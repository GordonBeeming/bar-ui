/// One of Gordon's menu bar apps. The set is closed: the Dashboard only knows
/// the Bar Apps listed here and never discovers others at runtime.
public enum BarApp: String, CaseIterable, Sendable, Hashable {
    case claudeBar
    case codexBar

    public var displayName: String {
        switch self {
        case .claudeBar: "ClaudeBar"
        case .codexBar: "CodexBar"
        }
    }

    /// Detection and the defaults domain both key on this, never on an app's
    /// name or path, so an unrelated app called "ClaudeBar" is never picked up.
    public var bundleIdentifier: String {
        switch self {
        case .claudeBar: "com.gordonbeeming.ClaudeBar"
        case .codexBar: "com.gordonbeeming.CodexBar"
        }
    }
}
