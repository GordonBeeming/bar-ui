import Foundation

/// How fast a Limit's utilisation has been rising, in percentage points per
/// hour, over a span that looks back from now (the last hour by default).
public struct BurnRate: Sendable, Equatable {
    /// How far back the shown rate looks.
    public static let defaultLookback: TimeInterval = 3_600

    /// The longest span a pace warning ever looks back over, so the
    /// history it needs stays bounded.
    static let longestPaceLookback: TimeInterval = 24 * 3_600

    public let percentPerHour: Double
    /// How far back this rate looked.
    public let lookback: TimeInterval
    /// The time between the first and last samples the rate came from.
    public let span: TimeInterval

    /// A rate drawn from samples covering less than half its lookback is
    /// mostly the start of a Window and says little about the pace.
    public var isSustained: Bool {
        span >= lookback / 2
    }

    /// The span a pace warning looks back over: a tenth of the Window, so a
    /// week is judged on most of a day, and never less than an hour.
    static func paceLookback(windowMinutes: Int?) -> TimeInterval {
        guard let windowMinutes, windowMinutes > 0 else {
            return defaultLookback
        }
        return min(max(TimeInterval(windowMinutes) * 60 / 10, defaultLookback), longestPaceLookback)
    }

    /// Nil when the span can't say how fast the Limit is rising: fewer than
    /// two samples since the last reset, or nothing recent.
    ///
    /// A reset ends the count whether or not the Bar App logged it. A fall in
    /// utilisation is treated the same way, because the reset event can reach
    /// the Archive after the samples that follow it.
    public init?(samples: [ArchivedSample], resetTimes: [Date], now: Date, lookback: TimeInterval = BurnRate.defaultLookback) {
        self.lookback = lookback
        let windowStart = now.addingTimeInterval(-lookback)
        let lastReset = resetTimes.filter { $0 <= now }.max()
        let floor = max(windowStart, lastReset ?? windowStart)
        let recent = samples
            .map { (time: Date(unixNano: $0.timeUnixNano), value: $0.value) }
            .filter { $0.time >= floor && $0.time <= now && ($0.time > windowStart) }
            .sorted { $0.time < $1.time }

        var sinceFall = recent[...]
        for (index, pair) in zip(recent.indices.dropFirst(), zip(recent, recent.dropFirst())) where pair.1.value < pair.0.value {
            sinceFall = recent[index...]
        }

        guard let first = sinceFall.first, let last = sinceFall.last else {
            return nil
        }
        span = last.time.timeIntervalSince(first.time)
        guard span > 0 else {
            return nil
        }
        percentPerHour = (last.value - first.value) / (span / 3_600)
    }

    /// How long until utilisation reaches 100% at this rate. Nil when it isn't
    /// rising or is already full.
    public func timeUntilFull(from utilization: Double) -> TimeInterval? {
        guard percentPerHour > 0, utilization < 100 else {
            return nil
        }
        return (100 - utilization) / percentPerHour * 3_600
    }

    /// `timeUntilFull`, but only when 100% comes before the Window resets and
    /// everything is known. After the reset time has passed the Limit is about
    /// to start over, so there is nothing to warn about.
    public func timeUntilFullBeforeReset(from utilization: Double, resetsAt: Date?, now: Date) -> TimeInterval? {
        guard let resetsAt, resetsAt > now, let untilFull = timeUntilFull(from: utilization) else {
            return nil
        }
        return untilFull < resetsAt.timeIntervalSince(now) ? untilFull : nil
    }
}
