import Foundation

/// A Bar App's Tracking settings as it last saved them. Bar UI reads these and
/// never writes them; changes go to the Bar App as a request it confirms.
public struct TrackingSettings: Sendable, Hashable {
    /// The spec's accepted ranges. A Bar App accepts any value inside them,
    /// not only its picker presets, so Bar UI does the same.
    public static let intervalRange = 1...1440
    public static let retentionRange = 0...3650

    public var enabled: Bool
    /// Nil when the Bar App hasn't saved one (or saved one out of range), so
    /// Bar UI never presents a guess at the Bar App's own default as fact.
    public var intervalMinutes: Int?
    /// `0` means keep forever. Nil means not set, as for `intervalMinutes`.
    public var retentionDays: Int?
    public var folder: URL

    public init(enabled: Bool, intervalMinutes: Int?, retentionDays: Int?, folder: URL) {
        self.enabled = enabled
        self.intervalMinutes = intervalMinutes
        self.retentionDays = retentionDays
        self.folder = folder
    }
}
