import AqminoCore
import Foundation

enum StoreFailure: Error { case unreadable, backupAvailable, noBackup, deletionPending, unsupportedVersion }
enum StoreCheckpoint: CaseIterable { case backupWrite, stateWrite, intentWrite, backupCleanup, clearCommit, intentCleanup }

/// Synchronous file operations are called only from StateCoordinator's actor executor.
final class FileStateStore: StateStore, @unchecked Sendable {
    let directory: URL
    var stateURL: URL { directory.appendingPathComponent("state-v1.json") }
    var backupURL: URL { directory.appendingPathComponent("state-backup-v1.json") }
    var intentURL: URL { directory.appendingPathComponent("delete-intent-v1.json") }
    private let checkpoint: @Sendable (StoreCheckpoint) throws -> Void

    init(directory: URL, checkpoint: @escaping @Sendable (StoreCheckpoint) throws -> Void = { _ in }) {
        self.directory = directory; self.checkpoint = checkpoint
    }

    static func defaultDirectory() throws -> URL {
        try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("Aqmino", isDirectory: true)
    }

    var deletionPending: Bool { FileManager.default.fileExists(atPath: intentURL.path) }
    var backupAvailable: Bool {
        guard !deletionPending else { return false }
        if let data = try? Data(contentsOf: stateURL) {
            if isUnsupported(data) || (try? decode(data)) != nil { return false }
        }
        return (try? decode(Data(contentsOf: backupURL))) != nil
    }

    func load() throws -> StateSnapshot {
        if FileManager.default.fileExists(atPath: directory.path) {
            _ = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        }
        if deletionPending {
            do {
                let snapshot = try decode(Data(contentsOf: intentURL))
                guard snapshot.records.isEmpty, snapshot.occurrences.allSatisfy(\.invalidated) else { throw StoreFailure.deletionPending }
                try finishDeletion(snapshot)
                return snapshot
            } catch { throw StoreFailure.deletionPending }
        }
        let mainExists = FileManager.default.fileExists(atPath: stateURL.path)
        let backupExists = FileManager.default.fileExists(atPath: backupURL.path)
        if !mainExists && !backupExists { return StateSnapshot() }
        do {
            let data = try Data(contentsOf: stateURL)
            if isUnsupported(data) { throw StoreFailure.unsupportedVersion }
            return try decode(data)
        } catch StoreFailure.unsupportedVersion { throw StoreFailure.unsupportedVersion }
        catch { throw backupAvailable ? StoreFailure.backupAvailable : StoreFailure.unreadable }
    }

    func save(_ snapshot: StateSnapshot, previous: StateSnapshot) throws {
        guard !deletionPending else { throw StoreFailure.deletionPending }
        try snapshot.validated(); try previous.validated(); try ensureDirectory()
        try checkpoint(.backupWrite)
        try encode(previous).write(to: backupURL, options: .atomic)
        try checkpoint(.stateWrite)
        try encode(snapshot).write(to: stateURL, options: .atomic)
    }

    func restoreBackup() throws -> StateSnapshot {
        guard backupAvailable else { throw StoreFailure.noBackup }
        let snapshot = try decode(Data(contentsOf: backupURL))
        if FileManager.default.fileExists(atPath: stateURL.path) {
            let preserved = directory.appendingPathComponent("corrupt-state-\(UUID().uuidString).json")
            try FileManager.default.copyItem(at: stateURL, to: preserved)
        }
        try checkpoint(.stateWrite)
        try encode(snapshot).write(to: stateURL, options: .atomic)
        return snapshot
    }

    func clear(_ snapshot: StateSnapshot) throws {
        guard snapshot.records.isEmpty, snapshot.occurrences.allSatisfy(\.invalidated) else { throw ValidationError.invalidSnapshot }
        try snapshot.validated(); try ensureDirectory()
        try checkpoint(.intentWrite)
        try encode(snapshot).write(to: intentURL, options: .atomic)
        try finishDeletion(snapshot)
    }

    private func finishDeletion(_ snapshot: StateSnapshot) throws {
        try checkpoint(.backupCleanup)
        for url in try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) {
            if url.lastPathComponent == backupURL.lastPathComponent || url.lastPathComponent.hasPrefix("corrupt-state-") {
                try FileManager.default.removeItem(at: url)
            }
        }
        try checkpoint(.clearCommit)
        try encode(snapshot).write(to: stateURL, options: .atomic)
        try checkpoint(.intentCleanup)
        try FileManager.default.removeItem(at: intentURL)
    }

    private func ensureDirectory() throws { try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true) }
    private func isUnsupported(_ data: Data) -> Bool {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let version = object["schemaVersion"] as? Int else { return false }
        return version != 1
    }
    private func encode(_ snapshot: StateSnapshot) throws -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer(); try container.encode(f.string(from: date))
        }
        return try encoder.encode(snapshot)
    }
    private func decode(_ data: Data) throws -> StateSnapshot {
        let decoder = JSONDecoder()
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        decoder.dateDecodingStrategy = .custom { decoder in
            let text = try decoder.singleValueContainer().decode(String.self)
            guard let date = f.date(from: text) else { throw ValidationError.invalidSnapshot }; return date
        }
        let snapshot = try decoder.decode(StateSnapshot.self, from: data)
        try snapshot.validated(); return snapshot
    }
}
