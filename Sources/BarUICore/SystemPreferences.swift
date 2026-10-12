import CoreFoundation
import Foundation

/// Reads another app's defaults domain through CFPreferences, by bundle ID.
public struct SystemPreferences: PreferencesReading {
    public init() {}

    public func value(forKey key: String, inDomain domain: String) -> Any? {
        let applicationID = domain as CFString
        // The Bar App writes this domain from its own process. Synchronizing
        // first is the documented way to see such outside changes, rather than
        // relying on cfprefsd happening to have invalidated our cached copy.
        CFPreferencesAppSynchronize(applicationID)
        return CFPreferencesCopyAppValue(key as CFString, applicationID)
    }
}
