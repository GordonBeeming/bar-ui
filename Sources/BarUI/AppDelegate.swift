import AppKit
import BarUICore
import Observation

/// Notes how Bar UI was launched, and turns a reopen (Spotlight or Finder on
/// the running app) into a request the menu bar label answers by opening the
/// window: only a SwiftUI view can call `openWindow`.
@MainActor
@Observable
final class AppDelegate: NSObject, NSApplicationDelegate {
    private(set) var launchKind: LaunchKind = .byHand
    /// Bumped on every reopen; the label watches it.
    private(set) var reopenRequests = 0

    func applicationWillFinishLaunching(_ notification: Notification) {
        // The launch event is only current while launching finishes; read it
        // before anything else handles it.
        launchKind = LaunchKind(launchEvent: NSAppleEventManager.shared().currentAppleEvent)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        reopenRequests += 1
        return false
    }
}
