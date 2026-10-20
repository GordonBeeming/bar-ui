import Foundation

/// What one Limit's samples have shown so far: every rollover up to the newest
/// paired poll, and enough to carry on from there.
struct DetectedRollovers: Sendable {
    let windowMinutes: Int?
    /// The newest poll scanned; the next scan pairs it with the first newer one.
    let lastPoll: InferredResets.Poll
    /// How many reset-time samples were at or before `lastPoll`. A different
    /// count later means older samples were imported since, and the whole
    /// Limit is scanned again rather than missing a rollover among them.
    let samplesThrough: Int
    let resets: [LimitReset]
}

extension Archive {
    /// Every rollover the Limit's samples show, logged or not, oldest first.
    /// Samples are kept forever and polled every few minutes, so this extends
    /// what it found last time with newer polls instead of rescanning them all
    /// on each refresh.
    func detectedRollovers(of app: BarApp, limit: LimitDescriptor) throws -> [LimitReset] {
        let key = "\(app.rawValue)/\(limit.id)"
        if let cached = rolloverCache[key],
           cached.windowMinutes == limit.windowDurationMinutes,
           try resetsAtSampleCount(of: app, limitID: limit.id, through: cached.lastPoll.time) == cached.samplesThrough {
            let newer = InferredResets.polls(
                resetsAt: try samples(of: app, limitID: limit.id, metric: .resetsAt, since: cached.lastPoll.time + 1),
                utilization: try samples(of: app, limitID: limit.id, metric: .utilization, since: cached.lastPoll.time + 1)
            )
            guard let newest = newer.last else {
                return cached.resets
            }
            let found = InferredResets.detected(app: app, limit: limit, in: [cached.lastPoll] + newer)
            let updated = DetectedRollovers(
                windowMinutes: limit.windowDurationMinutes,
                lastPoll: newest,
                samplesThrough: try resetsAtSampleCount(of: app, limitID: limit.id, through: newest.time),
                resets: cached.resets + found
            )
            rolloverCache[key] = updated
            return updated.resets
        }

        let polls = InferredResets.polls(
            resetsAt: try samples(of: app, limitID: limit.id, metric: .resetsAt, since: Int64.min),
            utilization: try samples(of: app, limitID: limit.id, metric: .utilization, since: Int64.min)
        )
        let found = InferredResets.detected(app: app, limit: limit, in: polls)
        if let newest = polls.last {
            rolloverCache[key] = DetectedRollovers(
                windowMinutes: limit.windowDurationMinutes,
                lastPoll: newest,
                samplesThrough: try resetsAtSampleCount(of: app, limitID: limit.id, through: newest.time),
                resets: found
            )
        } else {
            rolloverCache[key] = nil
        }
        return found
    }

    private func resetsAtSampleCount(of app: BarApp, limitID: String, through time: Int64) throws -> Int {
        let statement = try prepare("""
            SELECT COUNT(*) FROM limit_samples
            WHERE app = ?1 AND limit_id = ?2 AND metric = ?3 AND time_unix_nano <= ?4
            """)
        try statement.bind(.text(app.rawValue), .text(limitID), .text(LimitMetric.resetsAt.rawValue), .integer(time))
        return try statement.step() ? Int(statement.int64(at: 0)) : 0
    }
}
