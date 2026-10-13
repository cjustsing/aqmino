import Foundation
#if canImport(XCTest)
import XCTest
#endif
#if !AQMINO_STANDALONE_CHECKS
@testable import Aqmino
#endif

final class NotificationAdapterTests: XCTestCase {
    func testRepeatedTestsAreIndependentNotificationsWithoutWaterActions() async throws {
        await MainActor.run {
            let first = NotificationAdapter.makeTestRequest(sound: false)
            let second = NotificationAdapter.makeTestRequest(sound: true)
            XCTAssertFalse(first.identifier == second.identifier)
            XCTAssertTrue(first.identifier.hasPrefix("aqmino.test."))
            XCTAssertTrue(second.identifier.hasPrefix("aqmino.test."))
            XCTAssertTrue(first.content.userInfo.isEmpty)
            XCTAssertEqual(first.content.categoryIdentifier, "")
            XCTAssertNil(first.content.sound)
            XCTAssertFalse(second.content.sound == nil)
        }
    }
    func testConcurrentTestSendIsRejectedBeforeSubmission() throws {
        var gate = TestNotificationGate()
        let now = Date(timeIntervalSince1970: 1_000)
        try gate.begin(at: now)
        do { try gate.begin(at: now); XCTFail("A second in-flight request must not be accepted") }
        catch { XCTAssertEqual(error as? NotificationFailure, .testInProgress) }
        XCTAssertTrue(gate.sending)
        gate.finish(at: now, submitted: true)
        XCTAssertFalse(gate.sending)
    }
    func testSuccessfulTestSendHasExplicitCooldownAndAllowsExactBoundary() throws {
        var gate = TestNotificationGate()
        let now = Date(timeIntervalSince1970: 1_000)
        try gate.begin(at: now); gate.finish(at: now, submitted: true)
        do { try gate.begin(at: now.addingTimeInterval(1.5)); XCTFail("Cooldown must report an unsent request") }
        catch { XCTAssertEqual(error as? NotificationFailure, .testRateLimited(seconds: 4)) }
        XCTAssertFalse(gate.sending)
        try gate.begin(at: now.addingTimeInterval(5))
        XCTAssertTrue(gate.sending)
    }
    func testFailedTestSendCanBeRetriedImmediately() throws {
        var gate = TestNotificationGate()
        let now = Date(timeIntervalSince1970: 1_000)
        try gate.begin(at: now); gate.finish(at: now, submitted: false)
        try gate.begin(at: now)
        XCTAssertTrue(gate.sending)
    }
}
