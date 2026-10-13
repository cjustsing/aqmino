import AqminoCore
import Foundation
import UserNotifications

@MainActor
final class NotificationAdapter: NSObject, UNUserNotificationCenterDelegate {
    private let center = UNUserNotificationCenter.current()
    var onAction: ((String, UUID?, @escaping () -> Void) -> Void)?
    var isFrontVisible: (() -> Bool)?
    private var testGate = TestNotificationGate()

    override init() { super.init(); center.delegate = self }

    func capability() async -> NotificationCapability {
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus != .notDetermined else { return .notDetermined }
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional,
              settings.alertSetting == .enabled || settings.notificationCenterSetting == .enabled else { return .denied }
        return settings.alertSetting == .enabled && settings.alertStyle != .none ? .available : .centerOnly
    }
    func requestAuthorization() async throws { _ = try await center.requestAuthorization(options: [.alert, .sound]) }

    func registerCategories(state: StateSnapshot) {
        let capacities = Set(state.occurrences.filter { !$0.invalidated }.map(\.amountMl) + state.preferences.quickAmounts + [state.preferences.lastAmount])
        let categories = capacities.map { amount in
            let record = UNNotificationAction(identifier: "record", title: L10n.text("记录 \(amount) ml", "Record \(amount) ml"), options: [])
            let snooze = UNNotificationAction(identifier: "snooze", title: L10n.text("10 分钟后", "In 10 minutes"), options: [])
            return UNNotificationCategory(identifier: "water.amount.\(amount)", actions: [record, snooze], intentIdentifiers: [], options: [])
        }
        center.setNotificationCategories(Set(categories))
    }

    func send(_ occurrence: ReminderOccurrence, sound: Bool, isStillCurrent: @escaping @MainActor () -> Bool) async throws -> Bool {
        let capability = await capability()
        guard capability == .available || capability == .centerOnly, isStillCurrent() else { return false }
        await clearReminders()
        // Clearing crosses an async boundary, so validate generation again immediately before submission.
        guard isStillCurrent() else { return false }
        let content = UNMutableNotificationContent()
        content.title = L10n.text("喝口水，稍作休息。", "Take a sip. Take a moment.")
        content.body = L10n.text("给自己片刻休息。", "Take a short break.")
        content.categoryIdentifier = "water.amount.\(occurrence.amountMl)"
        content.userInfo = ["occurrenceID": occurrence.id.uuidString]
        content.interruptionLevel = .active
        content.sound = sound ? .default : nil
        let request = UNNotificationRequest(identifier: "aqmino.reminder.\(occurrence.id.uuidString)", content: content, trigger: nil)
        try await center.add(request); return true
    }
    func sendTest(sound: Bool) async throws -> NotificationCapability {
        try testGate.begin(at: Date())
        var submitted = false
        defer { testGate.finish(at: Date(), submitted: submitted) }
        let capability = await capability()
        guard capability == .available || capability == .centerOnly else { throw NotificationFailure.unavailable }
        try await center.add(Self.makeTestRequest(sound: sound))
        submitted = true
        return capability
    }
    static func makeTestRequest(sound: Bool) -> UNNotificationRequest {
        let content = UNMutableNotificationContent(); content.title = L10n.text("水序测试通知", "Aqmino test notification")
        content.body = L10n.text("提醒已就绪。这条测试不会记录饮水。", "Reminders are ready. This test does not log water.")
        content.interruptionLevel = .active
        content.sound = sound ? .default : nil
        // Each test is a new event rather than an update to the previous request.
        return UNNotificationRequest(identifier: "aqmino.test.\(UUID().uuidString)", content: content, trigger: nil)
    }
    func clearReminders() async {
        let delivered = await center.deliveredNotifications()
        center.removeDeliveredNotifications(withIdentifiers: delivered.map(\.request.identifier).filter { $0.hasPrefix("aqmino.reminder.") })
        let pending = await center.pendingNotificationRequests()
        center.removePendingNotificationRequests(withIdentifiers: pending.map(\.identifier).filter { $0.hasPrefix("aqmino.reminder.") })
    }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                            withCompletionHandler completionHandler: @escaping () -> Void) {
        let id = (response.notification.request.content.userInfo["occurrenceID"] as? String).flatMap(UUID.init(uuidString:))
        Task { @MainActor [weak self] in
            guard let action = self?.onAction else { completionHandler(); return }
            var completed = false
            action(response.actionIdentifier, id) {
                guard !completed else { return }; completed = true; completionHandler()
            }
        }
    }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                            withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        Task { @MainActor [weak self] in
            if self?.isFrontVisible?() == true, notification.request.identifier.hasPrefix("aqmino.reminder.") { completionHandler([]) }
            else { completionHandler([.banner, .list, .sound]) }
        }
    }
}

enum NotificationFailure: Error, Equatable {
    case unavailable
    case testInProgress
    case testRateLimited(seconds: Int)
}

struct TestNotificationGate {
    private(set) var sending = false
    private var lastSuccessfulSend: Date?

    mutating func begin(at now: Date) throws {
        guard !sending else { throw NotificationFailure.testInProgress }
        if let lastSuccessfulSend {
            let remaining = 5 - now.timeIntervalSince(lastSuccessfulSend)
            if remaining > 0 { throw NotificationFailure.testRateLimited(seconds: Int(ceil(remaining))) }
        }
        sending = true
    }
    mutating func finish(at now: Date, submitted: Bool) {
        if submitted { lastSuccessfulSend = now }
        sending = false
    }
}
