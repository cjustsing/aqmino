import Foundation
#if canImport(XCTest)
import XCTest
#endif
@testable import AqminoCore

final class HydrationHistoryTests: XCTestCase {
    var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return value
    }
    func date(_ value: String) -> Date { ISO8601DateFormatter().date(from: value)! }
    func record(_ value: String, _ amount: Int = 250) -> HydrationRecord {
        HydrationRecord(operationID: UUID(), amountMl: amount, recordedAt: date(value), timeZoneIDAtCreation: "Asia/Shanghai", source: .quick)
    }

    func testTodayAndYesterdayUseHalfOpenLocalCalendarDays() throws {
        let records = [
            record("2026-10-10T23:59:59+08:00"),
            record("2026-10-11T00:00:00+08:00", 150),
            record("2026-10-11T23:59:59+08:00", 350),
            record("2026-10-12T00:00:00+08:00", 450),
            record("2026-10-13T00:00:00+08:00"),
        ]
        let now = date("2026-10-12T16:00:00+08:00")
        let today = HydrationHistory(records: records, period: .today, now: now, calendar: calendar)
        let yesterday = HydrationHistory(records: records, period: .yesterday, now: now, calendar: calendar)
        XCTAssertEqual(today.totalMl, 450); XCTAssertEqual(today.count, 1)
        XCTAssertEqual(yesterday.totalMl, 500); XCTAssertEqual(yesterday.count, 2)
        XCTAssertEqual(yesterday.days.first?.records.map(\.amountMl), [350, 150])
    }

    func testSevenDayAverageIncludesUnrecordedDaysAndToday() throws {
        let records = [
            record("2026-10-05T23:59:59+08:00", 1000),
            record("2026-10-06T00:00:00+08:00", 150),
            record("2026-10-12T12:00:00+08:00", 200),
            record("2026-10-13T00:00:00+08:00", 1000),
        ]
        let history = HydrationHistory(records: records, period: .last7Days, now: date("2026-10-12T16:00:00+08:00"), calendar: calendar)
        XCTAssertEqual(history.days.count, 7)
        XCTAssertEqual(history.days.map(\.totalMl), [150, 0, 0, 0, 0, 0, 200])
        XCTAssertEqual(history.totalMl, 350); XCTAssertEqual(history.averageMl, 50)
        XCTAssertEqual(history.count, 2); XCTAssertEqual(history.recordedDayCount, 2)
    }

    func testThirtyDaysCrossMonthBoundaryWithoutLosingRecords() throws {
        let records = [record("2026-09-12T23:59:59+08:00", 1000), record("2026-09-13T00:00:00+08:00", 600)]
        let history = HydrationHistory(records: records, period: .last30Days, now: date("2026-10-12T16:00:00+08:00"), calendar: calendar)
        XCTAssertEqual(history.days.count, 30)
        XCTAssertEqual(history.days.first?.date, date("2026-09-13T00:00:00+08:00"))
        XCTAssertEqual(history.days.last?.date, date("2026-10-12T00:00:00+08:00"))
        XCTAssertEqual(history.totalMl, 600); XCTAssertEqual(history.averageMl, 20)
    }

    func testYearBoundaryAndEmptyPeriods() throws {
        let now = date("2026-01-01T10:00:00+08:00")
        let yesterday = HydrationHistory(records: [], period: .yesterday, now: now, calendar: calendar)
        XCTAssertEqual(yesterday.days.first?.date, date("2025-12-31T00:00:00+08:00"))
        for period in HydrationHistoryPeriod.allCases {
            let empty = HydrationHistory(records: [], period: period, now: now, calendar: calendar)
            XCTAssertEqual(empty.days.count, period.dayCount)
            XCTAssertEqual(empty.totalMl, 0); XCTAssertEqual(empty.averageMl, 0)
            XCTAssertEqual(empty.recordedDayCount, 0); XCTAssertEqual(empty.count, 0)
        }
    }

    func testHistoryUsesViewingTimeZoneAndMatchesTodaySummary() throws {
        var state = StateSnapshot()
        state.records = [record("2026-10-12T00:15:00+08:00", 350)]
        let now = date("2026-10-12T23:30:00+08:00")
        var pacific = calendar; pacific.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let history = HydrationHistory(records: state.records, period: .today, now: now, calendar: pacific)
        let yesterday = HydrationHistory(records: state.records, period: .yesterday, now: now, calendar: pacific)
        XCTAssertEqual(history.totalMl, DailySummary(state: state, now: now, calendar: pacific).totalMl)
        XCTAssertEqual(history.totalMl, 0); XCTAssertEqual(yesterday.totalMl, 350)
    }

    func testDSTTransitionsUseCalendarDaysRatherThanTwentyFourHours() throws {
        var eastern = calendar; eastern.timeZone = TimeZone(identifier: "America/New_York")!
        for (now, first, records) in [
            ("2026-03-09T12:00:00-04:00", "2026-03-03T00:00:00-05:00", [record("2026-03-08T23:30:00-04:00")]),
            ("2026-11-02T12:00:00-05:00", "2026-10-27T00:00:00-04:00", [record("2026-11-01T01:30:00-04:00"), record("2026-11-01T01:30:00-05:00")]),
        ] {
            let history = HydrationHistory(records: records, period: .last7Days, now: date(now), calendar: eastern)
            XCTAssertEqual(history.days.count, 7)
            XCTAssertEqual(history.days.first?.date, date(first))
            XCTAssertEqual(history.count, records.count)
            XCTAssertEqual(history.recordedDayCount, 1)
        }
    }

    func testHistoricalDeleteAndUndoKeepTodaysTotalAndReminderTime() throws {
        var state = StateSnapshot(); state.preferences.onboardingComplete = true
        let historical = record("2026-10-11T10:00:00+08:00", 250)
        state.records = [historical, record("2026-10-12T09:00:00+08:00", 300)]
        let now = date("2026-10-12T10:00:00+08:00")
        let context = RuleContext(now: now, calendar: calendar)
        let planned = try StateReducer.apply(.reconcile(reset: true), operationID: UUID(), to: state, context: context).state
        let deleted = try StateReducer.apply(.deleteRecord(historical.id), operationID: UUID(), to: planned, context: context)
        XCTAssertEqual(deleted.state.runtime.nextReminder, planned.runtime.nextReminder)
        XCTAssertEqual(DailySummary(state: deleted.state, now: now, calendar: calendar).totalMl, 300)
        XCTAssertEqual(HydrationHistory(records: deleted.state.records, period: .yesterday, now: now, calendar: calendar).totalMl, 0)
        let restored = try StateReducer.apply(.undo(try XCTUnwrap(deleted.undo)), operationID: UUID(), to: deleted.state, context: context).state
        XCTAssertEqual(restored.runtime.nextReminder, planned.runtime.nextReminder)
        XCTAssertEqual(HydrationHistory(records: restored.records, period: .yesterday, now: now, calendar: calendar).totalMl, 250)
    }
}
