import AppKit
import BarUICore
import Observation

/// Notes how Bar UI was launched, and turns a reopen (Spotlight or Finder on
/// the running app) into a request the menu bar label answers by opening the
/// window: only a SwiftUI view can call `openWindow`.
@MainActor
@Observable
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Nil until launching finishes; the label waits for it before deciding
    /// whether to open the window.
    private(set) var launchKind: LaunchKind?
    /// Bumped on every reopen; the label watches it.
    private(set) var reopenRequests = 0

    func applicationDidFinishLaunching(_ notification: Notification) {
        // AppKit calls this while handling the open-application event, so that
        // event is current here; in applicationWillFinishLaunching it isn't yet.
        launchKind = LaunchKind(launchEvent: NSAppleEventManager.shared().currentAppleEvent)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        reopenRequests += 1
        return false
    }
}
