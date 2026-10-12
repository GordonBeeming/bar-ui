import AppKit
import BarUICore

/// Asks Launch Services for an app by bundle ID, so it finds a Bar App wherever
/// it is installed and never matches another app that only shares its name.
struct WorkspaceApplicationLocator: ApplicationLocating {
    func isInstalled(bundleIdentifier: String) -> Bool {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) != nil
    }
}
