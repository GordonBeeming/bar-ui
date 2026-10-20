import Foundation

/// Window rollovers recovered from a Limit's archived samples, for the ones its
/// Bar App never logged as `bar.limit.reset`. A tool can reset a Window early,
/// days before its reset time, and a Bar App that only expects a Window to run
/// to its end misses those; the samples still show the reset time jumping and
/// usage falling back.
public enum InferredResets {
    /// One poll: its time, the reset time it reported (Unix seconds), and usage.
    struct Poll: Sendable, Equatable {
        let time: Int64
        let resetsAt: Double
        let usage: Double
    }

    /// More than a reset time drifts between reads. Weaker signals (a Window
    /// already over, a full Window ahead) need a jump past this.
    static let jumpTolerance: Double = 3_600
    /// The least a reset time must move for a decisive usage drop to count: a
    /// short Window reset early moves its deadline only by what had elapsed.
    static let minimumJump: Double = 60
    /// A rollover this close to a logged reset is that reset, not another one.
    /// Never more than half a Window, so a short Window's next rollover stays
    /// its own reset.
    static let loggedMatch: Int64 = 3_600 * 1_000_000_000
    /// Matching the Bar Apps' own reset check: a fall to zero, or a fall of
    /// more than this that ends under `usageFloor`.
    static let usageDrop: Double = 25
    static let usageFloor: Double = 10

    /// Every rollover in the samples that no logged reset already covers,
    /// oldest first.
    public static func rollovers(
        app: BarApp,
        limit: LimitDescriptor,
        resetsAt: [ArchivedSample],
        utilization: [ArchivedSample],
        logged: [LimitReset]
    ) -> [LimitReset] {
        let found = detected(app: app, limit: limit, in: polls(resetsAt: resetsAt, utilization: utilization))
        return unlogged(found, logged: logged, windowMinutes: limit.windowDurationMinutes)
    }

    /// Reset-time and utilisation samples paired by their exact time, oldest
    /// first. A Bar App writes both in the same sample; one without the other
    /// is skipped rather than guessed at.
    static func polls(resetsAt: [ArchivedSample], utilization: [ArchivedSample]) -> [Poll] {
        let usageByTime = Dictionary(utilization.map { ($0.timeUnixNano, $0.value) }, uniquingKeysWith: { _, latest in latest })
        return resetsAt
            .sorted { $0.timeUnixNano < $1.timeUnixNano }
            .compactMap { sample in usageByTime[sample.timeUnixNano].map { Poll(time: sample.timeUnixNano, resetsAt: sample.value, usage: $0) } }
    }

    /// Every rollover between consecutive polls, whether or not it was logged.
    /// Doesn't depend on the logged resets, so a caller can keep these and
    /// extend them with newer polls.
    static func detected(app: BarApp, limit: LimitDescriptor, in polls: [Poll]) -> [LimitReset] {
        var found: [LimitReset] = []
        for (before, after) in zip(polls, polls.dropFirst()) {
            guard rolledOver(before: before, after: after, windowMinutes: limit.windowDurationMinutes) else {
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

    /// The detected rollovers no logged reset already stands for.
    static func unlogged(_ detected: [LimitReset], logged: [LimitReset], windowMinutes: Int?) -> [LimitReset] {
        let radius = matchRadius(windowMinutes: windowMinutes)
        let loggedTimes = logged.map(\.timeUnixNano)
        return detected.filter { reset in
            !loggedTimes.contains { abs($0 - reset.timeUnixNano) <= radius }
        }
    }

    static func matchRadius(windowMinutes: Int?) -> Int64 {
        guard let windowMinutes else {
            return loggedMatch
        }
        // Strictly under half a Window, so the next rollover is never matched.
        let half = Int64(windowMinutes) * 30 * 1_000_000_000 - 1
        return min(loggedMatch, half)
    }

    static func decisiveDrop(from old: Double, to new: Double) -> Bool {
        (old > 0 && new == 0) || (old - new > usageDrop && new < usageFloor)
    }

    /// The same rule CodexBar logs resets by, plus a Window whose deadline fell
    /// between the two polls (the Mac asleep across its reset).
    static func rolledOver(before: Poll, after: Poll, windowMinutes: Int?) -> Bool {
        // A Window nobody has used floats a full Window ahead of every poll, so
        // after a gap, once it expires, or when use finally starts, its reset
        // time jumps like a real rollover. At 0% beforehand there was nothing
        // to reset, so it never counts.
        if before.usage == 0 {
            return false
        }
        let then = Double(before.time) / 1_000_000_000
        let now = Double(after.time) / 1_000_000_000
        // A deadline already past at the earlier poll was reported stale and is
        // only being corrected now; that rollover belongs to the pair before.
        if before.resetsAt <= then {
            return false
        }
        let jump = after.resetsAt - before.resetsAt
        guard jump >= minimumJump else {
            return false
        }
        let dropped = decisiveDrop(from: before.usage, to: after.usage)
        guard let windowMinutes else {
            // Without a Window length, only a decisive drop says a jump was a
            // reset rather than a reset time being corrected.
            return jump > jumpTolerance && dropped
        }
        let window = Double(windowMinutes) * 60
        // A full rollover, or a decisive drop with the deadline moving, counts
        // whatever the Window's length, so a short Window isn't held to the
        // hour of drift tolerance.
        if jump >= window / 2 || dropped {
            return true
        }
        guard jump > jumpTolerance else {
            return false
        }
        if before.resetsAt <= now {
            return true
        }
        // A full Window ahead alone could still be a floating Window; usage
        // going down is what tells a real reset apart.
        return after.usage < before.usage && abs(after.resetsAt - now - window) <= jumpTolerance
    }
}
