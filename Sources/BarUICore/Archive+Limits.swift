import Foundation

/// A Limit as it stands at its latest sample.
public struct CurrentLimit: Sendable, Hashable {
    public let app: BarApp
    public let limit: LimitDescriptor
    public let utilization: Double
    public let sampledAt: Date
    /// Nil until a reset time has been recorded for the Limit.
    public let resetsAt: Date?

    public init(app: BarApp, limit: LimitDescriptor, utilization: Double, sampledAt: Date, resetsAt: Date?) {
        self.app = app
        self.limit = limit
        self.utilization = utilization
        self.sampledAt = sampledAt
        self.resetsAt = resetsAt
    }
}

public struct ArchivedSample: Sendable, Hashable {
    public let timeUnixNano: Int64
    public let value: Double

    public init(timeUnixNano: Int64, value: Double) {
        self.timeUnixNano = timeUnixNano
        self.value = value
    }
}

/// One Limit's utilisation and resets over a stretch of the Archive.
public struct LimitHistory: Sendable, Hashable {
    public let app: BarApp
    public let limit: LimitDescriptor
    public let utilization: [ArchivedSample]
    /// The newest utilisation sample ever archived, even when it falls before
    /// the range the rest was read for.
    public let latest: ArchivedSample?
    public let resets: [LimitReset]
    /// The highest utilisation the Window open when the range began had
    /// reached before it began: 0 when a reset came after the Limit's last
    /// earlier sample, nil when the Limit has no sample before the range (or
    /// the range reaches back to the start). Crossings inside the range are
    /// judged against it, so one the Window made before isn't repeated.
    public let peakBeforeRange: Double?

    public init(
        app: BarApp,
        limit: LimitDescriptor,
        utilization: [ArchivedSample],
        latest: ArchivedSample?,
        resets: [LimitReset],
        peakBeforeRange: Double? = nil
    ) {
        self.app = app
        self.limit = limit
        self.utilization = utilization
        self.latest = latest
        self.resets = resets
        self.peakBeforeRange = peakBeforeRange
    }
}

extension Archive {
    public func currentLimits() throws -> [CurrentLimit] {
        let statement = try prepare("""
            SELECT l.app, l.limit_id, l.name, l.window_minutes, l.model_id, u.time_unix_nano, u.value,
                (SELECT r.value FROM limit_samples r
                 WHERE r.app = l.app AND r.limit_id = l.limit_id AND r.metric = ?2
                 ORDER BY r.time_unix_nano DESC LIMIT 1)
            FROM limits l
            JOIN limit_samples u ON u.app = l.app AND u.limit_id = l.limit_id AND u.metric = ?1
            WHERE u.time_unix_nano = (
                SELECT MAX(m.time_unix_nano) FROM limit_samples m
                WHERE m.app = l.app AND m.limit_id = l.limit_id AND m.metric = ?1)
            -- A Limit the tool stopped reporting keeps its last sample
            -- forever, so its disappearance is what says it isn't current.
            -- An appearance at the same instant wins the tie.
            AND IFNULL((
                SELECT e.kind = ?3 AND e.time_unix_nano > u.time_unix_nano FROM limit_events e
                WHERE e.app = l.app AND e.limit_id = l.limit_id
                ORDER BY e.time_unix_nano DESC, e.kind = ?3
                LIMIT 1), 0) = 0
            ORDER BY l.app, l.limit_id
            """)
        try statement.bind(
            .text(LimitMetric.utilization.rawValue),
            .text(LimitMetric.resetsAt.rawValue),
            .text(LimitLifecycleEvent.Kind.disappeared.rawValue)
        )
        var limits: [CurrentLimit] = []
        while try statement.step() {
            // A Bar App this build doesn't know (written by a newer Bar UI)
            // can't be shown, but its rows stay in the Archive untouched.
            guard let appName = statement.text(at: 0), let app = BarApp(rawValue: appName),
                  let id = statement.text(at: 1), let name = statement.text(at: 2) else {
                continue
            }
            let limit = LimitDescriptor(
                id: id,
                name: name,
                windowDurationMinutes: statement.optionalInt64(at: 3).map { Int($0) },
                modelID: statement.text(at: 4)
            )
            limits.append(CurrentLimit(
                app: app,
                limit: limit,
                utilization: statement.double(at: 6),
                sampledAt: Date(unixNano: statement.int64(at: 5)),
                resetsAt: statement.optionalDouble(at: 7).map { Date(timeIntervalSince1970: $0) }
            ))
        }
        return limits
    }

    public func samples(of app: BarApp, limitID: String, metric: LimitMetric) throws -> [ArchivedSample] {
        try samples(of: app, limitID: limitID, metric: metric, since: Int64.min)
    }

    private func samples(of app: BarApp, limitID: String, metric: LimitMetric, since floor: Int64) throws -> [ArchivedSample] {
        let statement = try prepare("""
            SELECT time_unix_nano, value FROM limit_samples
            WHERE app = ?1 AND limit_id = ?2 AND metric = ?3 AND time_unix_nano >= ?4
            ORDER BY time_unix_nano
            """)
        try statement.bind(.text(app.rawValue), .text(limitID), .text(metric.rawValue), .integer(floor))
        var samples: [ArchivedSample] = []
        while try statement.step() {
            samples.append(ArchivedSample(timeUnixNano: statement.int64(at: 0), value: statement.double(at: 1)))
        }
        return samples
    }

    /// Every Limit the Archive holds for the Bar App, each with its
    /// utilisation samples and resets from `since` on (all of them when nil).
    /// A Limit with nothing in the range still comes back, so it can say so.
    public func limitHistories(of app: BarApp, since: Date?) throws -> [LimitHistory] {
        let floor = since?.unixNano ?? Int64.min
        let limits = try prepare("""
            SELECT limit_id, name, window_minutes, model_id FROM limits WHERE app = ?1 ORDER BY limit_id
            """)
        try limits.bind(.text(app.rawValue))
        var descriptors: [LimitDescriptor] = []
        while try limits.step() {
            guard let id = limits.text(at: 0), let name = limits.text(at: 1) else {
                continue
            }
            descriptors.append(LimitDescriptor(
                id: id,
                name: name,
                windowDurationMinutes: limits.optionalInt64(at: 2).map { Int($0) },
                modelID: limits.text(at: 3)
            ))
        }

        let resets = try prepare("""
            SELECT time_unix_nano, utilization_last, next_resets_at FROM limit_resets
            WHERE app = ?1 AND limit_id = ?2 AND time_unix_nano >= ?3
            ORDER BY time_unix_nano
            """)
        let latest = try prepare("""
            SELECT time_unix_nano, value FROM limit_samples
            WHERE app = ?1 AND limit_id = ?2 AND metric = ?3
            ORDER BY time_unix_nano DESC LIMIT 1
            """)
        var histories: [LimitHistory] = []
        for descriptor in descriptors {
            try resets.bind(.text(app.rawValue), .text(descriptor.id), .integer(floor))
            var events: [LimitReset] = []
            while try resets.step() {
                events.append(LimitReset(
                    app: app,
                    limit: descriptor,
                    timeUnixNano: resets.int64(at: 0),
                    utilizationLast: resets.double(at: 1),
                    nextResetsAt: resets.optionalDouble(at: 2).map { Date(timeIntervalSince1970: $0) }
                ))
            }
            try latest.bind(.text(app.rawValue), .text(descriptor.id), .text(LimitMetric.utilization.rawValue))
            let latestSample = try latest.step()
                ? ArchivedSample(timeUnixNano: latest.int64(at: 0), value: latest.double(at: 1))
                : nil
            histories.append(LimitHistory(
                app: app,
                limit: descriptor,
                utilization: try samples(of: app, limitID: descriptor.id, metric: .utilization, since: floor),
                latest: latestSample,
                resets: events,
                peakBeforeRange: since == nil ? nil : try peakBefore(floor, of: app, limit: descriptor)
            ))
        }
        return histories
    }

    /// How high the Window open at `floor` had got before it. Reads back no
    /// further than that Window: to its reset, or one Window length when the
    /// reset wasn't logged. Without either, the Limit's last earlier sample
    /// stands in for the Window.
    private func peakBefore(_ floor: Int64, of app: BarApp, limit: LimitDescriptor) throws -> Double? {
        let latest = try prepare("""
            SELECT time_unix_nano, value FROM limit_samples
            WHERE app = ?1 AND limit_id = ?2 AND metric = ?3 AND time_unix_nano < ?4
            ORDER BY time_unix_nano DESC LIMIT 1
            """)
        try latest.bind(.text(app.rawValue), .text(limit.id), .text(LimitMetric.utilization.rawValue), .integer(floor))
        guard try latest.step() else {
            return nil
        }
        let lastSample = ArchivedSample(timeUnixNano: latest.int64(at: 0), value: latest.double(at: 1))

        let reset = try prepare("""
            SELECT MAX(time_unix_nano) FROM limit_resets
            WHERE app = ?1 AND limit_id = ?2 AND time_unix_nano < ?3
            """)
        try reset.bind(.text(app.rawValue), .text(limit.id), .integer(floor))
        let lastReset = try reset.step() ? reset.optionalInt64(at: 0) : nil
        if let lastReset, lastReset > lastSample.timeUnixNano {
            return 0
        }

        let windowStart = limit.windowDurationMinutes.map { floor - Int64($0) * 60 * 1_000_000_000 }
        guard let start = [lastReset, windowStart].compactMap({ $0 }).max() else {
            return lastSample.value
        }
        let peak = try prepare("""
            SELECT MAX(value) FROM limit_samples
            WHERE app = ?1 AND limit_id = ?2 AND metric = ?3 AND time_unix_nano >= ?4 AND time_unix_nano < ?5
            """)
        try peak.bind(.text(app.rawValue), .text(limit.id), .text(LimitMetric.utilization.rawValue), .integer(start), .integer(floor))
        // The last sample may be older than one Window length, which leaves
        // nothing in the Window; a fresh Window starts from normal.
        return try peak.step() ? peak.optionalDouble(at: 0) ?? 0 : 0
    }
}
