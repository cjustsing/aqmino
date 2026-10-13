import AppKit
import Combine
import SwiftUI

@MainActor
final class WindowCoordinator: NSObject, NSPopoverDelegate, NSWindowDelegate {
    enum WindowKind { case settings, welcome }
    private let model: AppModel
    private let settingsDraft = SettingsDraft()
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let popover = NSPopover()
    private var windows: [WindowKind: NSWindow] = [:]
    private var panelController: NSHostingController<AnyView>?
    private var appActiveObserver: NSObjectProtocol?
    private var attentionSubscription: AnyCancellable?

    init(model: AppModel) {
        self.model = model; super.init()
        popover.behavior = .transient; popover.delegate = self
        popover.appearance = NSApp.appearance
        let maximumHeight = max(300, min(600, (NSScreen.main?.visibleFrame.height ?? 800) - 48))
        let panel = AnyView(MenuPopoverContent(model: model, maximumHeight: maximumHeight) { [weak self] height in
            self?.popover.contentSize = NSSize(width: 360, height: height)
        })
        let hosting = NSHostingController(rootView: panel); panelController = hosting
        popover.contentViewController = hosting; popover.contentSize = NSSize(width: 360, height: 440)
        if let button = statusItem.button {
            button.imagePosition = .imageOnly
            button.target = self; button.action = #selector(togglePanel)
        }
        attentionSubscription = model.$reminderAttention.removeDuplicates().sink { [weak self] attention in
            self?.updateStatusItem(attention: attention)
        }
        model.openPanel = { [weak self] in self?.showPanel() }
        model.openSettings = { [weak self] section in self?.showSettings(section) }
        model.openRecords = { [weak self] in self?.showRecords() }
        model.closeWelcome = { [weak self] in self?.windows[.welcome]?.close() }
        model.isFrontVisible = { [weak self] in self?.isFrontVisible ?? false }
        appActiveObserver = NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                if self.isFrontVisible { self.model.acknowledgeReminder() }
                self.model.refresh()
            }
        }
    }

    private func updateStatusItem(attention: Bool) {
        let description = attention
            ? L10n.text("水序，该喝水了，点击查看", "Aqmino, time for water. Click to open.")
            : L10n.text("水序，饮水记录与提醒", "Aqmino, water records and reminders")
        statusItem.button?.image = Self.statusImage(attention: attention)
        statusItem.button?.toolTip = description
        statusItem.button?.setAccessibilityLabel(description)
    }

    static func statusImage(attention: Bool) -> NSImage? {
        guard attention else {
            let image = NSImage(systemSymbolName: "drop.halffull", accessibilityDescription: nil)
                ?? NSImage(systemSymbolName: "drop", accessibilityDescription: nil)
            image?.isTemplate = true
            return image
        }
        guard let drop = NSImage(systemSymbolName: "drop.fill", accessibilityDescription: nil),
              let badge = NSImage(systemSymbolName: "circle.fill", accessibilityDescription: nil) else { return nil }
        let image = NSImage(size: NSSize(width: 20, height: 18), flipped: false) { _ in
            drop.draw(in: NSRect(x: 0, y: 0, width: 14, height: 17))
            badge.draw(in: NSRect(x: 14, y: 12, width: 6, height: 6))
            return true
        }
        image.isTemplate = true
        return image
    }

    var isFrontVisible: Bool {
        NSApp.isActive && (popover.isShown
            || (NSApp.keyWindow.map { $0.isVisible && !$0.isMiniaturized } ?? false)
            || windows.values.contains(where: { $0.isVisible && !$0.isMiniaturized }))
    }
    var visibleWindowCount: Int { windows.values.filter(\.isVisible).count }
    var panelShown: Bool { popover.isShown }
    @objc private func togglePanel() { if popover.isShown { popover.performClose(nil) } else { showPanel() } }
    func showPanel() {
        guard let button = statusItem.button else { return }
        model.acknowledgeReminder()
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
        popover.contentViewController?.view.window?.makeFirstResponder(nil)
        model.refresh()
    }
    func closePanel() { popover.performClose(nil) }
    func showSettings(_ section: SettingsSection) {
        model.acknowledgeReminder()
        closePanel(); settingsDraft.section = section
        if let existing = windows[.settings] { focus(existing); model.refresh(); return }
        settingsDraft.reset(model.state.preferences)
        let view = SettingsView(model: model, draft: settingsDraft) { [weak self] in self?.windows[.settings]?.close() }
        let window = makeWindow(kind: .settings, title: L10n.brand, size: NSSize(width: 780, height: 660), view: view)
        window.minSize = NSSize(width: 680, height: 608); focus(window); model.refresh()
    }
    func showRecords() {
        guard model.canShowRecords else { showPanel(); return }
        showSettings(.history)
    }
    func showWelcome() {
        model.acknowledgeReminder()
        if let existing = windows[.welcome] { focus(existing); return }
        focus(makeWindow(kind: .welcome, title: L10n.brand, size: NSSize(width: 420, height: 340), view: WelcomeView(model: model)))
    }
    private func makeWindow<V: View>(kind: WindowKind, title: String, size: NSSize, view: V) -> NSWindow {
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = title; window.isReleasedWhenClosed = false; window.delegate = self
        window.appearance = NSApp.appearance
        window.contentViewController = NSHostingController(rootView: view)
        window.setContentSize(size)
        window.center(); window.setFrameAutosaveName("Aqmino.\(kind)")
        windows[kind] = window; return window
    }
    private func focus(_ window: NSWindow) {
        NSApp.activate(ignoringOtherApps: true); window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(nil)
    }
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if sender === windows[.welcome], !model.state.preferences.onboardingComplete, model.canWrite {
            model.completeWelcome(enableNotifications: false); return false
        }
        return true
    }
    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        if let entry = windows.first(where: { $0.value === window }) { windows.removeValue(forKey: entry.key) }
    }
    func windowDidBecomeKey(_ notification: Notification) { model.acknowledgeReminder() }
    func popoverDidShow(_ notification: Notification) {
        // Start with the window focused; Tab can still move to the first control.
        popover.contentViewController?.view.window?.makeFirstResponder(nil)
    }
    func popoverDidClose(_ notification: Notification) { /* UI closes; model and scheduler stay alive. */ }
    deinit {
        if let appActiveObserver { NotificationCenter.default.removeObserver(appActiveObserver) }
    }
}
