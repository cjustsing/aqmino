import AppKit
import AqminoCore
import SwiftUI
import UserNotifications

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var state = StateSnapshot()
    @Published private(set) var plan = ReminderPlan(status: .setupRequired, wakeAt: nil, canDeliver: false)
    @Published private(set) var loaded = false
    @Published private(set) var busy = false
    @Published private(set) var storageIssue: String?
    @Published private(set) var backupAvailable = false
    @Published private(set) var deletionPending = false
    @Published private(set) var capability: NotificationCapability = .notDetermined
    @Published private(set) var undo: UndoToken?
    @Published private(set) var inlineOccurrence: ReminderOccurrence?
    @Published private(set) var reminderAttention = false
    @Published private(set) var notice: String?
    @Published private(set) var dispatchFailed = false
    @Published private(set) var loginStatus: LoginItemController.Status = .disabled
    @Published private(set) var loginIssue: String?
    @Published private(set) var testingNotification = false
    @Published private(set) var testNotificationFeedback: String?
    @Published private(set) var testNotificationFailed = false
    @Published var now = Date()
    let dataDirectory: URL
    let notifications = NotificationAdapter()
    let login = LoginItemController()
    private let coordinator: StateCoordinator
    private let scheduler = ReminderScheduler()
    private var events: SystemEventObserver?
    private var sessionActive = true
    private var stopping = false
    private var environmentGeneration: UInt64 = 0
    private var pendingResetGeneration: UInt64?
    private var undoTask: Task<Void, Never>?
    private var queue: [PendingCommand] = []
    private var failedCommand: PendingCommand?
    private var worker: Task<Void, Never>?
    private enum LaunchRecovery { case pending, complete }
    private enum ScheduleRefresh { case ordinary, reset, recover }
    private var launchRecovery = LaunchRecovery.pending
    private var didReportReady = false
    var openPanel: (() -> Void)?
    var openSettings: ((SettingsSection) -> Void)?
    var openRecords: (() -> Void)?
    var closeWelcome: (() -> Void)?
    var isFrontVisible: (() -> Bool)?
    var onReady: (() -> Void)?

    struct PendingCommand {
        let command: BusinessCommand
        let id: UUID
        let retry: Bool
        let environmentGeneration: UInt64
        let completion: ((Bool) -> Void)?
    }
    init(directory: URL) {
        dataDirectory = directory; coordinator = StateCoordinator(store: FileStateStore(directory: directory))
        notifications.isFrontVisible = { [weak self] in self?.isFrontVisible?() ?? false }
        notifications.onAction = { [weak self] action, id, done in
            guard let self, !self.stopping else { done(); return }
            if action == "record", let id { self.enqueue(.notificationRecord(id)) { success in if !success && !self.stopping { self.openPanel?() }; done() } }
            else if action == "snooze", let id { self.enqueue(.snooze(id)) { success in if !success && !self.stopping { self.openPanel?() }; done() } }
            else { if action != UNNotificationDismissActionIdentifier { self.openPanel?() }; done() }
        }
    }
    var summary: DailySummary { DailySummary(state: state, now: now, calendar: Calendar.autoupdatingCurrent) }
    var canWrite: Bool { loaded && storageIssue == nil && !busy && !stopping }
    var canShowRecords: Bool { loaded && !deletionPending }
    var hasPause: Bool { (state.runtime.pauseUntil.map { $0 > now } ?? false) || state.runtime.pausedDay != nil }
    private var context: RuleContext { RuleContext(now: Date(), calendar: .autoupdatingCurrent, notifications: capability, sessionActive: sessionActive) }

    func start() {
        events = SystemEventObserver(onSleep: { [weak self] in self?.sleep() }, onResume: { [weak self] in self?.resumeSystem() }, onClockChange: { [weak self] in self?.refreshSchedule(.recover) })
        Task {
            do {
                state = try await coordinator.load()
                capability = await notifications.capability(); loginStatus = login.status
                guard !stopping else { return }
                loaded = true; now = Date()
                drain(); finishLaunchIfReady()
            } catch { await showStorageError(error); finishPendingAfterReadError(); reportReady() }
        }
    }

    private func finishLaunchIfReady() {
        // Notification actions may arrive before loading finishes. Recover from
        // their confirmed state so startup cannot replace a snooze or undo cycle.
        guard loaded, !stopping, worker == nil, queue.isEmpty, launchRecovery != .complete else { return }
        guard storageIssue == nil else { reportReady(); return }
        launchRecovery = .complete
        enqueue(.recoverSchedule) { [weak self] _ in self?.reportReady() }
    }

    private func reportReady() {
        guard !stopping, !didReportReady else { return }
        didReportReady = true; onReady?()
    }

    func enqueue(_ command: BusinessCommand, id: UUID = UUID(), retry: Bool = false, completion: ((Bool) -> Void)? = nil) {
        guard !stopping, storageIssue == nil || retry else { completion?(false); return }
        queue.append(PendingCommand(command: command, id: id, retry: retry, environmentGeneration: environmentGeneration, completion: completion))
        drain()
    }
    private func drain() {
        guard loaded, worker == nil, !queue.isEmpty else { return }
        busy = true
        worker = Task { [weak self] in
            guard let self else { return }
            while !queue.isEmpty {
                let pending = queue.removeFirst()
                if case .due = pending.command,
                   pending.environmentGeneration != environmentGeneration || !sessionActive || pendingResetGeneration != nil {
                    pending.completion?(true); continue
                }
                do {
                    let result = try await coordinator.execute(pending.command, id: pending.id, context: context, retry: pending.retry)
                    if result.state.runtime.generation != state.runtime.generation {
                        inlineOccurrence = nil; dispatchFailed = false; acknowledgeReminder()
                        if result.occurrence == nil { Task { await self.notifications.clearReminders() } }
                    }
                    state = result.state; plan = result.plan; now = Date()
                    storageIssue = nil; deletionPending = false; failedCommand = nil
                    notifications.registerCategories(state: state)
                    if let token = result.undo { setUndo(token) }
                    switch pending.command {
                    case .record, .notificationRecord:
                        if !result.duplicate { inlineOccurrence = nil; dispatchFailed = false; notice = L10n.text("已记录 \(result.undo?.record.amountMl ?? 0) ml", "Recorded \(result.undo?.record.amountMl ?? 0) ml") }
                    case .undo:
                        setUndo(nil); notice = L10n.text("已撤销", "Undone")
                    case .clearRecords:
                        setUndo(nil); inlineOccurrence = nil; notice = L10n.text("所有饮水记录已删除", "All water records deleted")
                    case .snooze, .pause, .pauseToday, .resume:
                        inlineOccurrence = nil; notice = nil
                    default: break
                    }
                    if let occurrence = result.occurrence, pending.environmentGeneration == environmentGeneration {
                        dispatchFailed = false
                        reminderAttention = !(isFrontVisible?() ?? false)
                        if occurrence.delivery == .inline { inlineOccurrence = occurrence }
                        else { deliver(occurrence, expectedEnvironment: environmentGeneration) }
                    }
                    schedule()
                    if case .snooze = pending.command { pending.completion?(!result.duplicate) }
                    else { pending.completion?(true) }
                } catch let error as ValidationError {
                    notice = validationMessage(error); pending.completion?(false)
                } catch {
                    failedCommand = pending; scheduler.cancel(); await showStorageError(error)
                    pending.completion?(false)
                    let waiting = queue; queue.removeAll(); waiting.forEach { $0.completion?(false) }
                    break
                }
            }
            busy = false; worker = nil
            if !queue.isEmpty { drain() }
            else { finishLaunchIfReady() }
        }
    }

    private func schedule() {
        guard launchRecovery == .complete, storageIssue == nil, !stopping, sessionActive, pendingResetGeneration == nil else { scheduler.cancel(); return }
        let expectedEnvironment = environmentGeneration
        scheduler.schedule(at: plan.wakeAt, generation: state.runtime.generation) { [weak self] generation in
            guard let self else { return }
            Task {
                let fresh = await self.notifications.capability()
                guard self.environmentGeneration == expectedEnvironment, self.sessionActive, !self.stopping else { return }
                if fresh != self.capability { self.capability = fresh; self.enqueue(.reconcile(reset: true)); return }
                guard generation == self.state.runtime.generation, self.storageIssue == nil else { return }
                self.enqueue(.due(expectedGeneration: generation, inline: self.isFrontVisible?() ?? false))
            }
        }
    }
    private func deliver(_ occurrence: ReminderOccurrence, expectedEnvironment: UInt64) {
        Task {
            do {
                let submitted = try await notifications.send(occurrence, sound: state.preferences.soundEnabled) { [weak self] in
                    guard let self, storageIssue == nil, sessionActive, !stopping, environmentGeneration == expectedEnvironment else { return false }
                    return ReminderPlanner.isEligibleNow(state, context: context) && state.runtime.generation == occurrence.interactionGeneration
                        && state.runtime.latestOccurrenceID == occurrence.id && !(isFrontVisible?() ?? false)
                }
                if submitted { enqueue(.delivery(occurrence.id, .submitted)) }
                else {
                    if isFrontVisible?() == true, state.runtime.latestOccurrenceID == occurrence.id,
                       state.runtime.generation == occurrence.interactionGeneration {
                        inlineOccurrence = occurrence; enqueue(.delivery(occurrence.id, .inline))
                    }
                    refresh(reset: false)
                }
            } catch { dispatchFailed = true; enqueue(.delivery(occurrence.id, .failed)) }
        }
    }
    private func setUndo(_ token: UndoToken?) {
        undoTask?.cancel(); undo = token
        guard let token else { return }
        undoTask = Task {
            try? await Task.sleep(nanoseconds: UInt64(max(0, token.expiresAt.timeIntervalSinceNow) * 1_000_000_000))
            guard !Task.isCancelled else { return }; undo = nil; notice = nil
        }
    }
    func undoLast() { if let undo { enqueue(.undo(undo)) } }
    /// Acknowledging only changes the menu bar indicator, never the reminder cycle.
    func acknowledgeReminder() { reminderAttention = false }
    func retryStorage() {
        guard !busy else { return }
        if let failedCommand, !deletionPending {
            enqueue(failedCommand.command, id: failedCommand.id, retry: true, completion: failedCommand.completion)
        } else { reload(restore: false) }
    }
    func restoreBackup() { reload(restore: true) }
    private func reload(restore: Bool) {
        guard !busy else { return }; busy = true
        Task {
            do {
                state = try await (restore ? coordinator.restore() : coordinator.load())
                capability = await notifications.capability(); loginStatus = login.status
                guard !stopping else { busy = false; return }
                loaded = true; storageIssue = nil; deletionPending = false; failedCommand = nil; busy = false
                setUndo(nil); inlineOccurrence = nil; acknowledgeReminder(); enqueue(.reconcile(reset: true))
            } catch { await showStorageError(error); busy = false }
        }
    }
    private func showStorageError(_ error: Error) async {
        let options = await coordinator.recoveryOptions(); backupAvailable = options.backup; deletionPending = options.deletion
        if deletionPending { storageIssue = L10n.text("清理尚未完成，请继续完成。", "Deletion is unfinished. Continue to complete it.") }
        else if loaded { storageIssue = L10n.text("未能保存，本次操作尚未生效。", "Could not save. This change has not taken effect.") }
        else { storageIssue = L10n.text("记录暂时无法读取。", "Records could not be read.") }
        scheduler.cancel()
    }
    private func finishPendingAfterReadError() { queue.forEach { $0.completion?(false) }; queue.removeAll() }
    func refresh(reset: Bool = false) {
        refreshSchedule(reset ? .reset : .ordinary)
    }
    private func refreshSchedule(_ mode: ScheduleRefresh) {
        // Activation can occur while the first capability query is suspended.
        // Recovery cancels platform timers without resetting a valid business plan.
        guard !stopping, loaded || mode != .ordinary else { return }
        if mode != .ordinary {
            environmentGeneration &+= 1; pendingResetGeneration = environmentGeneration; scheduler.cancel()
        }
        let expectedEnvironment = environmentGeneration
        Task {
            let fresh = await notifications.capability()
            guard environmentGeneration == expectedEnvironment, !stopping else { return }
            // Before load completes, the first capability result initializes
            // state; it is not a permission change that restarts the saved cycle.
            let changed = loaded && fresh != capability; capability = fresh; now = Date(); loginStatus = login.status
            if changed { environmentGeneration &+= 1; pendingResetGeneration = nil; scheduler.cancel() }
            else if mode != .ordinary { pendingResetGeneration = nil }
            if storageIssue == nil {
                if mode == .recover && !changed { enqueue(.recoverSchedule) }
                else { enqueue(.reconcile(reset: mode == .reset || changed)) }
            }
        }
    }
    func requestNotifications() {
        Task {
            do { try await notifications.requestAuthorization() }
            catch { notice = L10n.text("未能开启通知，请查看系统设置。", "Could not enable notifications. Check System Settings.") }
            refresh(reset: true)
        }
    }
    func testNotification(sound: Bool) {
        guard !testingNotification else { return }
        testingNotification = true; testNotificationFailed = false
        testNotificationFeedback = L10n.text("正在发送测试通知…", "Sending test notification…")
        Task {
            defer { testingNotification = false }
            do {
                let capability = try await notifications.sendTest(sound: sound)
                testNotificationFeedback = capability == .centerOnly
                    ? L10n.text("测试通知已发送至通知中心。系统未开启横幅。", "Sent to Notification Center. Banners are not enabled in System Settings.")
                    : L10n.text("测试通知已提交，请查看屏幕右上角或通知中心。", "Test notification submitted. Check the top-right corner of your screen or Notification Center.")
            } catch NotificationFailure.testRateLimited(let seconds) {
                testNotificationFeedback = L10n.text("请在 \(seconds) 秒后重试。", "Try again in \(seconds) seconds.")
            } catch NotificationFailure.testInProgress {
                testNotificationFeedback = L10n.text("正在发送测试通知…", "Sending test notification…")
            } catch NotificationFailure.unavailable {
                testNotificationFailed = true
                testNotificationFeedback = L10n.text("通知权限已关闭，请在系统设置中开启。", "Notifications are off. Enable them in System Settings.")
            } catch {
                testNotificationFailed = true
                testNotificationFeedback = L10n.text("发送失败：", "Could not send: ") + error.localizedDescription
            }
        }
    }
    func notificationSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") { NSWorkspace.shared.open(url) }
    }
    func setLoginEnabled(_ value: Bool) {
        loginIssue = nil
        do { try login.setEnabled(value) }
        catch { loginIssue = L10n.text("登录启动未能更改：", "Could not change launch at login: ") + error.localizedDescription }
        loginStatus = login.status
    }
    func completeWelcome(enableNotifications: Bool) {
        var p = state.preferences; p.onboardingComplete = true
        enqueue(.preferences(p)) { [weak self] success in
            guard success, let self, !stopping else { return }; closeWelcome?(); openPanel?()
            if enableNotifications { requestNotifications() }
        }
    }
    private func sleep() {
        sessionActive = false; environmentGeneration &+= 1; pendingResetGeneration = environmentGeneration
        acknowledgeReminder()
        scheduler.cancel(); Task { await notifications.clearReminders() }
    }
    private func resumeSystem() { sessionActive = true; refreshSchedule(.recover) }
    func stop() { scheduler.cancel(); undoTask?.cancel(); Task { await notifications.clearReminders() } }
    func prepareForExit() async {
        stopping = true; scheduler.cancel(); undoTask?.cancel(); acknowledgeReminder()
        await worker?.value
        await notifications.clearReminders()
    }
    private func validationMessage(_ error: ValidationError) -> String {
        switch error {
        case .unknownOccurrence: return L10n.text("这条提醒已失效，请直接记录饮水。", "This reminder is no longer valid. Record water directly.")
        case .expiredUndo: return L10n.text("这项撤销已失效。", "This undo is no longer available.")
        default: return L10n.text("请检查输入的容量、目标和提醒时段。", "Check your amount, goal and reminder window.")
        }
    }
}
