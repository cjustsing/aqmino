import AppKit
import AqminoCore
import SwiftUI

@main
struct SettingsViewChecks {
    static var failures = 0

    @MainActor
    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        if !condition() { failures += 1; print("FAIL: \(message)") }
    }

    @MainActor
    static func pump(_ host: NSHostingView<SettingsView>, until condition: () -> Bool) {
        for _ in 0..<300 {
            host.needsLayout = true; host.layoutSubtreeIfNeeded()
            RunLoop.current.run(until: Date().addingTimeInterval(0.01))
            if condition() {
                for _ in 0..<5 {
                    host.needsLayout = true; host.layoutSubtreeIfNeeded()
                    RunLoop.current.run(until: Date().addingTimeInterval(0.01))
                }
                return
            }
        }
        failures += 1; print("FAIL: view update timed out")
    }

    @MainActor
    static func runCase(_ name: String, backupRecovery: Bool) throws {
        let before = failures
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("aqmino-settings-check-\(UUID().uuidString)")
        let store = FileStateStore(directory: directory)
        defer { try? FileManager.default.removeItem(at: directory) }
        var state = StateSnapshot()
        state.preferences.onboardingComplete = true
        state.preferences.weekdays = Set(1...7)
        state.preferences.startMinute = 0; state.preferences.endMinute = 1439
        state.preferences.intervalMinutes = 60
        state.preferences.quickAmounts = [120, 240, 480]
        state.preferences.goalEnabled = true; state.preferences.goalMl = 700
        try store.save(state, previous: state)
        if backupRecovery { try Data("corrupt test main".utf8).write(to: store.stateURL) }
        let model = AppModel(directory: directory)
        defer { model.stop() }
        model.notifications.onCapabilityRequest = {}
        let draft = SettingsDraft(); draft.reset(model.state.preferences)
        let host = NSHostingView(rootView: SettingsView(model: model, draft: draft, close: {}))
        host.frame = NSRect(x: 0, y: 0, width: 680, height: 580)
        let window = NSWindow(contentRect: host.frame, styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = host
        host.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        model.start()
        if backupRecovery {
            pump(host) { model.storageIssue != nil && !model.busy }
            expect(!model.loaded, "failed read must not make the default draft writable")
            expect(model.backupAvailable, "valid backup remains available")
            model.restoreBackup()
        }
        pump(host) { model.loaded && !model.busy }
        expect(model.loaded, "model finished loading")
        expect(model.state.preferences == state.preferences, "model loaded the saved preferences")
        expect(draft.candidate == state.preferences, "visible draft must use saved preferences after loading")
        expect(!draft.dirty, "loaded preferences must be the clean draft baseline")
        draft.value.soundEnabled = true
        model.refresh()
        pump(host) { !model.busy }
        expect(draft.candidate?.soundEnabled == true && draft.dirty, "ordinary refresh must preserve user edits after loading")
        expect(draft.candidate?.quickAmounts == state.preferences.quickAmounts, "saving a later edit must not reset saved quick amounts")
        expect(draft.candidate?.intervalMinutes == 60 && draft.candidate?.goalMl == 700, "saving a later edit must not reset saved interval or goal")
        for section in [SettingsSection.history, .data, .records, .support, .reminders] {
            draft.section = section
            pump(host) { !model.busy }
            expect(draft.candidate?.soundEnabled == true && draft.dirty, "switching between history, support and settings must preserve unsaved edits")
            expect(draft.candidate?.quickAmounts == state.preferences.quickAmounts, "window navigation must preserve the shared settings draft")
        }
        expect(!window.isVisible, "test must not show a window")
        print("\(failures == before ? "PASS" : "FAIL") \(name); windowVisible=\(window.isVisible)")
    }

    @MainActor
    static func main() throws {
        NSApplication.shared.setActivationPolicy(.prohibited)
        try runCase("settings opened before startup load", backupRecovery: false)
        try runCase("settings opened before valid backup recovery", backupRecovery: true)
        print("Settings view checks: \(failures) assertion failures")
        if failures > 0 { exit(1) }
    }
}
