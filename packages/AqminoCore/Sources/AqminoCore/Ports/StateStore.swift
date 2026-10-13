import Foundation

public protocol StateStore: Sendable {
    func load() throws -> StateSnapshot
    func save(_ snapshot: StateSnapshot, previous: StateSnapshot) throws
    func clear(_ snapshot: StateSnapshot) throws
    func restoreBackup() throws -> StateSnapshot
}
