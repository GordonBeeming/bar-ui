import Foundation

/// A Limit as it stands at its latest sample.
public struct CurrentLimit: Sendable, Hashable {
    public let app: BarApp
    public let accountID: String
    public let limit: LimitDescriptor
    public let utilization: Double
    public let sampledAt: Date
    /// Nil until a reset time has been recorded for the Limit.
    public let resetsAt: Date?

    public var account: BarAppAccount {
        BarAppAccount(app: app, accountID: accountID)
    }

    public init(app: BarApp, accountID: String = BarAppAccount.defaultID, limit: LimitDescriptor, utilization: Double, sampledAt: Date, resetsAt: Date?) {
        self.app = app
        self.accountID = accountID
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
    public let accountID: String
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

    public var account: BarAppAccount {
        BarAppAccount(app: app, accountID: accountID)
    }

    public init(
        app: BarApp, accountID: String = BarAppAccount.defaultID,
        limit: LimitDescriptor,
        utilization: [ArchivedSample],
        latest: ArchivedSample?,
        resets: [LimitReset],
        peakBeforeRange: Double? = nil
    ) {
        self.app = app
        self.accountID = accountID
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
                (SELECT r.value FROM limit_samples_v2 r
                 WHERE r.app = l.app AND r.account = l.account AND r.limit_id = l.limit_id AND r.metric = ?2
                 ORDER BY r.time_unix_nano DESC LIMIT 1),
                l.account
            FROM limits_v2 l
            JOIN limit_samples_v2 u ON u.app = l.app AND u.account = l.account AND u.limit_id = l.limit_id AND u.metric = ?1
            WHERE u.time_unix_nano = (
                SELECT MAX(m.time_unix_nano) FROM limit_samples_v2 m
                WHERE m.app = l.app AND m.account = l.account AND m.limit_id = l.limit_id AND m.metric = ?1)
            -- A Limit the tool stopped reporting keeps its last sample
            -- forever, so its disappearance is what says it isn't current.
            -- An appearance at the same instant wins the tie.
            AND IFNULL((
                SELECT e.kind = ?3 AND e.time_unix_nano > u.time_unix_nano FROM limit_events_v2 e
                WHERE e.app = l.app AND e.account = l.account AND e.limit_id = l.limit_id
                ORDER BY e.time_unix_nano DESC, e.kind = ?3
                LIMIT 1), 0) = 0
            ORDER BY l.app, l.account <> 'default', l.account, l.limit_id
            """)
        try statement.bind(
            .text(LimitMetric.utilization.rawValue),
            .text(LimitMetric.resetsAt.rawValue),
            .text(LimitLifecycleEvent.Kind.disappeared.rawValue)
        )
        var limits: [CurrentLimit] = []
        while try statement.step() {
            guard let app = knownApp(statement.text(at: 0), in: "limits"),
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
                accountID: statement.text(at: 8) ?? BarAppAccount.defaultID,
                limit: limit,
                utilization: statement.double(at: 6),
                sampledAt: Date(unixNano: statement.int64(at: 5)),
                resetsAt: statement.optionalDouble(at: 7).map { Date(timeIntervalSince1970: $0) }
            ))
        }
        return limits
    }

    public func samples(of app: BarApp, account: String = BarAppAccount.defaultID, limitID: String, metric: LimitMetric) throws -> [ArchivedSample] {
        try samples(of: app, account: account, limitID: limitID, metric: metric, since: Int64.min)
    }

    func samples(of app: BarApp, account: String, limitID: String, metric: LimitMetric, since floor: Int64) throws -> [ArchivedSample] {
        let statement = try prepare("""
            SELECT time_unix_nano, value FROM limit_samples_v2
            WHERE app = ?1 AND limit_id = ?2 AND metric = ?3 AND time_unix_nano >= ?4 AND account = ?5
            ORDER BY time_unix_nano
            """)
        try statement.bind(.text(app.rawValue), .text(limitID), .text(metric.rawValue), .integer(floor), .text(account))
        var samples: [ArchivedSample] = []
        while try statement.step() {
            samples.append(ArchivedSample(timeUnixNano: statement.int64(at: 0), value: statement.double(at: 1)))
        }
        return samples
    }

    /// Every reset the Archive holds for the Bar App, by Limit ID, oldest
    /// first: the ones the Bar App logged, plus rollovers its samples show that
    /// it never logged. A Window resets a handful of times a day at most, so
    /// the whole list stays small.
    public func limitResets(of app: BarApp, account: String = BarAppAccount.defaultID) throws -> [String: [LimitReset]] {
        var byLimit = try loggedLimitResets(of: app, account: account)
        for descriptor in try limitDescriptors(of: app, account: account) {
            let logged = byLimit[descriptor.id] ?? []
            let all = try withInferredResets(logged, of: app, account: account, limit: descriptor, since: Int64.min)
            if !all.isEmpty {
                byLimit[descriptor.id] = all
            }
        }
        return byLimit
    }

    private func loggedLimitResets(of app: BarApp, account: String) throws -> [String: [LimitReset]] {
        let statement = try prepare("""
            SELECT r.limit_id, r.time_unix_nano, r.utilization_last, r.next_resets_at,
                   l.name, l.window_minutes, l.model_id
            FROM limit_resets_v2 r
            LEFT JOIN limits_v2 l ON l.app = r.app AND l.account = r.account AND l.limit_id = r.limit_id
            WHERE r.app = ?1 AND r.account = ?2
            ORDER BY r.limit_id, r.time_unix_nano
            """)
        try statement.bind(.text(app.rawValue), .text(account))
        var byLimit: [String: [LimitReset]] = [:]
        while try statement.step() {
            guard let id = statement.text(at: 0) else {
                continue
            }
            let descriptor = LimitDescriptor(
                id: id,
                name: statement.text(at: 4) ?? id,
                windowDurationMinutes: statement.optionalInt64(at: 5).map { Int($0) },
                modelID: statement.text(at: 6)
            )
            byLimit[id, default: []].append(LimitReset(
                app: app,
                accountID: account,
                limit: descriptor,
                timeUnixNano: statement.int64(at: 1),
                utilizationLast: statement.double(at: 2),
                nextResetsAt: statement.optionalDouble(at: 3).map { Date(timeIntervalSince1970: $0) }
            ))
        }
        return byLimit
    }

    /// Every Limit the Archive holds for the Bar App, each with its
    /// utilisation samples and resets from `since` on (all of them when nil).
    /// A Limit with nothing in the range still comes back, so it can say so.
    public func limitHistories(of app: BarApp, account: String = BarAppAccount.defaultID, since: Date?) throws -> [LimitHistory] {
        let floor = since?.unixNano ?? Int64.min
        let descriptors = try limitDescriptors(of: app, account: account)

        let resets = try prepare("""
            SELECT time_unix_nano, utilization_last, next_resets_at FROM limit_resets_v2
            WHERE app = ?1 AND limit_id = ?2 AND time_unix_nano >= ?3 AND account = ?4
            ORDER BY time_unix_nano
            """)
        let latest = try prepare("""
            SELECT time_unix_nano, value FROM limit_samples_v2
            WHERE app = ?1 AND limit_id = ?2 AND metric = ?3 AND account = ?4
            ORDER BY time_unix_nano DESC LIMIT 1
            """)
        var histories: [LimitHistory] = []
        for descriptor in descriptors {
            // Read from a Window before the range: the poll before a reset at the
            // range's start is needed to recover it, and a reset just before the
            // range bounds the peak the range starts from.
            let lookback = Self.inferenceFloor(for: floor, limit: descriptor)
            try resets.bind(.text(app.rawValue), .text(descriptor.id), .integer(lookback), .text(account))
            var events: [LimitReset] = []
            while try resets.step() {
                events.append(LimitReset(
                    app: app,
                    accountID: account,
                    limit: descriptor,
                    timeUnixNano: resets.int64(at: 0),
                    utilizationLast: resets.double(at: 1),
                    nextResetsAt: resets.optionalDouble(at: 2).map { Date(timeIntervalSince1970: $0) }
                ))
            }
            try latest.bind(.text(app.rawValue), .text(descriptor.id), .text(LimitMetric.utilization.rawValue), .text(account))
            let latestSample = try latest.step()
                ? ArchivedSample(timeUnixNano: latest.int64(at: 0), value: latest.double(at: 1))
                : nil
            let all = try withInferredResets(events, of: app, account: account, limit: descriptor, since: lookback)
            let lastResetBefore = all.last { $0.timeUnixNano < floor }?.timeUnixNano
            histories.append(LimitHistory(
                app: app,
                accountID: account,
                limit: descriptor,
                utilization: try samples(of: app, account: account, limitID: descriptor.id, metric: .utilization, since: floor),
                latest: latestSample,
                resets: all.filter { $0.timeUnixNano >= floor },
                peakBeforeRange: since == nil ? nil : try peakBefore(floor, of: app, account: account, limit: descriptor, lastReset: lastResetBefore)
            ))
        }
        return histories
    }

    private func limitDescriptors(of app: BarApp, account: String) throws -> [LimitDescriptor] {
        let limits = try prepare("""
            SELECT limit_id, name, window_minutes, model_id FROM limits_v2 WHERE app = ?1 AND account = ?2 ORDER BY limit_id
            """)
        try limits.bind(.text(app.rawValue), .text(account))
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
        return descriptors
    }

    /// One Window (and a day's margin) before `floor`, or everything when the
    /// Window's length isn't known. The full read is only for a range; an
    /// all-time read already starts at the beginning.
    static func inferenceFloor(for floor: Int64, limit: LimitDescriptor) -> Int64 {
        guard floor != Int64.min, let minutes = limit.windowDurationMinutes else {
            return Int64.min
        }
        let reach = (Int64(minutes) * 60 + 86_400) * 1_000_000_000
        return floor > Int64.min + reach ? floor - reach : Int64.min
    }

    /// The logged resets (read from `floor` on) with the rollovers recovered
    /// from the samples from `floor` on that none of them stands for, oldest
    /// first.
    private func withInferredResets(
        _ logged: [LimitReset],
        of app: BarApp,
        account: String,
        limit: LimitDescriptor,
        since floor: Int64
    ) throws -> [LimitReset] {
        let detected = try detectedRollovers(of: app, account: account, limit: limit).filter { $0.timeUnixNano >= floor }
        let inferred = InferredResets.unlogged(detected, logged: logged, windowMinutes: limit.windowDurationMinutes)
        guard !inferred.isEmpty else {
            return logged
        }
        return (logged + inferred).sorted { $0.timeUnixNano < $1.timeUnixNano }
    }

    /// How high the Window open at `floor` had got before it. Reads back no
    /// further than that Window: to its reset (logged or recovered from the
    /// samples, `lastReset`), or one Window length when there's none in reach.
    /// Without either, the Limit's last earlier sample stands in for the Window.
    private func peakBefore(_ floor: Int64, of app: BarApp, account: String, limit: LimitDescriptor, lastReset: Int64?) throws -> Double? {
        let latest = try prepare("""
            SELECT time_unix_nano, value FROM limit_samples_v2
            WHERE app = ?1 AND limit_id = ?2 AND metric = ?3 AND time_unix_nano < ?4 AND account = ?5
            ORDER BY time_unix_nano DESC LIMIT 1
            """)
        try latest.bind(.text(app.rawValue), .text(limit.id), .text(LimitMetric.utilization.rawValue), .integer(floor), .text(account))
        guard try latest.step() else {
            return nil
        }
        let lastSample = ArchivedSample(timeUnixNano: latest.int64(at: 0), value: latest.double(at: 1))

        if let lastReset, lastReset > lastSample.timeUnixNano {
            return 0
        }

        let windowStart = limit.windowDurationMinutes.map { floor - Int64($0) * 60 * 1_000_000_000 }
        guard let start = [lastReset, windowStart].compactMap({ $0 }).max() else {
            return lastSample.value
        }
        let peak = try prepare("""
            SELECT MAX(value) FROM limit_samples_v2
            WHERE app = ?1 AND limit_id = ?2 AND metric = ?3 AND time_unix_nano >= ?4 AND time_unix_nano < ?5 AND account = ?6
            """)
        try peak.bind(.text(app.rawValue), .text(limit.id), .text(LimitMetric.utilization.rawValue), .integer(start), .integer(floor), .text(account))
        // The last sample may be older than one Window length, which leaves
        // nothing in the Window; a fresh Window starts from normal.
        return try peak.step() ? peak.optionalDouble(at: 0) ?? 0 : 0
    }

    /// Every Account of a Bar App that has anything in the Archive,
    /// the default first. A Bar App with nothing archived has none.
    public func accounts() throws -> [BarAppAccount] {
        let statement = try prepare("""
            SELECT app, account FROM limits_v2
            UNION SELECT app, account FROM limit_samples_v2
            UNION SELECT app, account FROM limit_resets_v2
            UNION SELECT app, account FROM limit_events_v2
            UNION SELECT app, account FROM token_samples_v2
            UNION SELECT app, account FROM perk_points_v2
            UNION SELECT app, account FROM perk_gone_events_v2
            UNION SELECT app, account FROM perk_available_events_v2
            """)
        var accounts: [BarAppAccount] = []
        while try statement.step() {
            guard let app = knownApp(statement.text(at: 0), in: "limits"), let id = statement.text(at: 1) else {
                continue
            }
            accounts.append(BarAppAccount(app: app, accountID: id))
        }
        return accounts.sorted()
    }

    /// The label each Account last gave itself, such as an email address.
    public func accountNames() throws -> [BarAppAccount: String] {
        let statement = try prepare("SELECT app, account, name FROM account_names")
        var names: [BarAppAccount: String] = [:]
        while try statement.step() {
            guard let app = knownApp(statement.text(at: 0), in: "account_names"),
                  let id = statement.text(at: 1), let name = statement.text(at: 2) else {
                continue
            }
            names[BarAppAccount(app: app, accountID: id)] = name
        }
        return names
    }
}
