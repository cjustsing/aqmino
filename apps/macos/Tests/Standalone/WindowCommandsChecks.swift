import AppKit

@MainActor
private final class CloseProbe: NSObject, NSWindowDelegate {
    var allowClose = false
    var attempts = 0
    var closed = false
    func windowShouldClose(_ sender: NSWindow) -> Bool { attempts += 1; return allowClose }
    func windowWillClose(_ notification: Notification) { closed = true }
}

@main
struct WindowCommandsChecks {
    static var failures = 0

    @MainActor
    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        if !condition() { failures += 1; print("FAIL: \(message)") }
    }

    @MainActor
    static func commandW(_ window: NSWindow) -> Bool {
        let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [.command],
                                    timestamp: 0, windowNumber: window.windowNumber, context: nil,
                                    characters: "w", charactersIgnoringModifiers: "w", isARepeat: false, keyCode: 13)!
        NSApp.mainMenu?.update()
        return NSApp.mainMenu?.performKeyEquivalent(with: event) ?? false
    }

    @MainActor
    static func commandItems(_ menu: NSMenu) -> [NSMenuItem] {
        menu.items.flatMap { item in
            (item.keyEquivalent == "w" && item.keyEquivalentModifierMask == [.command] ? [item] : [])
                + (item.submenu.map(commandItems) ?? [])
        }
    }

    @MainActor
    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)
        let delegate = AqminoAppDelegate(); app.delegate = delegate
        delegate.makeMainMenu()
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 160),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let probe = CloseProbe(); window.delegate = probe
        window.performClose(nil)
        guard probe.attempts == 1 && !probe.closed else { print("SETUP FAILED: hidden closable window must support the standard close delegate"); exit(2) }
        probe.attempts = 0
        // Hidden windows cannot become key. Keep the production key equivalent
        // and action, routing it to this check's window without showing any UI.
        // Active-window responder selection is covered by native acceptance.
        let commands = app.mainMenu.map(commandItems) ?? []
        expect(commands.allSatisfy { $0.target == nil }, "Cmd+W must use the active responder instead of a fixed production target")
        commands.forEach { $0.target = window }
        expect(!window.isVisible, "check must keep its window hidden")

        expect(commandW(window), "Cmd+W must be handled by the production main menu")
        expect(probe.attempts == 1 && !probe.closed, "Cmd+W must respect a window delegate that rejects closing")
        probe.allowClose = true
        expect(commandW(window), "Cmd+W must remain available for a closable key window")
        expect(probe.attempts == 2 && probe.closed, "Cmd+W must close the current window through performClose")
        expect(!delegate.applicationShouldTerminateAfterLastWindowClosed(app), "closing the last window must keep the menu-bar app running")
        expect(!window.isVisible, "check must never display a window")
        print("Window command checks: \(failures) assertion failures")
        if failures > 0 { exit(1) }
    }
}
