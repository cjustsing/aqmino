import AppKit
import AqminoCore
import Foundation

/// Real native observer and timer, with isolated storage and fake notification
/// and login adapters. Posts process-local events without changing the Mac clock.
@main
struct ScheduleRecoveryChecks {
    enum CheckFailure: Error { case timeout, outsideTestWindow }

    @MainActor
    static func wait(_ predicate: () -> Bool) async throws {
        for _ in 0..<600 {
            if predicate() { return }
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        throw CheckFailure.timeout
    }

    @MainActor
    static func ready(_ model: AppModel) async throws {
        try await wait { model.loaded && !model.busy && model.plan.canDeliver }
    }

    @MainActor
    static func fixture(offset: TimeInterval = 600, _ body: (AppModel, StateSnapshot) async throws -> Void) async throws {
        let now = Date(), calendar = Calendar.autoupdatingCurrent
        guard calendar.component(.hour, from: now) < 23 else { throw CheckFailure.outsideTestWindow }
        var state = StateSnapshot()
        state.preferences.onboardingComplete = true
        state.preferences.weekdays = Set(1...7)
        state.preferences.startMinute = 0; state.preferences.endMinute = 1439
        state.runtime.generation = 4
        state.runtime.nextReminder = now.addingTimeInterval(offset)
        state.runtime.anchor = state.runtime.nextReminder?.addingTimeInterval(-2700)
        state.runtime.windowID = ReminderPlanner.windowID(now, preferences: state.preferences, calendar: calendar)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("aqmino-native-recovery-\(UUID().uuidString)")
        let store = FileStateStore(directory: directory)
        try store.save(state, previous: StateSnapshot())
        state = try store.load()
        let model = AppModel(directory: directory)
        defer { model.stop(); try? FileManager.default.removeItem(at: directory) }
        do { try await body(model, state) }
        catch { await model.prepareForExit(); throw error }
        await model.prepareForExit()
    }

    @MainActor
    static func clockChange(_ model: AppModel) async throws {
        let requestedAt = Date()
        NotificationCenter.default.post(name: .NSSystemClockDidChange, object: nil)
        try await wait { model.now >= requestedAt && !model.busy }
    }

    @MainActor
    static func wake(_ model: AppModel) async throws {
        let requestedAt = Date()
        NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.didWakeNotification, object: nil)
        try await wait { model.now >= requestedAt && !model.busy }
    }

    @MainActor
    static func main() async {
        let cases: [(String, () async throws -> Void)] = [
            ("native clock events preserve the original future plan repeatedly", {
                try await fixture { model, state in
                    model.start(); try await ready(model)
                    for _ in 0..<3 { try await clockChange(model) }
                    XCTAssertEqual(model.state.runtime, state.runtime)
                    XCTAssertTrue(model.state.occurrences.isEmpty)
                }
            }),
            ("native wake resumes a future plan without resetting its cycle", {
                try await fixture { model, state in
                    model.start(); try await ready(model)
                    NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.willSleepNotification, object: nil)
                    try await Task.sleep(nanoseconds: 50_000_000)
                    try await wake(model)
                    XCTAssertEqual(model.state.runtime, state.runtime)
                    XCTAssertTrue(model.state.occurrences.isEmpty)
                }
            }),
            ("native wake skips a reminder missed by less than one second", {
                try await fixture(offset: 0.3) { model, _ in
                    model.start(); try await ready(model)
                    NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.willSleepNotification, object: nil)
                    try await Task.sleep(nanoseconds: 450_000_000)
                    XCTAssertTrue(model.state.occurrences.isEmpty)
                    let resumedAt = Date()
                    try await wake(model)
                    XCTAssertTrue(model.state.occurrences.isEmpty)
                    XCTAssertTrue(abs((model.state.runtime.nextReminder ?? .distantPast).timeIntervalSince(resumedAt) - 2700) < 2)
                }
            }),
            ("restart skips a reminder missed by one second", {
                try await fixture(offset: -1) { model, _ in
                    let restartedAt = Date()
                    model.start(); try await ready(model)
                    XCTAssertTrue(model.state.occurrences.isEmpty)
                    XCTAssertTrue(abs((model.state.runtime.nextReminder ?? .distantPast).timeIntervalSince(restartedAt) - 2700) < 2)
                }
            }),
            ("clock recovery invalidates a timer awaiting notification capability", {
                try await fixture(offset: 0.2) { model, state in
                    model.start(); try await ready(model)
                    model.notifications.onCapabilityRequest = {
                        NotificationCenter.default.post(name: .NSSystemClockDidChange, object: nil)
                    }
                    try await wait { model.state.runtime.generation > state.runtime.generation && !model.busy }
                    try await Task.sleep(nanoseconds: 150_000_000)
                    XCTAssertTrue(model.state.occurrences.isEmpty)
                    XCTAssertFalse(model.reminderAttention)
                    XCTAssertTrue((model.state.runtime.nextReminder ?? .distantPast).timeIntervalSinceNow > 2698)
                }
            }),
            ("clock recovery during startup preserves a valid saved plan", {
                try await fixture { model, state in
                    model.notifications.onCapabilityRequest = {
                        NotificationCenter.default.post(name: .NSSystemClockDidChange, object: nil)
                    }
                    model.start(); try await ready(model)
                    XCTAssertEqual(model.state.runtime, state.runtime)
                    XCTAssertTrue(model.state.occurrences.isEmpty)
                }
            }),
        ]
        var passed = 0
        for (name, body) in cases {
            let before = CheckLog.failures
            do { try await body() } catch { XCTFail("\(name): \(error)") }
            if CheckLog.failures == before { passed += 1; print("PASS \(name)") }
            else { print("FAIL \(name)") }
        }
        print("\(passed)/\(cases.count) native recovery cases passed; \(CheckLog.failures) assertion failures")
        exit(CheckLog.failures == 0 ? 0 : 1)
    }
}
