import AppKit

/// Asks Launch Services for an app by bundle ID, so it finds a Bar App wherever
/// it is installed and never matches another app that only shares its name.
public struct WorkspaceApplicationLocator: ApplicationLocating {
    public init() {}

    public func isInstalled(bundleIdentifier: String) -> Bool {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) != nil
    }
}
