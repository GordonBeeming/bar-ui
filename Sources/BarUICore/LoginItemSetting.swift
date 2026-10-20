import Foundation
import Observation

public enum LoginItemStatus: Sendable, Equatable {
    case notRegistered
    case enabled
    /// Registered, but macOS is waiting for the person to allow it in System
    /// Settings, so it won't run yet.
    case requiresApproval
    /// macOS has no record of the item: never registered yet, or the helper
    /// isn't inside this build (for example when run from `swift run`).
    case notFound
}

/// The slice of SMAppService the setting needs. Kept behind a protocol so
/// tests never register a real login item.
public protocol LoginItemRegistering: Sendable {
    var status: LoginItemStatus { get }
    func register() throws
    func unregister() throws
}

/// Remembers the person's choice, separately from the login item itself, so
/// "never chosen" (on by default) differs from "switched off".
public protocol LoginItemChoiceStoring: Sendable {
    var choice: Bool? { get set }
}

/// A Settings switch backed by a login item: Bar UI opening at login, or the
/// background helper that keeps the Archive filling while the window is closed.
@MainActor
@Observable
public final class LoginItemSetting {
    public private(set) var isEnabled: Bool
    public private(set) var status: LoginItemStatus
    public private(set) var problem: String?

    private let service: any LoginItemRegistering
    private var store: any LoginItemChoiceStoring

    public init(service: any LoginItemRegistering, store: any LoginItemChoiceStoring) {
        self.service = service
        self.store = store
        self.isEnabled = store.choice ?? true
        self.status = service.status
    }

    /// Brings the login item in line with the saved choice. Run at launch,
    /// which is also what registers it the first time the app opens.
    public func reconcile() {
        apply()
    }

    public func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        store.choice = enabled
        apply()
    }

    private func apply() {
        do {
            switch (isEnabled, service.status) {
            // macOS reports an item it has never registered as not found,
            // not only a helper missing from the bundle, so not found gets a
            // register too. A truly missing helper makes register throw, and
            // Settings shows that instead of staying silently unregistered.
            case (true, .notRegistered), (true, .notFound):
                try service.register()
            case (false, .enabled), (false, .requiresApproval):
                try service.unregister()
            default:
                // Already as wanted, or approval that's the person's to give
                // in System Settings.
                break
            }
            problem = nil
        } catch {
            problem = error.localizedDescription
        }
        status = service.status
    }
}
