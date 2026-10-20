import CoreServices
import Foundation

/// Whether macOS started Bar UI as a login item or the person opened it. A
/// login launch stays in the menu bar; a launch by hand shows the window.
public enum LaunchKind: Sendable, Equatable {
    case atLogin
    case byHand

    /// Reads the open-application Apple event the app was launched with. A
    /// login item's launch marks it `keyAELaunchedAsLogInItem`; anything else,
    /// including no event at all, is treated as opened by hand, because showing
    /// the window when unsure beats a launch that seems to do nothing.
    public init(launchEvent: NSAppleEventDescriptor?) {
        guard let launchEvent,
              launchEvent.eventClass == AEEventClass(kCoreEventClass),
              launchEvent.eventID == AEEventID(kAEOpenApplication),
              launchEvent.paramDescriptor(forKeyword: AEKeyword(keyAEPropData))?.enumCodeValue == OSType(keyAELaunchedAsLogInItem)
        else {
            self = .byHand
            return
        }
        self = .atLogin
    }
}
