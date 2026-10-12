import Foundation

/// A `bar.limit.appeared` or `bar.limit.disappeared` event.
public struct LimitLifecycleEvent: Sendable, Hashable {
    public enum Kind: String, Sendable, Hashable {
        case appeared
        case disappeared
    }

    public let app: BarApp
    public let limit: LimitDescriptor
    public let kind: Kind
    public let timeUnixNano: Int64

    public init(app: BarApp, limit: LimitDescriptor, kind: Kind, timeUnixNano: Int64) {
        self.app = app
        self.limit = limit
        self.kind = kind
        self.timeUnixNano = timeUnixNano
    }
}

/// A `bar.tracking.started` event: Tracking turned on, or the counters restarted.
public struct TrackingStartedEvent: Sendable, Hashable {
    public let app: BarApp
    public let intervalMinutes: Int
    public let timeUnixNano: Int64

    public init(app: BarApp, intervalMinutes: Int, timeUnixNano: Int64) {
        self.app = app
        self.intervalMinutes = intervalMinutes
        self.timeUnixNano = timeUnixNano
    }
}

/// A `bar.perk.available` event: a Perk appeared, or its count or amount went up.
public struct PerkAvailableEvent: Sendable, Hashable {
    public let app: BarApp
    public let kind: PerkKind
    public let currency: String?
    /// How many appeared, or how much (major units). Nil only for a Credit
    /// Grant whose amount the Bar App didn't say.
    public let quantity: Double?
    public let perkID: String?
    /// Unix seconds.
    public let expiresAt: Int64?
    public let timeUnixNano: Int64

    public init(
        app: BarApp,
        kind: PerkKind,
        currency: String?,
        quantity: Double?,
        perkID: String?,
        expiresAt: Int64?,
        timeUnixNano: Int64
    ) {
        self.app = app
        self.kind = kind
        self.currency = currency
        self.quantity = quantity
        self.perkID = perkID
        self.expiresAt = expiresAt
        self.timeUnixNano = timeUnixNano
    }

    /// The parser validates both Perk events by the same rules, so an available
    /// event is read as a gone one and the reason, which it can't have, dropped.
    init(gone event: PerkGoneEvent) {
        self.init(
            app: event.app,
            kind: event.kind,
            currency: event.currency,
            quantity: event.quantity,
            perkID: event.perkID,
            expiresAt: event.expiresAt,
            timeUnixNano: event.timeUnixNano
        )
    }
}
