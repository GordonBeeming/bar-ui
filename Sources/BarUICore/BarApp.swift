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
}
