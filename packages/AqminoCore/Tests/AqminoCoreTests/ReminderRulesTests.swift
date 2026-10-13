import Foundation
#if canImport(XCTest)
import XCTest
#endif
@testable import AqminoCore

final class ReminderRulesTests: XCTestCase {
    var calendar: Calendar {
        var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "Asia/Shanghai")!; return c
    }
    func date(_ text: String) -> Date {
        let f = ISO8601DateFormatter(); return f.date(from: text + "+08:00")!
    }
    func context(_ time: String, capability: NotificationCapability = .available) -> RuleContext {
        RuleContext(now: date("2026-10-12T" + time + ":00"), calendar: calendar, notifications: capability)
    }
    func initial() -> StateSnapshot { var s = StateSnapshot(); s.preferences.onboardingComplete = true; return s }
    func apply(_ command: BusinessCommand, _ state: StateSnapshot, at time: String, id: UUID = UUID()) throws -> CommandResult {
        try StateReducer.apply(command, operationID: id, to: state, context: context(time))
    }
    func assertNext(_ state: StateSnapshot, _ expected: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(state.runtime.nextReminder, date(expected), file: file, line: line)
    }

    func testBeforeWindowAndFirstEnable_T01_T02() throws {
        let early = try apply(.reconcile(reset: true), initial(), at: "08:50")
        assertNext(early.state, "2026-10-12T09:45:00")
        let inside = try apply(.reconcile(reset: true), initial(), at: "10:00")
        assertNext(inside.state, "2026-10-12T10:45:00")
    }
    func testClearRejectsADeletionUndoCreatedBeforeErasure() throws {
        let recorded = try apply(.record(amount: 250, source: .quick), initial(), at: "10:00").state
        let deleted = try apply(.deleteRecord(recorded.records[0].id), recorded, at: "10:01")
        let token = try XCTUnwrap(deleted.undo)
        let cleared = try apply(.clearRecords, deleted.state, at: "10:01").state
        XCTAssertThrowsError(try apply(.undo(token), cleared, at: "10:01"))
        XCTAssertTrue(cleared.records.isEmpty)
    }
    func testClearRejectsAnInsertionUndoCreatedBeforeErasure() throws {
        let recorded = try apply(.record(amount: 250, source: .quick), initial(), at: "10:00")
        let token = try XCTUnwrap(recorded.undo)
        let cleared = try apply(.clearRecords, recorded.state, at: "10:00").state
        XCTAssertThrowsError(try apply(.undo(token), cleared, at: "10:00"))
    }
    func testDeletingAnImportedRecordCreatesAnUndoReceipt() throws {
        let recorded = try apply(.record(amount: 350, source: .custom), initial(), at: "10:00").state
        var imported = recorded; imported.receipts = []
        let deleted = try apply(.deleteRecord(imported.records[0].id), imported, at: "10:01")
        let restored = try apply(.undo(try XCTUnwrap(deleted.undo)), deleted.state, at: "10:01")
        XCTAssertEqual(restored.state.records, imported.records)
    }
    func testRecordResetsCycleAndIdempotentOperation_T03() throws {
        let start = try apply(.reconcile(reset: true), initial(), at: "10:00").state
        let id = UUID()
        let result = try apply(.record(amount: 250, source: .quick), start, at: "10:20", id: id)
        assertNext(result.state, "2026-10-12T11:05:00")
        XCTAssertEqual(DailySummary(state: result.state, now: context("10:20").now, calendar: calendar).totalMl, 250)
        let retry = try apply(.record(amount: 250, source: .quick), result.state, at: "10:21", id: id)
        XCTAssertTrue(retry.duplicate); XCTAssertEqual(retry.state, result.state)
    }
    func testTimedPauseExpiryAndRecordingPreservesPause_T04_T13() throws {
        let paused = try apply(.pause(minutes: 30), initial(), at: "10:00").state
        let recorded = try apply(.record(amount: 250, source: .quick), paused, at: "10:05").state
        XCTAssertEqual(recorded.runtime.pauseUntil, context("10:30").now)
        let expired = try apply(.reconcile(reset: false), recorded, at: "10:30")
        assertNext(expired.state, "2026-10-12T11:15:00")
        let lateWake = try apply(.recoverSchedule, recorded, at: "11:00")
        assertNext(lateWake.state, "2026-10-12T11:45:00")
    }
    func testSnoozeUsesActionTimeAndOldSnoozeCannotOverwrite_T05_T13() throws {
        let start = try apply(.reconcile(reset: true), initial(), at: "09:15").state
        let due = try apply(.due(expectedGeneration: start.runtime.generation, inline: true), start, at: "10:00")
        let id = try XCTUnwrap(due.occurrence?.id)
        let snooze = try apply(.snooze(id), due.state, at: "10:02")
        assertNext(snooze.state, "2026-10-12T10:12:00")
        let paused = try apply(.pause(minutes: 30), due.state, at: "10:01").state
        let stale = try apply(.snooze(id), paused, at: "10:02")
        XCTAssertTrue(stale.duplicate); XCTAssertEqual(stale.state.runtime.pauseUntil, paused.runtime.pauseUntil)
        XCTAssertNil(stale.state.runtime.snoozeUntil)
    }
    func testEndExclusiveAndNextWorkday_T06_T07() throws {
        let late = try apply(.record(amount: 250, source: .quick), initial(), at: "17:30")
        assertNext(late.state, "2026-10-13T09:45:00")
        var state = initial(); state.runtime.nextReminder = context("18:00").now
        let due = try apply(.due(expectedGeneration: 0, inline: false), state, at: "18:00")
        XCTAssertNil(due.occurrence); assertNext(due.state, "2026-10-13T09:45:00")
    }
    func testTodayPauseExpiresOnCalendarDate_T08() throws {
        let friday = RuleContext(now: date("2026-10-16T10:00:00"), calendar: calendar)
        let paused = try StateReducer.apply(.pauseToday, operationID: UUID(), to: initial(), context: friday).state
        let saturday = RuleContext(now: date("2026-10-17T10:00:00"), calendar: calendar)
        let result = try StateReducer.apply(.reconcile(reset: false), operationID: UUID(), to: paused, context: saturday)
        XCTAssertNil(result.state.runtime.pausedDay)
        assertNext(result.state, "2026-10-19T09:45:00")
    }
    func testWakeAndLateTimerDoNotCatchUp_T09_T10() throws {
        let start = try apply(.reconcile(reset: true), initial(), at: "10:00").state
        let wake = try apply(.recoverSchedule, start, at: "11:00")
        assertNext(wake.state, "2026-10-12T11:45:00")
        let late = try apply(.due(expectedGeneration: start.runtime.generation, inline: false), start, at: "10:47")
        XCTAssertNil(late.occurrence); assertNext(late.state, "2026-10-12T11:32:00")
    }
    func testGoalStopsThenDeleteRestartsAndOverflowRemains_T11() throws {
        var s = initial(); s.preferences.goalEnabled = true; s.preferences.goalMl = 200
        let result = try apply(.record(amount: 250, source: .quick), s, at: "10:00")
        XCTAssertEqual(result.plan.status, .goalReached)
        let summary = DailySummary(state: result.state, now: context("10:00").now, calendar: calendar)
        XCTAssertEqual(summary.totalMl, 250); XCTAssertEqual(summary.progress, 1)
        let deleted = try apply(.deleteRecord(result.state.records[0].id), result.state, at: "10:10")
        assertNext(deleted.state, "2026-10-12T10:55:00")
        XCTAssertNil(DailySummary(state: initial(), now: context("10:00").now, calendar: calendar).progress)
    }
    func testNotificationConsumptionSurvivesDeletingRecord_T12() throws {
        let start = try apply(.reconcile(reset: true), initial(), at: "09:15").state
        let due = try apply(.due(expectedGeneration: start.runtime.generation, inline: false), start, at: "10:00")
        let id = try XCTUnwrap(due.occurrence?.id)
        var p = due.state.preferences; p.lastAmount = 350
        let changed = try apply(.preferences(p), due.state, at: "10:01").state
        let first = try apply(.notificationRecord(id), changed, at: "10:02").state
        XCTAssertEqual(first.records[0].amountMl, 250, "The sent button's capacity must stay frozen")
        let deleted = try apply(.deleteRecord(first.records[0].id), first, at: "10:03").state
        let replay = try apply(.notificationRecord(id), deleted, at: "10:04")
        XCTAssertTrue(replay.duplicate); XCTAssertTrue(replay.state.records.isEmpty)
    }
    func testPermissionDoesNotBlockRecordingAndRestoreStartsFullInterval_T14() throws {
        let denied = context("10:00", capability: .denied)
        let recorded = try StateReducer.apply(.record(amount: 250, source: .quick), operationID: UUID(), to: initial(), context: denied)
        XCTAssertEqual(recorded.plan.status, .permissionDenied); XCTAssertEqual(recorded.state.records.count, 1)
        let restored = try apply(.reconcile(reset: true), recorded.state, at: "10:20")
        assertNext(restored.state, "2026-10-12T11:05:00")
    }
    func testFutureColdPlanCanBePreserved_T15() throws {
        let started = try apply(.reconcile(reset: true), initial(), at: "10:00").state
        let restored = try apply(.recoverSchedule, started, at: "10:10")
        assertNext(restored.state, "2026-10-12T10:45:00")
    }
    func testRepeatedSmallClockCorrectionsKeepTheOriginalCycle() throws {
        let started = try apply(.reconcile(reset: true), initial(), at: "09:00").state
        var state = started
        for time in ["09:10", "09:22", "09:38"] {
            let restored = try apply(.recoverSchedule, state, at: time)
            XCTAssertEqual(restored.state.runtime, started.runtime)
            XCTAssertNil(restored.occurrence)
            XCTAssertTrue(restored.state.occurrences.isEmpty)
            state = restored.state
        }
        assertNext(state, "2026-10-12T09:45:00")
    }
    func testSmallBackwardCorrectionImmediatelyAfterStartingKeepsFuturePlan() throws {
        let started = try apply(.reconcile(reset: true), initial(), at: "10:00").state
        for seconds in [0.1, 1.0, 60.0] {
            let corrected = RuleContext(now: context("10:00").now.addingTimeInterval(-seconds), calendar: calendar)
            let restored = try StateReducer.apply(.recoverSchedule, operationID: UUID(), to: started, context: corrected)
            XCTAssertEqual(restored.state.runtime, started.runtime)
        }
        let moved = RuleContext(now: context("10:00").now.addingTimeInterval(-120), calendar: calendar)
        let replanned = try StateReducer.apply(.recoverSchedule, operationID: UUID(), to: started, context: moved)
        XCTAssertEqual(replanned.state.runtime.nextReminder, moved.now.addingTimeInterval(2700))
    }
    func testRecoverySkipsDueAndJustMissedRemindersWithoutTimerGrace() throws {
        let started = try apply(.reconcile(reset: true), initial(), at: "10:00").state
        for seconds in [0.0, 1.0, 60.0, 3600.0] {
            let resumed = RuleContext(now: context("10:45").now.addingTimeInterval(seconds), calendar: calendar)
            let recovered = try StateReducer.apply(.recoverSchedule, operationID: UUID(), to: started, context: resumed)
            XCTAssertNil(recovered.occurrence)
            XCTAssertTrue(recovered.state.occurrences.isEmpty)
            XCTAssertEqual(recovered.state.runtime.nextReminder, resumed.now.addingTimeInterval(2700))
            let stale = try StateReducer.apply(.due(expectedGeneration: started.runtime.generation, inline: false), operationID: UUID(), to: recovered.state, context: resumed)
            XCTAssertNil(stale.occurrence)
            XCTAssertEqual(stale.state.runtime.nextReminder, recovered.state.runtime.nextReminder)
        }
    }
    func testOrdinaryTimerStillHasItsLateDeliveryGrace() throws {
        let started = try apply(.reconcile(reset: true), initial(), at: "10:00").state
        let result = try apply(.due(expectedGeneration: started.runtime.generation, inline: false), started, at: "10:46")
        XCTAssertTrue(result.occurrence != nil)
        assertNext(result.state, "2026-10-12T11:31:00")
    }
    func testRecoveryPreservesAndExpiresSnoozeWithoutCatchUp() throws {
        let started = try apply(.reconcile(reset: true), initial(), at: "09:15").state
        let due = try apply(.due(expectedGeneration: started.runtime.generation, inline: false), started, at: "10:00")
        let snoozed = try apply(.snooze(try XCTUnwrap(due.occurrence?.id)), due.state, at: "10:02").state
        let recovered = try apply(.recoverSchedule, snoozed, at: "10:05")
        XCTAssertEqual(recovered.state.runtime, snoozed.runtime)
        let expired = try apply(.recoverSchedule, snoozed, at: "10:12")
        XCTAssertNil(expired.state.runtime.snoozeUntil)
        assertNext(expired.state, "2026-10-12T10:57:00")
        XCTAssertEqual(expired.state.occurrences, snoozed.occurrences)
        XCTAssertNil(expired.occurrence)
    }
    func testRecoveryPreservesFirstReminderAcrossNightAndWeekend() throws {
        for (start, resume, expected) in [
            ("2026-10-12T18:10:00", "2026-10-13T09:22:00", "2026-10-13T09:45:00"),
            ("2026-10-16T18:10:00", "2026-10-19T09:22:00", "2026-10-19T09:45:00")
        ] {
            let started = try StateReducer.apply(.reconcile(reset: true), operationID: UUID(), to: initial(), context: RuleContext(now: date(start), calendar: calendar)).state
            let recovered = try StateReducer.apply(.recoverSchedule, operationID: UUID(), to: started, context: RuleContext(now: date(resume), calendar: calendar))
            assertNext(recovered.state, expected)
            XCTAssertEqual(recovered.state.runtime.generation, started.runtime.generation)
            XCTAssertNil(recovered.occurrence)
        }
    }
    func testRecoveryRejectsAnOverlyDistantOrOutsideWindowPlan() throws {
        var started = try apply(.reconcile(reset: true), initial(), at: "10:00").state
        started.runtime.nextReminder = context("15:00").now
        let distant = try apply(.recoverSchedule, started, at: "10:10")
        assertNext(distant.state, "2026-10-12T10:55:00")
        started.runtime.nextReminder = context("18:00").now
        let outside = try apply(.recoverSchedule, started, at: "17:50")
        assertNext(outside.state, "2026-10-13T09:45:00")
        XCTAssertNil(outside.occurrence)
    }
    func testRecoveryReevaluatesTimezoneAndChangedWindow() throws {
        let started = try apply(.reconcile(reset: true), initial(), at: "10:00").state
        var movedCalendar = calendar; movedCalendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        let moved = RuleContext(now: context("10:10").now, calendar: movedCalendar)
        let recovered = try StateReducer.apply(.recoverSchedule, operationID: UUID(), to: started, context: moved)
        XCTAssertEqual(recovered.state.runtime.nextReminder, moved.now.addingTimeInterval(2700))
        XCTAssertTrue(recovered.state.runtime.generation > started.runtime.generation)
        var changed = started; changed.preferences.intervalMinutes = 30
        let replanned = try apply(.recoverSchedule, changed, at: "10:10")
        assertNext(replanned.state, "2026-10-12T10:40:00")
    }
    func testRecoveryPreservesValidPausesAndSkipsExpiredPauseTimers() throws {
        let paused = try apply(.pause(minutes: 30), initial(), at: "10:00").state
        let recovered = try apply(.recoverSchedule, paused, at: "10:29")
        XCTAssertEqual(recovered.state.runtime.pauseUntil, paused.runtime.pauseUntil)
        XCTAssertEqual(recovered.plan.status, .pausedUntil(context("10:30").now))
        XCTAssertNil(recovered.state.runtime.nextReminder)
        let expired = try apply(.recoverSchedule, paused, at: "11:00")
        assertNext(expired.state, "2026-10-12T11:45:00")
        XCTAssertNil(expired.state.runtime.pauseUntil)
        XCTAssertNil(expired.occurrence)
        let today = try apply(.pauseToday, initial(), at: "10:00").state
        let stillPaused = try apply(.recoverSchedule, today, at: "11:00")
        XCTAssertEqual(stillPaused.plan.status, .pausedToday)
        XCTAssertNil(stillPaused.state.runtime.nextReminder)
    }
    func testTimezoneChangesTodayRangeAndClearsDayPause_T16() throws {
        var s = initial()
        s = try apply(.record(amount: 250, source: .quick), s, at: "00:15").state
        s = try apply(.pauseToday, s, at: "00:20").state
        var pacific = calendar; pacific.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let c = RuleContext(now: context("23:30").now, calendar: pacific)
        XCTAssertEqual(DailySummary(state: s, now: c.now, calendar: pacific).totalMl, 0)
        let otherDate = RuleContext(now: context("00:20").now, calendar: pacific)
        let moved = try StateReducer.apply(.reconcile(reset: true), operationID: UUID(), to: s, context: otherDate)
        XCTAssertNil(moved.state.runtime.pausedDay)
    }
    func testDSTDayAndMissingOrRepeatedBoundaries_T17() throws {
        var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "America/New_York")!
        let f = ISO8601DateFormatter()
        let spring = f.date(from: "2026-03-08T12:00:00Z")!
        let autumn = f.date(from: "2026-11-01T12:00:00Z")!
        XCTAssertEqual(c.dateInterval(of: .day, for: spring)?.duration, 23 * 3600)
        XCTAssertEqual(c.dateInterval(of: .day, for: autumn)?.duration, 25 * 3600)
        var p = ReminderPreferences(); p.weekdays = [7]; p.startMinute = 150; p.endMinute = 240
        let missing = try XCTUnwrap(ReminderPlanner.window(on: spring, preferences: p, calendar: c))
        XCTAssertEqual(c.component(.hour, from: missing.start), 3)
        p.startMinute = 90
        let repeated = try XCTUnwrap(ReminderPlanner.window(on: autumn, preferences: p, calendar: c))
        XCTAssertEqual(repeated.start, f.date(from: "2026-11-01T05:30:00Z"))
    }
    func testDispatchFailureDoesNotResetOrLoopAndInlineIsOneOccurrence_T18_T19() throws {
        let start = try apply(.reconcile(reset: true), initial(), at: "09:15").state
        let due = try apply(.due(expectedGeneration: start.runtime.generation, inline: true), start, at: "10:00")
        XCTAssertEqual(due.occurrence?.delivery, .inline); XCTAssertEqual(due.state.occurrences.count, 1)
        assertNext(due.state, "2026-10-12T10:45:00")
        let failure = try apply(.delivery(due.occurrence!.id, .failed), due.state, at: "10:01")
        XCTAssertEqual(failure.state.runtime.nextReminder, due.state.runtime.nextReminder)
        let oldTask = try apply(.due(expectedGeneration: start.runtime.generation, inline: true), due.state, at: "10:00")
        XCTAssertNil(oldTask.occurrence)
    }
    func testUndoRestoresPriorAnchorUnlessLaterEvent_T20() throws {
        let start = try apply(.reconcile(reset: true), initial(), at: "10:00").state
        let record = try apply(.record(amount: 250, source: .quick), start, at: "10:20")
        let token = try XCTUnwrap(record.undo)
        let undo = try StateReducer.apply(.undo(token), operationID: UUID(), to: record.state,
                                          context: RuleContext(now: context("10:20").now.addingTimeInterval(5), calendar: calendar))
        assertNext(undo.state, "2026-10-12T10:45:00"); XCTAssertTrue(undo.state.records.isEmpty)
        let paused = try StateReducer.apply(.pause(minutes: 30), operationID: UUID(), to: record.state,
                                            context: RuleContext(now: context("10:20").now.addingTimeInterval(1), calendar: calendar)).state
        let secondUndo = try StateReducer.apply(.undo(token), operationID: UUID(), to: paused,
                                                context: RuleContext(now: context("10:20").now.addingTimeInterval(5), calendar: calendar))
        XCTAssertEqual(secondUndo.state.runtime.pauseUntil, paused.runtime.pauseUntil)
        XCTAssertTrue(secondUndo.state.records.isEmpty)
    }
    func testValidationAndClearingInvalidatesOldNotifications() throws {
        for amount in [0, -1, 2001] { XCTAssertThrowsError(try apply(.record(amount: amount, source: .custom), initial(), at: "10:00")) }
        var p = ReminderPreferences(); p.quickAmounts = [250, 250, 350]; XCTAssertThrowsError(try p.validated())
        p = ReminderPreferences(); p.goalEnabled = true; XCTAssertThrowsError(try p.validated())
        let start = try apply(.reconcile(reset: true), initial(), at: "09:15").state
        let due = try apply(.due(expectedGeneration: start.runtime.generation, inline: false), start, at: "10:00")
        let cleared = try apply(.clearRecords, due.state, at: "10:01")
        XCTAssertThrowsError(try apply(.notificationRecord(due.occurrence!.id), cleared.state, at: "10:02"))
        XCTAssertEqual(cleared.state.preferences, due.state.preferences)
        XCTAssertTrue(cleared.state.occurrences.isEmpty, "Clearing removes reminder metadata as well as records")
    }
    func testOrdinaryDeleteKeepsCycleAndExpiredUndoIsRejected() throws {
        let start = try apply(.record(amount: 250, source: .quick), initial(), at: "10:00")
        let deleted = try apply(.deleteRecord(start.state.records[0].id), start.state, at: "10:20")
        assertNext(deleted.state, "2026-10-12T10:45:00")
        XCTAssertThrowsError(try apply(.undo(try XCTUnwrap(deleted.undo)), deleted.state, at: "10:21"))
    }
    func testSnoozePastWindowWaitsUntilNextDay() throws {
        let start = try apply(.reconcile(reset: true), initial(), at: "17:10").state
        let due = try apply(.due(expectedGeneration: start.runtime.generation, inline: false), start, at: "17:55")
        let snoozed = try apply(.snooze(try XCTUnwrap(due.occurrence?.id)), due.state, at: "17:56")
        XCTAssertFalse(snoozed.duplicate)
        XCTAssertTrue(snoozed.state.occurrences[0].consumed)
        assertNext(snoozed.state, "2026-10-13T09:45:00")
        XCTAssertNil(snoozed.state.runtime.snoozeUntil)
    }
    func testSavingAnOldSettingsDraftPreservesLatestRecordedCapacity() throws {
        let stale = initial().preferences
        let recorded = try apply(.record(amount: 350, source: .quick), initial(), at: "10:00").state
        let saved = try apply(.preferences(stale), recorded, at: "10:01")
        XCTAssertEqual(saved.state.preferences.lastAmount, 350)
        assertNext(saved.state, "2026-10-12T10:45:00")
    }
    func testLastReminderRemainsDeliverableWhileFollowingCycleIsTomorrow() throws {
        let start = try apply(.reconcile(reset: true), initial(), at: "17:10").state
        let due = try apply(.due(expectedGeneration: start.runtime.generation, inline: false), start, at: "17:55")
        let occurrence = try XCTUnwrap(due.occurrence)
        XCTAssertTrue(ReminderPlanner.isEligibleNow(due.state, context: context("17:55")))
        XCTAssertFalse(ReminderPlanner.isEligibleNow(due.state, context: context("18:00")))
        let confirmed = try apply(.delivery(occurrence.id, .submitted), due.state, at: "17:55").state
        XCTAssertEqual(confirmed.runtime.generation, occurrence.interactionGeneration)
        assertNext(confirmed, "2026-10-13T09:45:00")
    }
    func testReadingFutureWindowPlanDoesNotInvalidateItsGeneration() throws {
        let state = try apply(.record(amount: 250, source: .quick), initial(), at: "17:30").state
        let refreshed = try apply(.reconcile(reset: false), state, at: "17:31").state
        XCTAssertEqual(refreshed.runtime.generation, state.runtime.generation)
        XCTAssertEqual(refreshed.runtime.nextReminder, state.runtime.nextReminder)
    }
}
