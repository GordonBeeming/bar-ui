/// One of Gordon's menu bar apps. The set is closed: the Dashboard only knows
/// the Bar Apps listed here and never discovers others at runtime.
public enum BarApp: String, CaseIterable, Sendable, Hashable {
    case claudeBar
    case codexBar
    case grokBar

    public var displayName: String {
        switch self {
        case .claudeBar: "ClaudeBar"
        case .codexBar: "CodexBar"
        case .grokBar: "GrokBar"
        }
    }

    /// Detection and the defaults domain both key on this, never on an app's
    /// name or path, so an unrelated app called "ClaudeBar" is never picked up.
    public var bundleIdentifier: String {
        switch self {
        case .claudeBar: "com.gordonbeeming.ClaudeBar"
        case .codexBar: "com.gordonbeeming.CodexBar"
        case .grokBar: "com.gordonbeeming.GrokBar"
        }
    }
}

/// One sign-in of a Bar App's tool. Limits, tokens and Perks belong to this
/// pair; Tracking and the Telemetry Folder belong to the `app` alone.
public struct BarAppAccount: Sendable, Hashable, Comparable, Identifiable {
    /// What a Bar App with a single Account, or a row from before Accounts
    /// existed, is called. It is the Account with no part in the file name.
    public static let defaultID = "default"

    public let app: BarApp
    public let accountID: String

    public init(app: BarApp, accountID: String = BarAppAccount.defaultID) {
        self.app = app
        self.accountID = accountID
    }

    public var id: String {
        "\(app.rawValue)/\(accountID)"
    }

    /// How ids built from this series are spelled. The default Account keeps
    /// the spelling from before Accounts, so an id a view or a stored
    /// selection holds doesn't change, and no other spelling can collide with
    /// it: an app's raw value has no dot and an Account id never has one.
    public var key: String {
        isDefault ? app.rawValue : "\(app.rawValue).\(accountID)"
    }

    public var isDefault: Bool {
        accountID == Self.defaultID
    }

    /// The grammar the Telemetry Spec gives an id. It ends up in file names,
    /// so nothing outside it is ever accepted.
    public static func isValidID(_ id: String) -> Bool {
        !id.isEmpty && id.utf8.allSatisfy { ($0 >= 0x61 && $0 <= 0x7A) || ($0 >= 0x30 && $0 <= 0x39) || $0 == 0x2D }
    }

    /// Bar Apps in their usual order, the default Account first within one,
    /// then the others by id.
    public static func < (lhs: BarAppAccount, rhs: BarAppAccount) -> Bool {
        let apps = BarApp.allCases
        if lhs.app != rhs.app {
            return (apps.firstIndex(of: lhs.app) ?? apps.count) < (apps.firstIndex(of: rhs.app) ?? apps.count)
        }
        if lhs.isDefault != rhs.isDefault {
            return lhs.isDefault
        }
        return lhs.accountID < rhs.accountID
    }
}
