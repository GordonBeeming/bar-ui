import Foundation

/// The three parts a token total splits into for display. A large total is
/// mostly cache reads (context re-read on every turn), so a single number
/// says little; split this way it shows how much fresh context went in and
/// how much was generated.
public enum TokenKind: String, Sendable, CaseIterable, Hashable {
    /// Context read back from the cache.
    case cacheRead
    /// Context sent fresh: plain input and cache writes.
    case newInput
    /// What the model generated, reasoning included.
    case output

    /// Nil for reasoning, which output already contains.
    public init?(_ type: TokenType) {
        switch type {
        case .cacheRead: self = .cacheRead
        case .input, .cacheWrite5m, .cacheWrite1h, .cacheWrite: self = .newInput
        case .output: self = .output
        case .reasoning: return nil
        }
    }

    public var label: String {
        switch self {
        case .cacheRead: "Cache reads"
        case .newInput: "Input"
        case .output: "Output"
        }
    }

    /// Short form for a headline line: "1.4B cached".
    public var shortLabel: String {
        switch self {
        case .cacheRead: "cached"
        case .newInput: "in"
        case .output: "out"
        }
    }
}
