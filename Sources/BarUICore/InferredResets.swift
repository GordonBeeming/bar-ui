import Foundation

/// Window rollovers recovered from a Limit's archived samples, for the ones its
/// Bar App never logged as `bar.limit.reset`. A tool can reset a Window early,
/// days before its reset time, and a Bar App that only expects a Window to run
/// to its end misses those; the samples still show the reset time jumping and
/// usage falling back.
public enum InferredResets {
    /// More than a reset time drifts between reads, and more than a Window that
    /// hasn't started yet creeps forward per poll.
    static let jumpTolerance: Double = 3_600
    /// A rollover this close to a logged reset is that reset, not another one.
    static let loggedMatch: Int64 = 3_600 * 1_000_000_000
    /// Matching the Bar Apps' own reset check: a fall to zero, or a fall of
    /// more than this that ends under `usageFloor`.
    static let usageDrop: Double = 25
    static let usageFloor: Double = 10

    /// Every rollover in the samples that no logged reset already covers,
    /// oldest first. Reset-time and utilisation samples are paired by their
    /// exact time, because a Bar App writes both in the same sample; one
    /// without the other is skipped rather than guessed at.
    public static func rollovers(
        app: BarApp,
        limit: LimitDescriptor,
        resetsAt: [ArchivedSample],
        utilization: [ArchivedSample],
        logged: [LimitReset]
    ) -> [LimitReset] {
        let usageByTime = Dictionary(utilization.map { ($0.timeUnixNano, $0.value) }, uniquingKeysWith: { _, latest in latest })
        let polls = resetsAt
            .sorted { $0.timeUnixNano < $1.timeUnixNano }
            .compactMap { sample in usageByTime[sample.timeUnixNano].map { (time: sample.timeUnixNano, resetsAt: sample.value, usage: $0) } }
        let loggedTimes = logged.map(\.timeUnixNano)

        var found: [LimitReset] = []
        for (before, after) in zip(polls, polls.dropFirst()) {
            let now = Double(after.time) / 1_000_000_000
            guard rolledOver(
                oldResetsAt: before.resetsAt, oldUsage: before.usage,
                newResetsAt: after.resetsAt, newUsage: after.usage,
                now: now, windowMinutes: limit.windowDurationMinutes
            ) else {
                continue
            }
            guard !loggedTimes.contains(where: { abs($0 - after.time) <= loggedMatch }) else {
                continue
            }
            found.append(LimitReset(
                app: app,
                limit: limit,
                timeUnixNano: after.time,
                utilizationLast: before.usage,
                nextResetsAt: Date(timeIntervalSince1970: after.resetsAt)
            ))
        }
        return found
    }

    /// The same rule CodexBar logs resets by, plus a Window that had already
    /// ended by the next poll (the Mac asleep across its reset).
    static func rolledOver(
        oldResetsAt: Double, oldUsage: Double,
        newResetsAt: Double, newUsage: Double,
        now: Double, windowMinutes: Int?
    ) -> Bool {
        let jump = newResetsAt - oldResetsAt
        guard jump > jumpTolerance else {
            return false
        }
        guard let windowMinutes else {
            return true
        }
        let window = Double(windowMinutes) * 60
        if jump >= window / 2 || oldResetsAt <= now {
            return true
        }
        if (oldUsage > 0 && newUsage == 0) || (oldUsage - newUsage > usageDrop && newUsage < usageFloor) {
            return true
        }
        // A Window not started yet also reads as a full Window ahead; usage
        // going down is what tells a real reset apart.
        return newUsage < oldUsage && abs(newResetsAt - now - window) <= jumpTolerance
    }
}
