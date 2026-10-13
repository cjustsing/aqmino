import AqminoCore
import Foundation
import UserNotifications

@main
struct AppModelChecks {
    enum CheckError: Error { case timeout, outsideTestWindow }

    @MainActor
    static func wait(_ condition: () -> Bool) async throws {
        for _ in 0..<600 {
            if condition() { return }
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        throw CheckError.timeout
    }

    @MainActor
    static func fixture() throws -> (AppModel, FileStateStore, UUID, Date) {
        let now = Date(), calendar = Calendar.autoupdatingCurrent
        let minute = calendar.component(.hour, from: now) * 60 + calendar.component(.minute, from: now)
        guard minute < 23 * 60 else { throw CheckError.outsideTestWindow }
        var state = StateSnapshot()
        state.preferences.onboardingComplete = true
        state.preferences.weekdays = Set(1...7)
        state.preferences.startMinute = 0; state.preferences.endMinute = 1439
        state.runtime.generation = 4
        state.runtime.anchor = now.addingTimeInterval(-3000)
        state.runtime.nextReminder = now.addingTimeInterval(-300)
        state.runtime.windowID = ReminderPlanner.windowID(now, preferences: state.preferences, calendar: calendar)
        let id = UUID()
        state.runtime.latestOccurrenceID = id
        state.occurrences = [ReminderOccurrence(id: id, createdAt: now.addingTimeInterval(-3000), amountMl: 250, interactionGeneration: 4)]
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("aqmino-app-model-\(UUID().uuidString)")
        let store = FileStateStore(directory: directory)
        try store.save(state, previous: StateSnapshot())
        return (AppModel(directory: directory), store, id, now)
    }

    @MainActor
    static func ready(_ model: AppModel) async throws {
        try await wait { model.loaded && !model.busy && model.plan.status != .setupRequired }
    }

    @MainActor
    static func withFixture(_ body: (AppModel, FileStateStore, UUID, Date) async throws -> Void) async throws {
        let (model, store, id, now) = try fixture()
        defer { model.stop(); try? FileManager.default.removeItem(at: store.directory) }
        try await body(model, store, id, now)
    }

    @MainActor
    static func fireReminder(_ model: AppModel, store: FileStateStore, inline: Bool = false) async throws -> UUID {
        var state = try store.load()
        let dueAt = Date().addingTimeInterval(0.2)
        state.runtime.anchor = dueAt.addingTimeInterval(-2700)
        state.runtime.nextReminder = dueAt
        try store.save(state, previous: state)
        model.isFrontVisible = { inline }
        model.start(); try await ready(model)
        try await wait { Date() >= dueAt }
        model.enqueue(.due(expectedGeneration: model.state.runtime.generation, inline: inline))
        try await wait { !model.busy && model.state.occurrences.count == 2 }
        return try XCTUnwrap(model.state.runtime.latestOccurrenceID)
    }

    @MainActor
    static func main() async {
        let cases: [(String, () async throws -> Void)] = [
            ("restart preserves a valid future reminder", {
                try await withFixture { model, store, _, _ in
                    var state = try store.load()
                    state.runtime.nextReminder = Date().addingTimeInterval(600)
                    state.runtime.anchor = state.runtime.nextReminder?.addingTimeInterval(-2700)
                    try store.save(state, previous: state)
                    state = try store.load()
                    model.start(); try await ready(model)
                    XCTAssertEqual(model.state.runtime, state.runtime)
                    XCTAssertEqual(model.state.occurrences, state.occurrences)
                }
            }),
            ("clock correction preserves a valid future reminder", {
                try await withFixture { model, store, _, _ in
                    var state = try store.load()
                    state.runtime.nextReminder = Date().addingTimeInterval(600)
                    state.runtime.anchor = state.runtime.nextReminder?.addingTimeInterval(-2700)
                    try store.save(state, previous: state)
                    state = try store.load()
                    model.start(); try await ready(model)
                    let scheduler = try XCTUnwrap(ReminderScheduler.latest)
                    let scheduled = scheduler.scheduleCount
                    SystemEventObserver.latest?.onClockChange()
                    try await wait { scheduler.scheduleCount > scheduled && !model.busy }
                    XCTAssertEqual(model.state.runtime, state.runtime)
                    XCTAssertEqual(model.state.occurrences, state.occurrences)
                }
            }),
            ("wake preserves a valid future reminder", {
                try await withFixture { model, store, _, _ in
                    var state = try store.load()
                    state.runtime.nextReminder = Date().addingTimeInterval(600)
                    state.runtime.anchor = state.runtime.nextReminder?.addingTimeInterval(-2700)
                    try store.save(state, previous: state)
                    state = try store.load()
                    model.start(); try await ready(model)
                    let scheduler = try XCTUnwrap(ReminderScheduler.latest)
                    let scheduled = scheduler.scheduleCount
                    SystemEventObserver.latest?.onSleep()
                    SystemEventObserver.latest?.onResume()
                    try await wait { scheduler.scheduleCount > scheduled && !model.busy }
                    XCTAssertEqual(model.state.runtime, state.runtime)
                    XCTAssertEqual(model.state.occurrences, state.occurrences)
                }
            }),
            ("clock correction and wake preserve a valid snooze", {
                try await withFixture { model, _, id, _ in
                    model.notifications.onAction?("snooze", id, {})
                    model.start(); try await ready(model)
                    let runtime = model.state.runtime
                    let scheduler = try XCTUnwrap(ReminderScheduler.latest)
                    var scheduled = scheduler.scheduleCount
                    SystemEventObserver.latest?.onClockChange()
                    try await wait { scheduler.scheduleCount > scheduled && !model.busy }
                    XCTAssertEqual(model.state.runtime, runtime)
                    scheduled = scheduler.scheduleCount
                    SystemEventObserver.latest?.onSleep()
                    SystemEventObserver.latest?.onResume()
                    try await wait { scheduler.scheduleCount > scheduled && !model.busy }
                    XCTAssertEqual(model.state.runtime, runtime)
                    XCTAssertEqual(model.state.occurrences.count, 1)
                }
            }),
            ("login registration updates independently of hydration settings", {
                try await withFixture { model, store, _, _ in
                    model.start(); try await ready(model)
                    let preferences = model.state.preferences
                    let records = model.state.records
                    model.setLoginEnabled(true)
                    XCTAssertTrue(model.loginStatus == .enabled)
                    XCTAssertTrue(model.loginIssue == nil)
                    model.setLoginEnabled(false)
                    XCTAssertTrue(model.loginStatus == .disabled)
                    XCTAssertEqual(model.login.requestedChanges, [true, false])
                    XCTAssertEqual(try store.load().preferences, preferences)
                    XCTAssertEqual(model.state.records, records)
                }
            }),
            ("pending login approval can be cancelled and refreshed", {
                try await withFixture { model, _, _, _ in
                    model.start(); try await ready(model)
                    model.login.requiresApproval = true
                    model.setLoginEnabled(true)
                    XCTAssertTrue(model.loginStatus == .requiresApproval)
                    model.setLoginEnabled(false)
                    XCTAssertTrue(model.loginStatus == .disabled)
                    model.login.status = .enabled
                    model.refresh()
                    try await wait { model.loginStatus == .enabled && !model.busy }
                }
            }),
            ("login failure is shown and a successful retry clears it", {
                try await withFixture { model, _, _, _ in
                    model.start(); try await ready(model)
                    model.login.registrationError = NSError(domain: "LoginItemCheck", code: 1, userInfo: [NSLocalizedDescriptionKey: "registration failed"])
                    model.setLoginEnabled(true)
                    XCTAssertTrue(model.loginStatus == .disabled)
                    XCTAssertTrue(model.loginIssue?.contains("registration failed") == true)
                    model.login.registrationError = nil
                    model.setLoginEnabled(true)
                    XCTAssertTrue(model.loginStatus == .enabled)
                    XCTAssertTrue(model.loginIssue == nil)
                }
            }),
            ("test notifications leave reminder attention and the normal cycle unchanged", {
                try await withFixture { model, _, _, _ in
                    model.start(); try await ready(model)
                    let next = model.state.runtime.nextReminder
                    model.testNotification(sound: false)
                    try await wait { !model.testingNotification }
                    XCTAssertFalse(model.reminderAttention)
                    XCTAssertTrue(model.state.records.isEmpty)
                    XCTAssertEqual(model.state.runtime.nextReminder, next)
                }
            }),
            ("background reminder marks the menu bar until acknowledged", {
                try await withFixture { model, store, _, _ in
                    let id = try await fireReminder(model, store: store)
                    XCTAssertTrue(model.reminderAttention)
                    let generation = model.state.runtime.generation
                    let next = model.state.runtime.nextReminder
                    model.acknowledgeReminder()
                    XCTAssertFalse(model.reminderAttention)
                    XCTAssertEqual(model.state.runtime.generation, generation)
                    XCTAssertEqual(model.state.runtime.nextReminder, next)
                    XCTAssertTrue(model.state.records.isEmpty)
                    model.enqueue(.delivery(id, .submitted))
                    try await wait { !model.busy }
                    XCTAssertFalse(model.reminderAttention, "Late delivery confirmation cannot mark a seen reminder again")
                }
            }),
            ("inline reminder is already visible and does not mark the menu bar", {
                try await withFixture { model, store, _, _ in
                    let id = try await fireReminder(model, store: store, inline: true)
                    XCTAssertFalse(model.reminderAttention)
                    XCTAssertEqual(model.inlineOccurrence?.id, id)
                }
            }),
            ("notification record and snooze both clear menu bar attention", {
                for action in ["record", "snooze"] {
                    try await withFixture { model, store, _, _ in
                        let id = try await fireReminder(model, store: store)
                        XCTAssertTrue(model.reminderAttention)
                        var completed = false
                        model.notifications.onAction?(action, id, { completed = true })
                        try await wait { !model.busy && completed }
                        XCTAssertFalse(model.reminderAttention)
                        if action == "record" { XCTAssertEqual(model.state.records.count, 1) }
                        else { XCTAssertTrue(model.state.records.isEmpty); XCTAssertTrue(model.state.runtime.snoozeUntil != nil) }
                    }
                }
            }),
            ("dismissing a banner keeps menu bar attention", {
                try await withFixture { model, store, _, _ in
                    let id = try await fireReminder(model, store: store)
                    var opened = false
                    model.openPanel = { opened = true }
                    model.notifications.onAction?(UNNotificationDismissActionIdentifier, id, {})
                    XCTAssertTrue(model.reminderAttention)
                    XCTAssertFalse(opened)
                }
            }),
            ("failed save keeps the unhandled reminder until retry succeeds", {
                try await withFixture { model, store, _, _ in
                    _ = try await fireReminder(model, store: store)
                    try FileManager.default.removeItem(at: store.stateURL)
                    try FileManager.default.createDirectory(at: store.stateURL, withIntermediateDirectories: false)
                    model.enqueue(.record(amount: 250, source: .quick))
                    try await wait { !model.busy && model.storageIssue != nil }
                    XCTAssertTrue(model.reminderAttention)
                    XCTAssertTrue(model.state.records.isEmpty)
                    try FileManager.default.removeItem(at: store.stateURL)
                    try Data(contentsOf: store.backupURL).write(to: store.stateURL)
                    model.retryStorage(); try await wait { !model.busy && model.storageIssue == nil }
                    XCTAssertFalse(model.reminderAttention)
                    XCTAssertEqual(model.state.records.count, 1)
                }
            }),
            ("pause clears attention without adding a drink", {
                try await withFixture { model, store, _, _ in
                    _ = try await fireReminder(model, store: store)
                    model.enqueue(.pause(minutes: 30)); try await wait { !model.busy }
                    XCTAssertFalse(model.reminderAttention)
                    XCTAssertTrue(model.state.records.isEmpty)
                    XCTAssertTrue(model.hasPause)
                }
            }),
            ("queued snooze survives startup restoration", {
                try await withFixture { model, store, id, now in
                    model.notifications.onAction?("snooze", id, {})
                    model.start(); try await ready(model)
                    XCTAssertTrue(model.state.runtime.snoozeUntil != nil)
                    XCTAssertTrue(abs((model.state.runtime.nextReminder ?? .distantPast).timeIntervalSince(now) - 600) < 3)
                    XCTAssertTrue(model.state.occurrences[0].consumed)
                    let disk = try store.load()
                    XCTAssertEqual(disk.revision, model.state.revision)
                    XCTAssertEqual(disk.runtime.generation, model.state.runtime.generation)
                    XCTAssertTrue(abs((disk.runtime.nextReminder ?? .distantPast).timeIntervalSince(model.state.runtime.nextReminder ?? .distantFuture)) < 0.002)
                }
            }),
            ("notification arriving during capability query is handled after it", {
                try await withFixture { model, _, id, now in
                    model.notifications.onCapabilityRequest = { model.notifications.onAction?("snooze", id, {}) }
                    model.start(); try await ready(model)
                    XCTAssertTrue(model.state.occurrences[0].consumed)
                    XCTAssertTrue(abs((model.state.runtime.snoozeUntil ?? .distantPast).timeIntervalSince(now) - 600) < 3)
                }
            }),
            ("queued record keeps its undo generation", {
                try await withFixture { model, _, id, _ in
                    model.notifications.onAction?("record", id, {})
                    model.start(); try await ready(model)
                    XCTAssertEqual(model.state.records.count, 1)
                    XCTAssertEqual(model.undo?.resultingGeneration, model.state.runtime.generation)
                    model.undoLast(); try await wait { !model.busy }
                    XCTAssertTrue(model.state.records.isEmpty)
                    XCTAssertTrue(model.state.occurrences[0].consumed)
                }
            }),
            ("duplicate callback only records once", {
                try await withFixture { model, _, id, _ in
                    model.notifications.onAction?("record", id, {})
                    model.notifications.onAction?("record", id, {})
                    model.start(); try await ready(model)
                    XCTAssertEqual(model.state.records.count, 1)
                    XCTAssertEqual(model.state.records[0].amountMl, 250)
                }
            }),
            ("unknown action does not replay an overdue opportunity", {
                try await withFixture { model, _, _, now in
                    model.notifications.onAction?("snooze", UUID(), {})
                    model.start(); try await ready(model)
                    XCTAssertTrue(model.state.records.isEmpty)
                    XCTAssertFalse(model.state.occurrences[0].consumed)
                    XCTAssertTrue(abs((model.state.runtime.nextReminder ?? .distantPast).timeIntervalSince(now) - 2700) < 3)
                }
            }),
            ("notification record remains available when permission is denied", {
                try await withFixture { model, _, id, _ in
                    model.notifications.testCapability = .denied
                    model.notifications.onAction?("record", id, {})
                    model.start(); try await ready(model)
                    XCTAssertEqual(model.state.records.count, 1)
                    XCTAssertEqual(model.plan.status, .permissionDenied)
                }
            }),
            ("startup action save failure can be retried without duplicate records", {
                try await withFixture { model, store, id, _ in
                    model.notifications.onAction?("record", id, {})
                    model.notifications.onCapabilityRequest = {
                        try? FileManager.default.removeItem(at: store.stateURL)
                        try? FileManager.default.createDirectory(at: store.stateURL, withIntermediateDirectories: false)
                    }
                    model.start(); try await wait { model.storageIssue != nil && !model.busy }
                    XCTAssertTrue(model.state.records.isEmpty)
                    try FileManager.default.removeItem(at: store.stateURL)
                    try Data(contentsOf: store.backupURL).write(to: store.stateURL, options: .atomic)
                    model.retryStorage(); try await ready(model)
                    XCTAssertNil(model.storageIssue)
                    XCTAssertEqual(model.state.records.count, 1)
                    XCTAssertEqual(model.undo?.resultingGeneration, model.state.runtime.generation)
                    let disk = try store.load()
                    XCTAssertEqual(disk.revision, model.state.revision)
                    XCTAssertEqual(disk.records.map(\.id), model.state.records.map(\.id))
                }
            }),
            ("quitting during startup cannot reopen the interface", {
                try await withFixture { model, _, _, _ in
                    var readyCount = 0, quitFinished = false
                    model.onReady = { readyCount += 1 }
                    model.notifications.onCapabilityRequest = {
                        Task { await model.prepareForExit(); quitFinished = true }
                    }
                    model.start(); try await wait { quitFinished }
                    try await Task.sleep(nanoseconds: 200_000_000)
                    XCTAssertEqual(readyCount, 0)
                }
            }),
            ("activation refresh during startup cannot replace a queued snooze", {
                try await withFixture { model, _, id, now in
                    model.notifications.onCapabilityRequest = {
                        model.notifications.onAction?("snooze", id, {})
                        model.refresh()
                    }
                    model.start(); try await ready(model)
                    XCTAssertTrue(model.state.occurrences[0].consumed)
                    XCTAssertTrue(abs((model.state.runtime.snoozeUntil ?? .distantPast).timeIntervalSince(now) - 600) < 3)
                    XCTAssertTrue(abs((model.state.runtime.nextReminder ?? .distantPast).timeIntervalSince(now) - 600) < 3)
                }
            }),
            ("activation refresh during startup keeps notification undo generation", {
                try await withFixture { model, _, id, _ in
                    model.notifications.onCapabilityRequest = {
                        model.notifications.onAction?("record", id, {})
                        model.refresh()
                    }
                    model.start(); try await ready(model)
                    XCTAssertEqual(model.state.records.count, 1)
                    XCTAssertEqual(model.undo?.resultingGeneration, model.state.runtime.generation)
                }
            }),
            ("permission changes after startup still reset the cycle", {
                try await withFixture { model, _, id, _ in
                    model.notifications.onAction?("snooze", id, {})
                    model.start(); try await ready(model)
                    let generation = model.state.runtime.generation
                    model.notifications.testCapability = .denied
                    model.refresh(); try await wait { !model.busy && model.plan.status == .permissionDenied }
                    XCTAssertTrue(model.state.runtime.generation > generation)
                    XCTAssertNil(model.state.runtime.snoozeUntil)
                    let restoredAt = Date()
                    model.notifications.testCapability = .available
                    model.refresh(); try await wait { !model.busy && model.plan.canDeliver }
                    XCTAssertTrue(abs((model.state.runtime.nextReminder ?? .distantPast).timeIntervalSince(restoredAt) - 2700) < 3)
                }
            }),
            ("read failure retry refreshes permission before scheduling", {
                try await withFixture { model, store, _, _ in
                    let saved = try Data(contentsOf: store.stateURL)
                    try Data("invalid test snapshot".utf8).write(to: store.stateURL, options: .atomic)
                    model.start(); try await wait { model.storageIssue != nil && !model.busy }
                    XCTAssertFalse(model.loaded)
                    try saved.write(to: store.stateURL, options: .atomic)
                    model.retryStorage(); try await ready(model)
                    XCTAssertEqual(model.capability, .available)
                    XCTAssertTrue(model.plan.canDeliver)
                    XCTAssertNil(model.storageIssue)
                }
            }),
            ("finishing welcome while quitting cannot reopen a panel", {
                try await withFixture { model, store, _, _ in
                    var initial = try store.load()
                    initial.preferences.onboardingComplete = false
                    try store.save(initial, previous: initial)
                    var opened = 0
                    model.openPanel = { opened += 1 }
                    model.start(); try await wait { model.loaded && !model.busy }
                    model.completeWelcome(enableNotifications: false)
                    await model.prepareForExit()
                    XCTAssertEqual(opened, 0)
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
        print("\(passed)/\(cases.count) AppModel cases passed; \(CheckLog.failures) assertion failures")
        exit(CheckLog.failures == 0 ? 0 : 1)
    }
}
