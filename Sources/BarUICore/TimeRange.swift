import Foundation

/// How far back a view reaches, counting from now: the token chart and
/// tiles, the Events list, tokens by model and Limit history all pick one.
public enum TimeRange: String, CaseIterable, Identifiable, Sendable, Hashable {
    case day
    case week
    case month
    case all

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .day: "24h"
        case .week: "7d"
        case .month: "30d"
        case .all: "All time"
        }
    }

    /// How far back the range reaches. Nil for All time, which reaches back to
    /// the oldest data in the Archive.
    var span: TimeInterval? {
        switch self {
        case .day: 24 * 3_600
        case .week: 7 * 24 * 3_600
        case .month: 30 * 24 * 3_600
        case .all: nil
        }
    }

    /// Whether this range reaches back at least as far as `other`.
    func reaches(atLeastAsFarAs other: TimeRange) -> Bool {
        guard let span else {
            return true
        }
        return other.span.map { span >= $0 } ?? false
    }

    /// When the range begins, counting back from `now`. Nil for All time.
    public func start(now: Date) -> Date? {
        span.map { now.addingTimeInterval(-$0) }
    }

    /// A day of data is too few points at daily resolution to show a shape.
    public var bucketComponent: Calendar.Component {
        self == .day ? .hour : .day
    }
}
