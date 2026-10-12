/// The Token Types of Telemetry Spec v1. The raw values are the spec's
/// `token.type` values, which the Archive also stores, so they must not change.
public enum TokenType: String, Sendable, Hashable, CaseIterable {
    case input
    case cacheRead = "cache_read"
    case cacheWrite5m = "cache_write_5m"
    case cacheWrite1h = "cache_write_1h"
    case cacheWrite = "cache_write"
    case output
    /// A part of `output`, never an addition to it.
    case reasoning

    /// Everything the model was given, whether or not the cache was involved.
    public var isInput: Bool {
        switch self {
        case .input, .cacheRead, .cacheWrite5m, .cacheWrite1h, .cacheWrite: true
        case .output, .reasoning: false
        }
    }
}

/// One cumulative `bar.tokens` data point: how many tokens a Bar App has
/// counted for a model and Token Type since `startTimeUnixNano`.
public struct TokenSample: Sendable, Hashable {
    public let app: BarApp
    public let model: String
    public let tokenType: TokenType
    /// When the count began. A different start than the previous point means
    /// the counter restarted, not that it fell.
    public let startTimeUnixNano: Int64
    public let timeUnixNano: Int64
    /// The running total at `timeUnixNano`.
    public let count: Int64

    public init(app: BarApp, model: String, tokenType: TokenType, startTimeUnixNano: Int64, timeUnixNano: Int64, count: Int64) {
        self.app = app
        self.model = model
        self.tokenType = tokenType
        self.startTimeUnixNano = startTimeUnixNano
        self.timeUnixNano = timeUnixNano
        self.count = count
    }
}
