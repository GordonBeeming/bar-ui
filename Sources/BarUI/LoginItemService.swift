import BarUICore
import ServiceManagement

/// The background helper, registered as a login item through SMAppService.
/// The helper app ships inside this app's bundle (see the Makefile).
struct LoginItemService: LoginItemRegistering {
    static let helperIdentifier = "com.gordonbeeming.BarUI.Helper"

    private var service: SMAppService {
        SMAppService.loginItem(identifier: Self.helperIdentifier)
    }

    var status: LoginItemStatus {
        switch service.status {
        case .notRegistered: .notRegistered
        case .enabled: .enabled
        case .requiresApproval: .requiresApproval
        case .notFound: .notFound
        @unknown default: .notFound
        }
    }

    func register() throws {
        try service.register()
    }

    func unregister() throws {
        try service.unregister()
    }
}
