// Test-only platform replacements. The check runner compiles these INSTEAD OF
// the native adapters; neither notification permissions nor login items change.
import AqminoCore
import Foundation

@MainActor
final class NotificationAdapter {
    var onAction: ((String, UUID?, @escaping () -> Void) -> Void)?
    var isFrontVisible: (() -> Bool)?
    var testCapability: NotificationCapability = .available
    var onCapabilityRequest: (() -> Void)?
    func capability() async -> NotificationCapability {
        if let hook = onCapabilityRequest {
            onCapabilityRequest = nil
            hook()
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        return testCapability
    }
    func requestAuthorization() async throws {}
    func registerCategories(state: StateSnapshot) {}
    func clearReminders() async {}
    func send(_ occurrence: ReminderOccurrence, sound: Bool, isStillCurrent: @escaping @MainActor () -> Bool) async throws -> Bool { isStillCurrent() }
    func sendTest(sound: Bool) async throws -> NotificationCapability { testCapability }
}
enum NotificationFailure: Error { case unavailable, testInProgress, testRateLimited(seconds: Int) }

@MainActor
final class LoginItemController {
    enum Status { case enabled, disabled, requiresApproval, unavailable }
    var status: Status = .disabled
    var requiresApproval = false
    var registrationError: Error?
    var requestedChanges: [Bool] = []
    func setEnabled(_ value: Bool) throws {
        requestedChanges.append(value)
        if let registrationError { throw registrationError }
        status = value ? (requiresApproval ? .requiresApproval : .enabled) : .disabled
    }
    func openSettings() {}
}

@MainActor
final class ReminderScheduler {
    static weak var latest: ReminderScheduler?
    private(set) var scheduleCount = 0
    private(set) var scheduledCallback: (@MainActor () -> Void)?
    init() { Self.latest = self }
    func cancel() { scheduledCallback = nil }
    func schedule(at date: Date?, generation: UInt64, fire: @escaping @MainActor (UInt64) -> Void) {
        scheduleCount += 1
        scheduledCallback = date.map { _ in { fire(generation) } }
    }
}

@MainActor
final class SystemEventObserver {
    static weak var latest: SystemEventObserver?
    let onSleep: @MainActor () -> Void
    let onResume: @MainActor () -> Void
    let onClockChange: @MainActor () -> Void
    init(onSleep: @escaping @MainActor () -> Void, onResume: @escaping @MainActor () -> Void, onClockChange: @escaping @MainActor () -> Void) {
        self.onSleep = onSleep; self.onResume = onResume; self.onClockChange = onClockChange
        Self.latest = self
    }
}
