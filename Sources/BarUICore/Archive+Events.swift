import Foundation

extension Archive {
    // Each of these reads from `since` on, or everything when it is nil.

    public func limitLifecycleEvents(since: Date? = nil) throws -> [LimitLifecycleEvent] {
        let statement = try prepare("""
            SELECT e.app, e.limit_id, e.kind, e.time_unix_nano, l.name, l.window_minutes, l.model_id
            FROM limit_events e
            JOIN limits l ON l.app = e.app AND l.limit_id = e.limit_id
            WHERE e.time_unix_nano >= ?1
            ORDER BY e.time_unix_nano, e.app, e.limit_id
            """)
        try statement.bind(.integer(since?.unixNano ?? Int64.min))
        var events: [LimitLifecycleEvent] = []
        while try statement.step() {
            guard let appName = statement.text(at: 0), let app = BarApp(rawValue: appName),
                  let id = statement.text(at: 1),
                  let kindName = statement.text(at: 2), let kind = LimitLifecycleEvent.Kind(rawValue: kindName),
                  let name = statement.text(at: 4) else {
                continue
            }
            events.append(LimitLifecycleEvent(
                app: app,
                limit: LimitDescriptor(
                    id: id,
                    name: name,
                    windowDurationMinutes: statement.optionalInt64(at: 5).map { Int($0) },
                    modelID: statement.text(at: 6)
                ),
                kind: kind,
                timeUnixNano: statement.int64(at: 3)
            ))
        }
        return events
    }

    public func trackingStarts(since: Date? = nil) throws -> [TrackingStartedEvent] {
        let statement = try prepare("""
            SELECT app, time_unix_nano, interval_minutes FROM tracking_starts
            WHERE time_unix_nano >= ?1
            ORDER BY time_unix_nano, app
            """)
        try statement.bind(.integer(since?.unixNano ?? Int64.min))
        var events: [TrackingStartedEvent] = []
        while try statement.step() {
            guard let appName = statement.text(at: 0), let app = BarApp(rawValue: appName) else {
                continue
            }
            events.append(TrackingStartedEvent(
                app: app,
                intervalMinutes: Int(statement.int64(at: 2)),
                timeUnixNano: statement.int64(at: 1)
            ))
        }
        return events
    }

    public func perkAvailableEvents(since: Date? = nil) throws -> [PerkAvailableEvent] {
        let statement = try prepare("""
            SELECT app, kind, currency, quantity, perk_id, expires_at, time_unix_nano
            FROM perk_available_events
            WHERE time_unix_nano >= ?1
            ORDER BY time_unix_nano, rowid
            """)
        try statement.bind(.integer(since?.unixNano ?? Int64.min))
        var events: [PerkAvailableEvent] = []
        while try statement.step() {
            guard let appName = statement.text(at: 0), let app = BarApp(rawValue: appName),
                  let kindName = statement.text(at: 1), let kind = PerkKind(rawValue: kindName) else {
                continue
            }
            events.append(PerkAvailableEvent(
                app: app,
                kind: kind,
                currency: statement.text(at: 2).flatMap { $0.isEmpty ? nil : $0 },
                quantity: statement.optionalDouble(at: 3),
                perkID: statement.text(at: 4).flatMap { $0.isEmpty ? nil : $0 },
                expiresAt: statement.optionalInt64(at: 5),
                timeUnixNano: statement.int64(at: 6)
            ))
        }
        return events
    }
}
