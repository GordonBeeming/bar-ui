import Foundation

/// The three kinds of Perk the Telemetry Spec defines. The raw values are the
/// spec's `perk.kind` values, which the Archive also stores.
public enum PerkKind: String, Sendable, Hashable, CaseIterable {
    case resetCredit = "reset_credit"
    case guestPass = "guest_pass"
    case creditGrant = "credit_grant"

    var sortOrder: Int {
        Self.allCases.firstIndex(of: self) ?? Self.allCases.count
    }
}

/// A Perk series as it stands at its latest reading.
public struct AvailablePerk: Sendable, Hashable {
    public let app: BarApp
    public let kind: PerkKind
    /// ISO 4217 code, for Credit Grants only.
    public let currency: String?
    /// A count, or an amount in major units of `currency`.
    public let quantity: Double
    /// The earliest expiry among the Perks counted in `quantity`.
    public let expiresAt: Date?
    public let sampledAt: Date

    public init(app: BarApp, kind: PerkKind, currency: String?, quantity: Double, expiresAt: Date?, sampledAt: Date) {
        self.app = app
        self.kind = kind
        self.currency = currency
        self.quantity = quantity
        self.expiresAt = expiresAt
        self.sampledAt = sampledAt
    }
}

/// A Perk that went, and why.
public struct GonePerk: Sendable, Hashable {
    public let app: BarApp
    public let kind: PerkKind
    public let currency: String?
    /// Nil when a Credit Grant went without saying how much.
    public let quantity: Double?
    public let perkID: String?
    public let expiresAt: Date?
    public let goneAt: Date
    public let reason: PerkGoneReason

    public init(
        app: BarApp,
        kind: PerkKind,
        currency: String?,
        quantity: Double?,
        perkID: String?,
        expiresAt: Date?,
        goneAt: Date,
        reason: PerkGoneReason
    ) {
        self.app = app
        self.kind = kind
        self.currency = currency
        self.quantity = quantity
        self.perkID = perkID
        self.expiresAt = expiresAt
        self.goneAt = goneAt
        self.reason = reason
    }
}

/// Why a Perk went. `unknown` is what Bar UI shows when neither the Bar App
/// nor the Perk's expiry can say.
public enum PerkGoneReason: String, Sendable, Hashable {
    case used
    case expired
    case unknown

    /// The Bar App's own reason wins. Otherwise the expiry decides, and with
    /// no expiry known only a recorded redemption can say it was used.
    public static func resolve(
        reported: PerkGoneReason?,
        goneAt: Date,
        expiresAt: Date?,
        redemptionOnRecord: Bool
    ) -> PerkGoneReason {
        if let reported {
            return reported
        }
        if let expiresAt {
            return goneAt >= expiresAt ? .expired : .used
        }
        return redemptionOnRecord ? .used : .unknown
    }
}

/// One `bar.perk.available` reading for a series: how many Reset Credits or
/// Guest Passes, or how much Credit Grant in major units of `currency`.
public struct PerkSample: Sendable, Hashable {
    public static let metricName = "bar.perk.available"

    public let app: BarApp
    public let kind: PerkKind
    /// Set for Credit Grants only; it is part of the series key.
    public let currency: String?
    public let timeUnixNano: Int64
    public let value: Double
    /// Unix seconds. The earliest expiry among the Perks counted in `value`.
    public let expiresAt: Int64?

    public init(app: BarApp, kind: PerkKind, currency: String?, timeUnixNano: Int64, value: Double, expiresAt: Int64?) {
        self.app = app
        self.kind = kind
        self.currency = currency
        self.timeUnixNano = timeUnixNano
        self.value = value
        self.expiresAt = expiresAt
    }
}

/// Folds the points of one series and instant into a single sample, as the
/// spec says to when a Bar App writes several (two Guest Pass campaigns).
struct PerkAccumulator {
    private struct Key: Hashable {
        let kind: PerkKind
        let currency: String?
        let time: Int64
    }

    private var byKey: [Key: PerkSample] = [:]
    private var order: [Key] = []

    mutating func add(_ sample: PerkSample) {
        let key = Key(kind: sample.kind, currency: sample.currency, time: sample.timeUnixNano)
        guard let existing = byKey[key] else {
            byKey[key] = sample
            order.append(key)
            return
        }
        byKey[key] = PerkSample(
            app: sample.app,
            kind: sample.kind,
            currency: sample.currency,
            timeUnixNano: sample.timeUnixNano,
            value: existing.value + sample.value,
            expiresAt: [existing.expiresAt, sample.expiresAt].compactMap { $0 }.min()
        )
    }

    var samples: [PerkSample] {
        order.compactMap { byKey[$0] }
    }
}
