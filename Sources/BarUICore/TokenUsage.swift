import Foundation

/// The period the Overview's token chart and tiles cover.
public enum TokenRange: String, CaseIterable, Identifiable, Sendable {
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
    fileprivate var span: TimeInterval? {
        switch self {
        case .day: 24 * 3_600
        case .week: 7 * 24 * 3_600
        case .month: 30 * 24 * 3_600
        case .all: nil
        }
    }

    /// When the range begins, counting back from `now`. Nil for All time.
    public func start(now: Date) -> Date? {
        span.map { now.addingTimeInterval(-$0) }
    }

    /// A day of data is too few points at daily resolution to show a shape.
    fileprivate var bucketComponent: Calendar.Component {
        self == .day ? .hour : .day
    }
}

/// Token usage over one range, worked out from the Archive's cumulative
/// counters.
public struct TokenUsage: Sendable, Equatable {
    public struct Bucket: Sendable, Equatable {
        public let start: Date
        public let tokensByApp: [BarApp: Int64]
    }

    /// Oldest first, with no gaps: a quiet period is a bucket of zero.
    public let buckets: [Bucket]
    public let totalByApp: [BarApp: Int64]
    /// Input, cache reads and cache writes, and output. Reasoning is inside
    /// output already, so it is never added.
    public let total: Int64
    /// All input, whether or not it touched the cache.
    public let input: Int64
    public let output: Int64
    public let reasoning: Int64
    public let cacheRead: Int64
    /// What each model used, by Token Type, across every Bar App. Reasoning is
    /// left out because output already contains it.
    public let tokensByModel: [String: [TokenType: Int64]]
    private let tokensByAppAndModel: [BarApp: [String: [TokenType: Int64]]]

    /// What each model used in one Bar App, by Token Type. Unlike
    /// `tokensByModel` this keeps Reasoning, so a page can show it; it must not
    /// be priced or summed with the other types.
    public func tokens(of app: BarApp) -> [String: [TokenType: Int64]] {
        tokensByAppAndModel[app] ?? [:]
    }

    /// Nil when there was no output to take a share of.
    public var reasoningShareOfOutput: Double? {
        output > 0 ? min(Double(reasoning) / Double(output), 1) : nil
    }

    /// Nil when there was no input to take a share of.
    public var cacheReadShareOfInput: Double? {
        input > 0 ? min(Double(cacheRead) / Double(input), 1) : nil
    }

    public init(samples: [TokenSample], range: TokenRange, now: Date, calendar: Calendar = .current) {
        self.init(
            samples: samples,
            windowStart: range.start(now: now),
            bucketComponent: range.bucketComponent,
            now: now,
            calendar: calendar
        )
    }

    /// For periods that aren't a `TokenRange`, such as the last hour.
    init(samples: [TokenSample], windowStart: Date?, bucketComponent: Calendar.Component, now: Date, calendar: Calendar) {
        let increases = Self.increases(in: samples)
            .filter { increase in
                let time = Date(unixNano: increase.timeUnixNano)
                return time <= now && windowStart.map { time > $0 } != false
            }

        var totalByApp: [BarApp: Int64] = [:]
        var input: Int64 = 0
        var output: Int64 = 0
        var reasoning: Int64 = 0
        var cacheRead: Int64 = 0
        var byBucket: [Date: [BarApp: Int64]] = [:]
        var tokensByModel: [String: [TokenType: Int64]] = [:]
        var tokensByAppAndModel: [BarApp: [String: [TokenType: Int64]]] = [:]
        for increase in increases {
            tokensByAppAndModel[increase.app, default: [:]][increase.model, default: [:]][increase.tokenType, default: 0] += increase.tokens
            switch increase.tokenType {
            case .reasoning:
                reasoning += increase.tokens
                continue
            case .output:
                output += increase.tokens
            case .cacheRead:
                cacheRead += increase.tokens
                input += increase.tokens
            case .input, .cacheWrite5m, .cacheWrite1h, .cacheWrite:
                input += increase.tokens
            }
            totalByApp[increase.app, default: 0] += increase.tokens
            tokensByModel[increase.model, default: [:]][increase.tokenType, default: 0] += increase.tokens
            let start = calendar.dateInterval(of: bucketComponent, for: Date(unixNano: increase.timeUnixNano))?.start
                ?? Date(unixNano: increase.timeUnixNano)
            byBucket[start, default: [:]][increase.app, default: 0] += increase.tokens
        }

        self.totalByApp = totalByApp
        self.total = input + output
        self.input = input
        self.output = output
        self.reasoning = reasoning
        self.cacheRead = cacheRead
        self.tokensByModel = tokensByModel
        self.tokensByAppAndModel = tokensByAppAndModel
        self.buckets = Self.filledBuckets(byBucket, windowStart: windowStart, now: now, component: bucketComponent, calendar: calendar)
    }

    // MARK: - Counters to increases

    private struct Increase {
        let app: BarApp
        let model: String
        let tokenType: TokenType
        let timeUnixNano: Int64
        let tokens: Int64
    }

    private struct SeriesKey: Hashable {
        let app: BarApp
        let model: String
        let tokenType: TokenType
    }

    /// What each counter added at each sample. A new start time means the
    /// counter began again from zero, so its whole value is new usage and the
    /// old counter's last value is irrelevant. A fall under the same start
    /// breaks the spec; it is taken as no usage and the lower value becomes
    /// the new baseline, so it can't be counted twice when the counter climbs.
    private static func increases(in samples: [TokenSample]) -> [Increase] {
        var series: [SeriesKey: [TokenSample]] = [:]
        for sample in samples {
            series[SeriesKey(app: sample.app, model: sample.model, tokenType: sample.tokenType), default: []].append(sample)
        }

        var increases: [Increase] = []
        for (key, points) in series {
            var previous: TokenSample?
            for point in points.sorted(by: { $0.timeUnixNano < $1.timeUnixNano }) {
                let tokens: Int64
                if let previous, previous.startTimeUnixNano == point.startTimeUnixNano {
                    tokens = max(point.count - previous.count, 0)
                } else {
                    tokens = point.count
                }
                previous = point
                if tokens > 0 {
                    increases.append(Increase(app: key.app, model: key.model, tokenType: key.tokenType, timeUnixNano: point.timeUnixNano, tokens: tokens))
                }
            }
        }
        return increases
    }

    private static func filledBuckets(
        _ byBucket: [Date: [BarApp: Int64]],
        windowStart: Date?,
        now: Date,
        component: Calendar.Component,
        calendar: Calendar
    ) -> [Bucket] {
        guard let first = windowStart.flatMap({ calendar.dateInterval(of: component, for: $0)?.start }) ?? byBucket.keys.min(),
              let last = calendar.dateInterval(of: component, for: now)?.start else {
            return []
        }
        var buckets: [Bucket] = []
        var cursor = first
        while cursor <= last {
            buckets.append(Bucket(start: cursor, tokensByApp: byBucket[cursor] ?? [:]))
            guard let next = calendar.date(byAdding: component, value: 1, to: cursor), next > cursor else {
                break
            }
            cursor = next
        }
        return buckets
    }
}
