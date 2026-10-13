import AppKit
import Foundation

@MainActor
final class SystemEventObserver {
    private var tokens: [(NotificationCenter, NSObjectProtocol)] = []
    init(onSleep: @escaping @MainActor () -> Void, onResume: @escaping @MainActor () -> Void, onClockChange: @escaping @MainActor () -> Void) {
        let workspace = NSWorkspace.shared.notificationCenter
        func watch(_ center: NotificationCenter, _ name: Notification.Name, _ block: @escaping @MainActor () -> Void) {
            let token = center.addObserver(forName: name, object: nil, queue: .main) { _ in Task { @MainActor in block() } }
            tokens.append((center, token))
        }
        watch(workspace, NSWorkspace.willSleepNotification, onSleep)
        watch(workspace, NSWorkspace.sessionDidResignActiveNotification, onSleep)
        watch(workspace, NSWorkspace.didWakeNotification, onResume)
        watch(workspace, NSWorkspace.sessionDidBecomeActiveNotification, onResume)
        watch(.default, .NSSystemTimeZoneDidChange, onClockChange)
        watch(.default, .NSCalendarDayChanged, onClockChange)
        watch(.default, .NSSystemClockDidChange, onClockChange)
    }
    deinit { for (center, token) in tokens { center.removeObserver(token) } }
}
