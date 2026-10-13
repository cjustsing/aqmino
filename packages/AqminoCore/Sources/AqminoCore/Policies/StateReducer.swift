import Foundation

public enum BusinessCommand: Sendable {
    case record(amount: Int, source: RecordSource)
    case preferences(ReminderPreferences)
    case pause(minutes: Int)
    case pauseToday
    case resume
    case deleteRecord(UUID)
    case undo(UndoToken)
    case notificationRecord(UUID)
    case snooze(UUID)
    case reconcile(reset: Bool)
    case recoverSchedule
    case due(expectedGeneration: UInt64, inline: Bool)
    case delivery(UUID, DeliveryResult)
    case clearRecords
}

public struct CommandResult: Sendable {
    public let state: StateSnapshot
    public let plan: ReminderPlan
    public let undo: UndoToken?
    public let occurrence: ReminderOccurrence?
    public let duplicate: Bool
    public init(state: StateSnapshot, plan: ReminderPlan, undo: UndoToken?, occurrence: ReminderOccurrence?, duplicate: Bool) {
        self.state = state; self.plan = plan; self.undo = undo; self.occurrence = occurrence; self.duplicate = duplicate
    }
}

public enum StateReducer {
    public static func apply(_ command: BusinessCommand, operationID: UUID, to original: StateSnapshot, context: RuleContext) throws -> CommandResult {
        var state = original
        if state.receipts.contains(where: { $0.operationID == operationID }) {
            let plan = ReminderPlanner.reconcile(&state, context: context)
            return CommandResult(state: original, plan: plan, undo: nil, occurrence: nil, duplicate: true)
        }
        var undoRecord: (UndoToken.Kind, HydrationRecord)?
        var occurrence: ReminderOccurrence?
        var duplicate = false
        var reset = false
        var recovering = false
        let previousRuntime = state.runtime
        func insert(amount: Int, source: RecordSource, occurrenceID: UUID? = nil) throws -> HydrationRecord {
            guard (1...2000).contains(amount) else { throw ValidationError.amount }
            let record = HydrationRecord(operationID: operationID, amountMl: amount, recordedAt: context.now,
                                         timeZoneIDAtCreation: context.calendar.timeZone.identifier, source: source, occurrenceID: occurrenceID)
            state.records.append(record); state.preferences.lastAmount = amount
            state.runtime.invalidate(anchor: context.now)
            return record
        }
        switch command {
        case let .record(amount, source): undoRecord = (.insertion, try insert(amount: amount, source: source))
        case let .preferences(preferences):
            try preferences.validated()
            let old = state.preferences
            state.preferences = preferences
            state.preferences.lastAmount = old.lastAmount
            if old.remindersEnabled != preferences.remindersEnabled || old.weekdays != preferences.weekdays || old.startMinute != preferences.startMinute || old.endMinute != preferences.endMinute || old.intervalMinutes != preferences.intervalMinutes || old.onboardingComplete != preferences.onboardingComplete {
                state.runtime.invalidate(anchor: context.now)
            }
        case let .pause(minutes):
            guard [30, 60].contains(minutes) else { throw ValidationError.interval }
            state.runtime.invalidate(); state.runtime.pausedDay = nil
            state.runtime.pauseUntil = context.now.addingTimeInterval(TimeInterval(minutes * 60))
        case .pauseToday:
            state.runtime.invalidate(); state.runtime.pauseUntil = nil
            state.runtime.pausedDay = ReminderPlanner.dayID(context.now, calendar: context.calendar)
        case .resume:
            state.runtime.pauseUntil = nil; state.runtime.pausedDay = nil; reset = true
        case let .deleteRecord(id):
            if let record = state.records.first(where: { $0.id == id }) {
                state.records.removeAll { $0.id == id }; undoRecord = (.deletion, record)
            } else { duplicate = true }
        case let .undo(token):
            // Clearing records removes receipt record IDs, invalidating old undo tokens.
            guard context.now < token.expiresAt,
                  state.receipts.contains(where: { $0.recordID == token.record.id }) else { throw ValidationError.expiredUndo }
            switch token.kind {
            case .insertion: state.records.removeAll { $0.id == token.record.id }
            case .deletion: if !state.records.contains(where: { $0.id == token.record.id }) { state.records.append(token.record) }
            }
            if state.runtime.generation == token.resultingGeneration {
                let generation = state.runtime.generation
                state.runtime = token.previousRuntime; state.runtime.generation = generation &+ 1
                if let next = state.runtime.nextReminder, next <= context.now { state.runtime.invalidate(anchor: context.now) }
            }
        case let .notificationRecord(id):
            guard let index = state.occurrences.firstIndex(where: { $0.id == id }), !state.occurrences[index].invalidated else { throw ValidationError.unknownOccurrence }
            if state.occurrences[index].consumed { duplicate = true; break }
            let amount = state.occurrences[index].amountMl
            state.occurrences[index].consumed = true
            undoRecord = (.insertion, try insert(amount: amount, source: .notification, occurrenceID: id))
        case let .snooze(id):
            guard let index = state.occurrences.firstIndex(where: { $0.id == id }), !state.occurrences[index].invalidated else { throw ValidationError.unknownOccurrence }
            let item = state.occurrences[index]
            guard !item.consumed, state.runtime.latestOccurrenceID == id, item.interactionGeneration == state.runtime.generation else { duplicate = true; break }
            guard ReminderPlanner.isEligibleNow(state, context: context) else { duplicate = true; break }
            state.occurrences[index].consumed = true
            state.runtime.invalidate(anchor: context.now)
            let snooze = context.now.addingTimeInterval(600)
            if let window = ReminderPlanner.window(on: context.now, preferences: state.preferences, calendar: context.calendar), snooze < window.end {
                state.runtime.snoozeUntil = snooze; state.runtime.nextReminder = snooze
            }
        case let .reconcile(shouldReset): reset = shouldReset
        case .recoverSchedule: recovering = true
        case let .due(expectedGeneration, inline):
            let plannedDate = state.runtime.nextReminder
            let plan = ReminderPlanner.reconcile(&state, context: context)
            guard expectedGeneration == state.runtime.generation else { duplicate = true; break }
            guard plan.canDeliver, let plannedDate, plannedDate <= context.now,
                  context.now.timeIntervalSince(plannedDate) <= 60 else {
                if let plannedDate, plannedDate <= context.now { state.runtime.invalidate(anchor: context.now) }
                break
            }
            state.runtime.invalidate(anchor: context.now)
            let item = ReminderOccurrence(id: UUID(), createdAt: context.now, amountMl: state.preferences.lastAmount,
                                          interactionGeneration: state.runtime.generation)
            state.runtime.latestOccurrenceID = item.id
            state.occurrences.append(item)
            if inline { state.occurrences[state.occurrences.count - 1].delivery = .inline }
            occurrence = state.occurrences.last
        case let .delivery(id, result):
            if let i = state.occurrences.firstIndex(where: { $0.id == id }) { state.occurrences[i].delivery = result }
        case .clearRecords:
            state.records = []; state.runtime.invalidate(anchor: context.now)
            state.runtime.latestOccurrenceID = nil
            // Unknown occurrences are rejected, so deleting their details cannot replay them.
            state.occurrences = []
            state.receipts = state.receipts.map { CommandReceipt(operationID: $0.operationID) }
        }
        let plan = ReminderPlanner.reconcile(&state, context: context, reset: reset, recovering: recovering)
        let undo = undoRecord.map { UndoToken(kind: $0.0, record: $0.1, previousRuntime: previousRuntime,
                                            resultingGeneration: state.runtime.generation, expiresAt: context.now.addingTimeInterval(10)) }
        state.receipts.append(CommandReceipt(operationID: operationID, recordID: undoRecord?.1.id))
        state.revision &+= 1
        try state.validated()
        return CommandResult(state: state, plan: plan, undo: undo, occurrence: occurrence, duplicate: duplicate)
    }
}
