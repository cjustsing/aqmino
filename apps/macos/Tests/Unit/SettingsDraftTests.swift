import AqminoCore
import Foundation
#if canImport(XCTest)
import XCTest
#endif
#if !AQMINO_STANDALONE_CHECKS
@testable import Aqmino
#endif

final class SettingsDraftTests: XCTestCase {
    func testGoalNeedsUserInputAndDisabledGoalKeepsPreviouslyChosenValue() async throws {
        await MainActor.run {
            let draft = SettingsDraft(); draft.reset(ReminderPreferences())
            XCTAssertFalse(draft.dirty); XCTAssertFalse(draft.value.goalEnabled); XCTAssertEqual(draft.goal, "")
            draft.value.goalEnabled = true
            XCTAssertNil(draft.candidate)
            draft.goal = "1500"
            XCTAssertEqual(draft.candidate?.goalMl, 1500)
            var stored = ReminderPreferences(); stored.goalMl = 1500
            draft.reset(stored); draft.value.goalEnabled = true
            XCTAssertEqual(draft.candidate?.goalMl, 1500)
        }
    }
    func testSwitchingSectionsKeepsDraftAndCancelResetDiscardsIt() async throws {
        await MainActor.run {
            let draft = SettingsDraft(); let original = ReminderPreferences(); draft.reset(original)
            draft.amounts[0] = "200"; draft.section = .general; draft.section = .records
            XCTAssertTrue(draft.dirty); XCTAssertEqual(draft.amounts[0], "200")
            draft.reset(original); XCTAssertFalse(draft.dirty); XCTAssertEqual(draft.amounts[0], "150")
        }
    }
    func testDuplicateAmountsAndInvalidWindowPreventSaving() async throws {
        await MainActor.run {
            let draft = SettingsDraft(); draft.reset(ReminderPreferences())
            draft.amounts = ["250", "250", "350"]; XCTAssertNil(draft.candidate)
            draft.amounts = ["150", "250", "350"]; draft.value.startMinute = 1080
            XCTAssertNil(draft.candidate)
            draft.value.startMinute = 540; draft.interval = "200"; XCTAssertNil(draft.candidate)
            draft.interval = "45"; XCTAssertEqual(draft.candidate, ReminderPreferences())
        }
    }
}
