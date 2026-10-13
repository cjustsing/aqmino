import ServiceManagement

@MainActor
final class LoginItemController {
    enum Status { case enabled, disabled, requiresApproval, unavailable }
    var status: Status {
        switch SMAppService.mainApp.status {
        case .enabled: return .enabled
        case .requiresApproval: return .requiresApproval
        // The system may not know a main-app service until its first registration.
        case .notRegistered, .notFound: return .disabled
        @unknown default: return .unavailable
        }
    }
    func setEnabled(_ enabled: Bool) throws {
        switch (enabled, status) {
        case (true, .enabled), (true, .requiresApproval), (false, .disabled): return
        default: break
        }
        if enabled { try SMAppService.mainApp.register() }
        else { try SMAppService.mainApp.unregister() }
    }
    func openSettings() { SMAppService.openSystemSettingsLoginItems() }
}
