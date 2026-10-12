import Foundation

extension Archive {
    /// Each series' latest reading, with one item per point in it.
    public func availablePerks() throws -> [AvailablePerk] {
        let statement = try prepare("""
            SELECT p.app, p.kind, p.currency, p.value, p.expires_at, p.time_unix_nano, p.perk_id
            FROM perk_points p
            WHERE p.value > 0 AND p.time_unix_nano = (
                SELECT MAX(m.time_unix_nano) FROM perk_points m
                WHERE m.app = p.app AND m.kind = p.kind AND m.currency = p.currency)
            """)
        struct SeriesKey: Hashable {
            let app: BarApp
            let kind: PerkKind
            let currency: String?
        }
        var items: [SeriesKey: [AvailablePerkItem]] = [:]
        var sampledAt: [SeriesKey: Date] = [:]
        while try statement.step() {
            guard let appName = statement.text(at: 0), let app = BarApp(rawValue: appName),
                  let kindName = statement.text(at: 1), let kind = PerkKind(rawValue: kindName) else {
                continue
            }
            let key = SeriesKey(app: app, kind: kind, currency: statement.text(at: 2).flatMap { $0.isEmpty ? nil : $0 })
            items[key, default: []].append(AvailablePerkItem(
                quantity: statement.double(at: 3),
                perkID: statement.text(at: 6).flatMap { $0.isEmpty ? nil : $0 },
                expiresAt: statement.optionalInt64(at: 4).map { Date(timeIntervalSince1970: TimeInterval($0)) }
            ))
            sampledAt[key] = Date(unixNano: statement.int64(at: 5))
        }
        let perks = items.compactMap { key, points in
            sampledAt[key].map {
                AvailablePerk(app: key.app, kind: key.kind, currency: key.currency, items: AvailablePerk.ordered(points), sampledAt: $0)
            }
        }
        return perks.sorted { ($0.app.rawValue, $0.kind.sortOrder, $0.currency ?? "") < ($1.app.rawValue, $1.kind.sortOrder, $1.currency ?? "") }
    }

    /// Every gone Perk, newest first, each with its reason settled.
    public func gonePerks() throws -> [GonePerk] {
        let statement = try prepare("""
            SELECT app, kind, currency, quantity, perk_id, expires_at, reason, time_unix_nano
            FROM perk_gone_events
            ORDER BY time_unix_nano DESC, rowid DESC
            """)
        var perks: [GonePerk] = []
        while try statement.step() {
            guard let appName = statement.text(at: 0), let app = BarApp(rawValue: appName),
                  let kindName = statement.text(at: 1), let kind = PerkKind(rawValue: kindName) else {
                continue
            }
            let goneAt = Date(unixNano: statement.int64(at: 7))
            let expiresAt = statement.optionalInt64(at: 5).map { Date(timeIntervalSince1970: TimeInterval($0)) }
            perks.append(GonePerk(
                app: app,
                kind: kind,
                currency: statement.text(at: 2).flatMap { $0.isEmpty ? nil : $0 },
                quantity: statement.optionalDouble(at: 3),
                perkID: statement.text(at: 4).flatMap { $0.isEmpty ? nil : $0 },
                expiresAt: expiresAt,
                goneAt: goneAt,
                // No event records a redemption yet, so nothing can turn an
                // unexplained disappearance without an expiry into "used".
                reason: PerkGoneReason.resolve(
                    reported: statement.text(at: 6).flatMap(PerkGoneReason.init(rawValue:)),
                    goneAt: goneAt,
                    expiresAt: expiresAt,
                    redemptionOnRecord: false
                )
            ))
        }
        return perks
    }
}
