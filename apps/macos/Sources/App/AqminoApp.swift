import AppKit
import AqminoCore

@main
struct AqminoLauncher {
    @MainActor static func main() {
        let app = NSApplication.shared
        if let iconURL = Bundle.main.url(forResource: "Aqmino", withExtension: "icns"),
           let icon = NSImage(contentsOf: iconURL) {
            app.applicationIconImage = icon
        }
        let delegate = AqminoAppDelegate(); app.delegate = delegate
        app.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) { app.run() }
    }
}

@MainActor
final class AqminoAppDelegate: NSObject, NSApplicationDelegate {
    private var model: AppModel?
    private var windows: WindowCoordinator?
    private var quitting = false
    func applicationDidFinishLaunching(_ notification: Notification) {
        if ProcessInfo.processInfo.environment["AQMINO_TEST_HOST"] == "1" { return }
        do {
            #if DEBUG
            let arguments = CommandLine.arguments
            if let index = arguments.firstIndex(of: "--preview-appearance"), arguments.count > index + 1 {
                NSApp.appearance = NSAppearance(named: arguments[index + 1] == "light" ? .aqua : .darkAqua)
            }
            #endif
            let directory: URL
            #if DEBUG
            if let index = arguments.firstIndex(of: "--data-directory"), arguments.count > index + 1 {
                directory = URL(fileURLWithPath: arguments[index + 1], isDirectory: true)
            } else { directory = try FileStateStore.defaultDirectory() }
            #else
            directory = try FileStateStore.defaultDirectory()
            #endif
            let model = AppModel(directory: directory); self.model = model
            let windows = WindowCoordinator(model: model); self.windows = windows
            makeMainMenu()
            model.onReady = { [weak model, weak windows] in
                if model?.loaded == true && model?.state.preferences.onboardingComplete == false { windows?.showWelcome(); return }
                #if DEBUG
                if arguments.contains("--show-panel") { windows?.showPanel() }
                #endif
            }
            model.start()
        } catch {
            let alert = NSAlert(); alert.messageText = L10n.text("未能打开数据目录", "Could not open the data folder")
            alert.informativeText = L10n.text("请检查本机应用支持目录的访问权限，然后重新启动水序。", "Check access to the Application Support folder, then restart Aqmino.")
            alert.runModal(); NSApp.terminate(nil)
        }
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        windows?.showPanel(); return true
    }
    func applicationWillTerminate(_ notification: Notification) { model?.stop() }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let model else { return .terminateNow }
        guard !quitting else { return .terminateLater }; quitting = true
        Task { await model.prepareForExit(); sender.reply(toApplicationShouldTerminate: true) }
        return .terminateLater
    }
    private func makeMainMenu() {
        let menu = NSMenu()
        let appMenu = NSMenu(); let appItem = NSMenuItem(); appItem.submenu = appMenu; menu.addItem(appItem)
        let panel = NSMenuItem(title: L10n.text("打开水序", "Open Aqmino"), action: #selector(panelAction), keyEquivalent: "d")
        panel.keyEquivalentModifierMask = [.command, .shift]; panel.target = self; appMenu.addItem(panel)
        let records = NSMenuItem(title: L10n.text("饮水记录", "Water history"), action: #selector(recordsAction), keyEquivalent: "r")
        records.keyEquivalentModifierMask = [.command, .shift]; records.target = self; appMenu.addItem(records)
        let settings = NSMenuItem(title: L10n.text("设置…", "Settings…"), action: #selector(settingsAction), keyEquivalent: ","); settings.target = self; appMenu.addItem(settings)
        appMenu.addItem(.separator())
        appMenu.addItem(NSMenuItem(title: L10n.text("退出水序", "Quit Aqmino"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        let fileMenu = NSMenu(title: L10n.text("文件", "File")); let fileItem = NSMenuItem(); fileItem.submenu = fileMenu; menu.addItem(fileItem)
        fileMenu.addItem(NSMenuItem(title: L10n.text("关闭窗口", "Close Window"), action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w"))
        let editMenu = NSMenu(title: L10n.text("编辑", "Edit")); let editItem = NSMenuItem(); editItem.submenu = editMenu; menu.addItem(editItem)
        for (title, action, key) in [
            (L10n.text("撤销", "Undo"), "undo:", "z"),
            (L10n.text("剪切", "Cut"), "cut:", "x"),
            (L10n.text("复制", "Copy"), "copy:", "c"),
            (L10n.text("粘贴", "Paste"), "paste:", "v"),
            (L10n.text("全选", "Select All"), "selectAll:", "a")
        ] { editMenu.addItem(NSMenuItem(title: title, action: Selector(action), keyEquivalent: key)) }
        NSApp.mainMenu = menu
    }
    @objc private func settingsAction() { windows?.showSettings(.reminders) }
    @objc private func panelAction() { windows?.showPanel() }
    @objc private func recordsAction() { windows?.showRecords() }
}
