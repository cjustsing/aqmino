import Foundation

// Test-only API boundary. No real login item is read or changed by these checks.
@MainActor
final class SMAppService {
    enum Status { case enabled, requiresApproval, notRegistered, notFound }
    enum Failure: Error { case registration, alreadyRegistered, notRegistered }
    static let mainApp = SMAppService()
    var status: Status = .notFound
    var registrationResult: Status = .enabled
    var failRegistration = false
    var registerCalls = 0
    var unregisterCalls = 0
    func register() throws {
        registerCalls += 1
        if failRegistration { throw Failure.registration }
        if status == .enabled || status == .requiresApproval { throw Failure.alreadyRegistered }
        status = registrationResult
    }
    func unregister() throws {
        unregisterCalls += 1
        if status == .notFound || status == .notRegistered { throw Failure.notRegistered }
        status = .notRegistered
    }
    static func openSystemSettingsLoginItems() {}
    func reset(_ status: Status) {
        self.status = status; registrationResult = .enabled; failRegistration = false
        registerCalls = 0; unregisterCalls = 0
    }
}

@main
struct LoginItemChecks {
    static var failures = 0
    @MainActor static func expect(_ value: @autoclosure () -> Bool, _ message: String) {
        if !value() { failures += 1; print("FAIL: \(message)") }
    }
    @MainActor static func main() {
        let service = SMAppService.mainApp
        let controller = LoginItemController()
        service.reset(.notFound)
        expect(controller.status == .disabled, "A never-registered main app must allow enabling launch at login")
        do {
            try controller.setEnabled(true)
            expect(controller.status == .enabled && service.registerCalls == 1, "First enable must register the main app")
            try controller.setEnabled(true)
            expect(service.registerCalls == 1, "Enabling an enabled login item must be idempotent")
            try controller.setEnabled(false)
            expect(controller.status == .disabled, "Disabling an enabled login item must unregister it")
            try controller.setEnabled(false)
            expect(service.unregisterCalls == 1, "Disabling a disabled login item must be idempotent")
        } catch { failures += 1; print("FAIL: login registration sequence threw \(error)") }
        service.reset(.notFound); service.registrationResult = .requiresApproval
        do {
            try controller.setEnabled(true)
            expect(controller.status == .requiresApproval, "System approval must remain visible")
            try controller.setEnabled(true)
            expect(service.registerCalls == 1, "An approval request must not register twice")
            try controller.setEnabled(false)
            expect(controller.status == .disabled, "An approval request must be cancellable")
        } catch { failures += 1; print("FAIL: approval sequence threw \(error)") }
        service.reset(.notFound); service.failRegistration = true
        do {
            try controller.setEnabled(true)
            failures += 1; print("FAIL: registration error was swallowed")
        } catch { expect(controller.status == .disabled, "Failed registration must not pretend the service is enabled") }
        print("Login item checks: \(failures) assertion failures")
        if failures > 0 { exit(1) }
    }
}
