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
    /// Two-point lines joining a segment to the next across a Tracking gap,
    /// drawn fainter so the stretch with no samples (a Mac asleep, say) still
    /// reads as one line. A gap with a reset in it isn't bridged: a line from
    /// before the reset to after it would draw the drop as a slope.
    public let bridges: [[Point]]
    public let resetMarkers: [ResetMarker]
    public let percentUsedNow: Int?
    public let latestSampleAt: Date?
    public let unusedAtLastReset: Double?
    /// Over `averageLabel`'s lookback, whatever range the chart shows.
    public let averageUnusedAtReset: Double?
    /// What the average covers, "last 7d" or "last 5 weeks".
    public let averageLabel: String

    public var id: String {
        "\(app.rawValue)/\(limitID)"
    }

    /// `averageResets` is every reset the Archive holds for this Limit, for the
    /// average and the last reset; without it, the history's own resets are
    /// used. `now` defaults to the newest sample or reset.
    public init(history: LimitHistory, averageResets: [LimitReset]? = nil, now: Date? = nil) {
        app = history.app
        limitID = history.limit.id
        name = history.limit.name
        windowText = Self.windowText(minutes: history.limit.windowDurationMinutes)
        segments = Self.segments(of: history.utilization)
        resetMarkers = history.resets
            .sorted { $0.timeUnixNano < $1.timeUnixNano }
            .map { ResetMarker(date: Date(unixNano: $0.timeUnixNano), unusedPercent: 100 - $0.utilizationLast) }
        bridges = Self.bridges(between: segments, resets: resetMarkers.map(\.date))
        percentUsedNow = history.latest.map { Int($0.value.rounded()) }
        latestSampleAt = history.latest.map { Date(unixNano: $0.timeUnixNano) }
        let all = (averageResets ?? history.resets)
            .sorted { $0.timeUnixNano < $1.timeUnixNano }
            .map { ResetAverage.Reset(date: Date(unixNano: $0.timeUnixNano), utilizationLast: $0.utilizationLast) }
        unusedAtLastReset = all.last.map { 100 - $0.utilizationLast }
        let newest = [all.last?.date, history.latest.map { Date(unixNano: $0.timeUnixNano) }, history.utilization.last.map { Date(unixNano: $0.timeUnixNano) }]
            .compactMap { $0 }
            .max()
        let average = ResetAverage(
            resets: all,
            windowMinutes: history.limit.windowDurationMinutes,
            now: now ?? newest ?? Date()
        )
        averageUnusedAtReset = average.unusedPercent
        averageLabel = average.label
    }

    /// Shortest Window first, unknown Windows last, then by ID so a renamed
    /// label doesn't reshuffle the page.
    public static func rows(from histories: [LimitHistory], resets: [String: [LimitReset]]? = nil, now: Date? = nil) -> [LimitHistoryRow] {
        histories
            .sorted {
                let lhs = $0.limit.windowDurationMinutes ?? .max
                let rhs = $1.limit.windowDurationMinutes ?? .max
                return lhs != rhs ? lhs < rhs : $0.limit.id < $1.limit.id
            }
            .map { history in
                LimitHistoryRow(history: history, averageResets: resets.map { $0[history.limit.id] ?? [] }, now: now)
            }
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
        // The lower middle for an even count: with few intervals, the upper
        // middle can be the gap itself, which would hide it.
        let usual = seconds.sorted()[(seconds.count - 1) / 2]
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

    private static func bridges(between segments: [[Point]], resets: [Date]) -> [[Point]] {
        zip(segments, segments.dropFirst()).compactMap { before, after in
            guard let end = before.last, let start = after.first else {
                return nil
            }
            let resetInGap = resets.contains { $0 > end.date && $0 <= start.date }
            return resetInGap ? nil : [end, start]
        }
    }

    private static func point(_ sample: ArchivedSample) -> Point {
        Point(date: Date(unixNano: sample.timeUnixNano), percent: sample.value)
    }
}
