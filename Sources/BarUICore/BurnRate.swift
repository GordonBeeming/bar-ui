import Foundation

/// How fast a Limit's utilisation has been rising over the last hour, in
/// percentage points per hour.
public struct BurnRate: Sendable, Equatable {
    /// How far back the rate looks.
    static let lookback: TimeInterval = 3_600

    public let percentPerHour: Double

    /// Nil when the last hour can't say how fast the Limit is rising: fewer
    /// than two samples since the last reset, or nothing recent.
    ///
    /// A reset ends the count whether or not the Bar App logged it. A fall in
    /// utilisation is treated the same way, because the reset event can reach
    /// the Archive after the samples that follow it.
    public init?(samples: [ArchivedSample], resetTimes: [Date], now: Date) {
        let windowStart = now.addingTimeInterval(-Self.lookback)
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
        let hours = last.time.timeIntervalSince(first.time) / 3_600
        guard hours > 0 else {
            return nil
        }
        percentPerHour = (last.value - first.value) / hours
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
