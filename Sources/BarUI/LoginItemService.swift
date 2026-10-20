import BarUICore
import ServiceManagement

/// A login item through SMAppService: Bar UI itself, or the background helper
/// that ships inside this app's bundle (see the Makefile).
struct LoginItemService: LoginItemRegistering {
    static let helperIdentifier = "com.gordonbeeming.BarUI.Helper"

    /// Bar UI opening at login, in the menu bar.
    static let app = LoginItemService { .mainApp }
    /// The helper that keeps importing while Bar UI is closed.
    static let helper = LoginItemService { .loginItem(identifier: helperIdentifier) }

    /// Made on each use rather than stored: SMAppService isn't Sendable, and
    /// it's a cheap handle onto launchd's record, not state of its own.
    private let makeService: @Sendable () -> SMAppService

    private init(_ makeService: @escaping @Sendable () -> SMAppService) {
        self.makeService = makeService
    }

    private var service: SMAppService {
        makeService()
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
