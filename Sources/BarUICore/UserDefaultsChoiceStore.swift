import Foundation

/// One login-item switch's choice in UserDefaults, under its own key.
public struct UserDefaultsChoiceStore: LoginItemChoiceStoring {
    /// Bar UI itself opening at login.
    public static let openAtLoginKey = "openAtLogin"
    /// The background helper. The key it has always used, so a choice made
    /// before Bar UI could open at login still applies.
    public static let backgroundImportKey = "backgroundImport"

    private let key: String
    // Apple documents UserDefaults as safe to use from any thread; it just
    // isn't annotated Sendable.
    nonisolated(unsafe) private let defaults: UserDefaults

    public init(key: String, defaults: UserDefaults = .standard) {
        self.key = key
        self.defaults = defaults
    }

    /// Nil until the person has flipped the switch, which reads as on.
    public var choice: Bool? {
        get { defaults.object(forKey: key) as? Bool }
        set { defaults.set(newValue, forKey: key) }
    }
}
