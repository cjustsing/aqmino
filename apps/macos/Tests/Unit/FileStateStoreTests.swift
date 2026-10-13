import AqminoCore
import Foundation
#if canImport(XCTest)
import XCTest
#endif
#if !AQMINO_STANDALONE_CHECKS
@testable import Aqmino
#endif

final class FileStateStoreTests: XCTestCase {
    enum Injected: Error { case failure }
    var directories: [URL] = []
    func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("aqmino-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true); directories.append(url); return url
    }
    override func tearDownWithError() throws { for url in directories { try FileManager.default.removeItem(at: url) } }
    func recorded() -> StateSnapshot {
        var s = StateSnapshot(); s.preferences.onboardingComplete = true; s.revision = 1
        s.records = [HydrationRecord(operationID: UUID(), amountMl: 250, recordedAt: Date(timeIntervalSince1970: 1791770400), timeZoneIDAtCreation: "Asia/Shanghai", source: .quick)]
        return s
    }
    func testRoundTripAndBackupKeepsPreviousConfirmedState() throws {
        let store = FileStateStore(directory: try directory())
        XCTAssertEqual(try store.load(), StateSnapshot())
        let one = recorded(); try store.save(one, previous: StateSnapshot())
        XCTAssertEqual(try store.load(), one)
        var two = one; two.revision += 1; two.records.append(HydrationRecord(operationID: UUID(), amountMl: 350, recordedAt: Date(timeIntervalSince1970: 1791771000), timeZoneIDAtCreation: "Asia/Shanghai", source: .custom))
        try store.save(two, previous: one)
        XCTAssertEqual(try store.load(), two)
        try Data("broken".utf8).write(to: store.stateURL)
        XCTAssertThrowsError(try store.load()); XCTAssertTrue(store.backupAvailable)
        XCTAssertEqual(try Data(contentsOf: store.stateURL), Data("broken".utf8), "Loading must not silently restore")
        XCTAssertEqual(try store.restoreBackup(), one)
    }
    func testWriteFailurePreservesMainAtBothStages() throws {
        for failure in [StoreCheckpoint.backupWrite, .stateWrite] {
            let url = try directory(); let good = FileStateStore(directory: url); let state = recorded()
            try good.save(state, previous: StateSnapshot())
            let failing = FileStateStore(directory: url) { if $0 == failure { throw Injected.failure } }
            var changed = state; changed.revision += 1; changed.records = []
            XCTAssertThrowsError(try failing.save(changed, previous: state))
            XCTAssertEqual(try good.load(), state)
            XCTAssertFalse(good.backupAvailable, "A valid main file must not offer an older backup as recovery")
        }
    }
    func testNewerSchemaNeverOffersDestructiveBackupRestore() throws {
        let store = FileStateStore(directory: try directory()); try store.save(recorded(), previous: StateSnapshot())
        let data = Data("{\"schemaVersion\":99}".utf8); try data.write(to: store.stateURL)
        XCTAssertThrowsError(try store.load()); XCTAssertFalse(store.backupAvailable)
        XCTAssertThrowsError(try store.restoreBackup()); XCTAssertEqual(try Data(contentsOf: store.stateURL), data)
    }
    func testDeleteRecoveryAtEveryTransactionStageCannotResurrectRecords() throws {
        for failure in [StoreCheckpoint.intentWrite, .backupCleanup, .clearCommit, .intentCleanup] {
            let url = try directory(); let good = FileStateStore(directory: url); let original = recorded()
            try good.save(original, previous: original)
            try Data("old copy".utf8).write(to: url.appendingPathComponent("corrupt-state-test.json"))
            let failing = FileStateStore(directory: url) { if $0 == failure { throw Injected.failure } }
            var cleared = original; cleared.records = []; cleared.revision += 1
            XCTAssertThrowsError(try failing.clear(cleared))
            if failure == .intentWrite {
                XCTAssertFalse(good.deletionPending); XCTAssertEqual(try good.load(), original)
            } else {
                XCTAssertTrue(good.deletionPending); XCTAssertFalse(good.backupAvailable)
                let recovered = try good.load()
                XCTAssertEqual(recovered, cleared); XCTAssertFalse(good.deletionPending)
                XCTAssertFalse(FileManager.default.fileExists(atPath: good.backupURL.path))
                XCTAssertFalse(FileManager.default.fileExists(atPath: url.appendingPathComponent("corrupt-state-test.json").path))
                XCTAssertEqual(recovered.preferences, original.preferences)
            }
        }
    }
    func testMalformedDeletionIntentBlocksReadWriteAndRestore() throws {
        let store = FileStateStore(directory: try directory()); let original = recorded()
        try store.save(original, previous: original)
        try Data("broken".utf8).write(to: store.intentURL)
        XCTAssertThrowsError(try store.load()); XCTAssertThrowsError(try store.save(original, previous: original))
        XCTAssertFalse(store.backupAvailable)
    }
    func testCoordinatorConcurrentCommandsAndFailedWriteDoNotPublishCandidate() async throws {
        let url = try directory(); let coordinator = StateCoordinator(store: FileStateStore(directory: url))
        _ = try await coordinator.load()
        let context = RuleContext(now: Date(timeIntervalSince1970: 1791770400), calendar: Calendar(identifier: .gregorian))
        try await withThrowingTaskGroup(of: Void.self) { group in
            for _ in 0..<20 { group.addTask { _ = try await coordinator.execute(.record(amount: 250, source: .quick), id: UUID(), context: context) } }
            try await group.waitForAll()
        }
        XCTAssertEqual(try FileStateStore(directory: url).load().records.count, 20)
        let failing = StateCoordinator(store: FileStateStore(directory: url) { if $0 == .stateWrite { throw Injected.failure } })
        _ = try await failing.load()
        do { _ = try await failing.execute(.record(amount: 350, source: .quick), id: UUID(), context: context); XCTFail("Expected failure") } catch { }
        XCTAssertEqual(try FileStateStore(directory: url).load().records.count, 20)
    }
}
