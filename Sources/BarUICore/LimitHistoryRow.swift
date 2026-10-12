import Foundation

/// One Limit's row on a Bar App's page: its utilisation line, a marker at each
/// reset, and what was left unused at those resets.
public struct LimitHistoryRow: Sendable, Hashable, Identifiable {
    public struct Point: Sendable, Hashable {
        public let date: Date
        public let percent: Double
    }

    public struct ResetMarker: Sendable, Hashable {
        public let date: Date
        /// Headroom left in the last sample before the reset.
        public let unusedPercent: Double
    }

    /// Samples closer together than this are never treated as a gap, so a Bar
    /// App sampling every minute doesn't show a hole for one missed sample.
    private static let smallestGap: TimeInterval = 10 * 60
    /// How many usual sampling intervals of silence make a gap. Nothing says
    /// how often a Bar App samples, so the pace comes from the data.
    private static let gapIntervals = 3.0

    public let app: BarApp
    public let limitID: String
    public let name: String
    public let windowText: String
    /// Runs of samples with no Tracking gap inside them. Each run is drawn as
    /// its own line, so a gap shows as empty space instead of a straight line
    /// across it.
    public let segments: [[Point]]
    public let resetMarkers: [ResetMarker]
    public let percentUsedNow: Int?
    public let latestSampleAt: Date?
    public let unusedAtLastReset: Double?
    public let averageUnusedAtReset: Double?

    public var id: String {
        "\(app.rawValue)/\(limitID)"
    }

    public init(history: LimitHistory) {
        app = history.app
        limitID = history.limit.id
        name = history.limit.name
        windowText = Self.windowText(minutes: history.limit.windowDurationMinutes)
        segments = Self.segments(of: history.utilization)
        resetMarkers = history.resets
            .sorted { $0.timeUnixNano < $1.timeUnixNano }
            .map { ResetMarker(date: Date(unixNano: $0.timeUnixNano), unusedPercent: 100 - $0.utilizationLast) }
        percentUsedNow = history.latest.map { Int($0.value.rounded()) }
        latestSampleAt = history.latest.map { Date(unixNano: $0.timeUnixNano) }
        unusedAtLastReset = resetMarkers.last?.unusedPercent
        averageUnusedAtReset = resetMarkers.isEmpty
            ? nil
            : resetMarkers.map(\.unusedPercent).reduce(0, +) / Double(resetMarkers.count)
    }

    /// Shortest Window first, unknown Windows last, then by ID so a renamed
    /// label doesn't reshuffle the page.
    public static func rows(from histories: [LimitHistory]) -> [LimitHistoryRow] {
        histories
            .sorted {
                let lhs = $0.limit.windowDurationMinutes ?? .max
                let rhs = $1.limit.windowDurationMinutes ?? .max
                return lhs != rhs ? lhs < rhs : $0.limit.id < $1.limit.id
            }
            .map { LimitHistoryRow(history: $0) }
    }

    static func windowText(minutes: Int?) -> String {
        guard let minutes else {
            return "Window length unknown"
        }
        func unit(_ count: Int, _ name: String) -> String {
            "\(count) \(name) window"
        }
        if minutes % (24 * 60) == 0 {
            return unit(minutes / (24 * 60), "day")
        }
        if minutes % 60 == 0 {
            return unit(minutes / 60, "hour")
        }
        return unit(minutes, "minute")
    }

    private static func segments(of samples: [ArchivedSample]) -> [[Point]] {
        guard samples.count > 1 else {
            return samples.isEmpty ? [] : [samples.map(point)]
        }
        let seconds = zip(samples, samples.dropFirst()).map { Double($1.timeUnixNano - $0.timeUnixNano) / 1_000_000_000 }
        let usual = seconds.sorted()[seconds.count / 2]
        let threshold = max(usual * gapIntervals, smallestGap)

        var segments: [[Point]] = [[point(samples[0])]]
        for (sample, gap) in zip(samples.dropFirst(), seconds) {
            if gap > threshold {
                segments.append([])
            }
            segments[segments.count - 1].append(point(sample))
        }
        return segments
    }

    private static func point(_ sample: ArchivedSample) -> Point {
        Point(date: Date(unixNano: sample.timeUnixNano), percent: sample.value)
    }
}
