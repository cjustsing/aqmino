import AppKit
import AqminoCore
import SwiftUI

@main
struct MenuPanelChecks {
    static var failures = 0

    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        if !condition() { failures += 1; print("FAIL: \(message)") }
    }

    static func checkActivity() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        func record(_ hour: Int, _ minute: Int, _ amount: Int, seconds: Int = 0, nanoseconds: Int = 0) -> HydrationRecord {
            let date = calendar.date(from: DateComponents(year: 2026, month: 10, day: 12, hour: hour, minute: minute, second: seconds, nanosecond: nanoseconds))!
            return HydrationRecord(operationID: UUID(), amountMl: amount, recordedAt: date,
                                   timeZoneIDAtCreation: "UTC", source: .quick)
        }
        var preferences = ReminderPreferences()
        let records = [record(16, 52, 450), record(10, 3, 330), record(11, 31, 450), record(15, 39, 450),
                       record(8, 59, 120), record(18, 1, 240), record(9, 0, 60), record(17, 59, 90, seconds: 59, nanoseconds: 999_000_000),
                       record(18, 0, 80), record(18, 0, 100, nanoseconds: 1_000_000)]
        let activity = TodayActivity(records: records, preferences: preferences, calendar: calendar)
        expect(activity.range == "09:00–18:00" && activity.buckets.count == 9, "configured clock range replaces the 24-hour axis")
        expect(activity.buckets.first?.amountMl == 60 && activity.buckets.last?.amountMl == 90, "start and the last fraction before the end belong to the chart")
        expect(activity.buckets.first { $0.startMinute == 600 }?.amountMl == 330, "hourly volume uses current local time rather than creation zone")
        expect(activity.outsideRecords.count == 4 && activity.outsideTotalMl == 540 && activity.outsideRecords.contains { $0.id == records[8].id },
               "end is exclusive, matching the reminder plan, and outside records remain accounted for")
        expect(activity.insideTotalMl == 1830 && activity.insideTotalMl + activity.outsideTotalMl == 2370, "chart and outside volumes reconcile with today's total")
        expect(activity.latest?.recordedAt == records[5].recordedAt, "latest record is selected by time, not input order")
        preferences.startMinute = 9 * 60 + 15; preferences.endMinute = 17 * 60 + 45
        let partial = TodayActivity(records: [record(9, 14, 100), record(9, 15, 120), record(10, 0, 250),
                                             record(17, 44, 300, seconds: 59, nanoseconds: 999_000_000), record(17, 45, 50, seconds: 1), record(18, 0, 80)],
                                    preferences: preferences, calendar: calendar)
        expect(partial.range == "09:15–17:45" && partial.buckets.first?.endMinute == 600 && partial.buckets.last?.startMinute == 1020,
               "partial hours preserve exact configured boundaries")
        expect(partial.insideTotalMl == 670 && partial.outsideTotalMl == 230, "partial-hour records are neither hidden nor duplicated")
        preferences.startMinute = 555; preferences.endMinute = 571; preferences.intervalMinutes = 15
        let short = TodayActivity(records: [record(9, 15, 120), record(9, 30, 250)], preferences: preferences, calendar: calendar)
        expect(short.buckets.count == 1 && short.duration == 16 && short.insideTotalMl == 370, "a short valid range has one correctly scaled bucket")
        preferences.startMinute = 0; preferences.endMinute = 1439
        let long = TodayActivity(records: records, preferences: preferences, calendar: calendar)
        expect(long.buckets.count == 24 && long.range == "00:00–23:59" && long.outsideRecords.isEmpty, "near-full-day range includes all daytime records")
        let empty = TodayActivity(records: [], preferences: preferences, calendar: calendar)
        expect(empty.insideTotalMl == 0 && empty.latest == nil && empty.outsideRecords.isEmpty, "empty chart has no invented amount or latest record")
        print("Today activity partition checks complete")
    }

    @MainActor
    static func pump(_ host: NSHostingView<MenuPanelView>, until condition: () -> Bool) {
        for _ in 0..<300 {
            host.layoutSubtreeIfNeeded()
            RunLoop.current.run(until: Date().addingTimeInterval(0.01))
            if condition() {
                for _ in 0..<5 {
                    host.layoutSubtreeIfNeeded()
                    RunLoop.current.run(until: Date().addingTimeInterval(0.01))
                }
                return
            }
        }
        failures += 1; print("FAIL: panel update timed out")
    }

    @MainActor
    static func checkHeight(_ host: NSHostingView<MenuPanelView>, _ state: String) {
        let height = host.fittingSize.height
        print("Panel \(state): \(height) pt")
        if height > 528 {
            failures += 1
            print("FAIL: \(state) overflows the existing 528 pt panel")
        }
    }

    @MainActor
    static func main() throws {
        checkActivity()
        NSApplication.shared.setActivationPolicy(.prohibited)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("aqmino-panel-check-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        var state = StateSnapshot()
        state.preferences.onboardingComplete = true
        state.preferences.goalEnabled = true; state.preferences.goalMl = 1500
        try FileStateStore(directory: directory).save(state, previous: state)
        let model = AppModel(directory: directory)
        defer { model.stop() }
        let host = NSHostingView(rootView: MenuPanelView(model: model))
        host.frame = NSRect(x: 0, y: 0, width: 360, height: 528)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = host
        model.start(); pump(host) { model.loaded && !model.busy }
        checkHeight(host, "goal enabled")
        model.enqueue(.record(amount: 250, source: .quick))
        pump(host) { !model.busy && model.summary.totalMl == 250 }
        checkHeight(host, "goal and undo feedback")
        model.enqueue(.pause(minutes: 30))
        pump(host) { !model.busy && model.hasPause }
        checkHeight(host, "paused with chart and undo feedback")
        model.enqueue(.resume)
        pump(host) { !model.busy && !model.hasPause }
        var preferences = model.state.preferences
        preferences.goalEnabled = false
        model.enqueue(.preferences(preferences))
        pump(host) { !model.busy && model.summary.goalMl == nil }
        checkHeight(host, "chart without daily goal")
        preferences.goalEnabled = true
        model.enqueue(.preferences(preferences))
        for _ in 0..<5 { model.enqueue(.record(amount: 2000, source: .quick)) }
        pump(host) { !model.busy && model.summary.totalMl == 10250 }
        checkHeight(host, "five-digit total with chart and undo feedback")
        preferences.startMinute = 555; preferences.endMinute = 1065
        model.enqueue(.preferences(preferences))
        pump(host) { !model.busy && model.state.preferences.startMinute == 555 }
        checkHeight(host, "partial-hour range and outside records")
        preferences.startMinute = 0; preferences.endMinute = 1439
        model.enqueue(.preferences(preferences))
        pump(host) { !model.busy && model.state.preferences.startMinute == 0 }
        checkHeight(host, "full-day range")
        if window.isVisible { failures += 1; print("FAIL: check must not show a window") }
        print("Menu panel checks: \(failures) assertion failures")
        if failures > 0 { exit(1) }
    }
}
