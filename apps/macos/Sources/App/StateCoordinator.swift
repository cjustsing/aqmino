import AqminoCore
import Foundation

actor StateCoordinator {
    private let store: FileStateStore
    private var confirmed: StateSnapshot?
    private var writable = false
    init(store: FileStateStore) { self.store = store }

    func load() throws -> StateSnapshot {
        do {
            let state = try store.load(); confirmed = state; writable = true; return state
        } catch { writable = false; throw error }
    }
    func restore() throws -> StateSnapshot {
        let state = try store.restoreBackup(); confirmed = state; writable = true; return state
    }
    func recoveryOptions() -> (backup: Bool, deletion: Bool) { (store.backupAvailable, store.deletionPending) }

    // No suspension between reading, reducing, writing and committing: actor reentrancy
    // cannot split this transaction. Calls arriving during I/O remain queued.
    func execute(_ command: BusinessCommand, id: UUID, context: RuleContext, retry: Bool = false) throws -> CommandResult {
        guard let confirmed, writable || retry else { throw StoreFailure.unreadable }
        guard !store.deletionPending else { throw StoreFailure.deletionPending }
        let result = try StateReducer.apply(command, operationID: id, to: confirmed, context: context)
        if result.duplicate && result.state == confirmed { return result }
        let isPlanning: Bool
        switch command { case .reconcile, .recoverSchedule: isPlanning = true; default: isPlanning = false }
        if isPlanning, result.state.runtime == confirmed.runtime {
            return CommandResult(state: confirmed, plan: result.plan, undo: nil, occurrence: nil, duplicate: false)
        }
        do {
            if case .clearRecords = command { try store.clear(result.state) }
            else { try store.save(result.state, previous: confirmed) }
            self.confirmed = result.state; writable = true; return result
        } catch { writable = false; throw error }
    }
}
