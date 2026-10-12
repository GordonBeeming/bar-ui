import Foundation

/// A `bar.perk.gone` event: a Perk disappeared, or its count or amount went down.
public struct PerkGoneEvent: Sendable, Hashable {
    public let app: BarApp
    public let kind: PerkKind
    public let currency: String?
    /// How many went (a count) or how much (major units). Nil only for a
    /// Credit Grant whose amount the Bar App didn't say.
    public let quantity: Double?
    public let perkID: String?
    /// Unix seconds.
    public let expiresAt: Int64?
    /// What the Bar App wrote, when it knew. Never filled in by Bar UI.
    public let reportedReason: PerkGoneReason?
    public let timeUnixNano: Int64

    public init(
        app: BarApp,
        kind: PerkKind,
        currency: String?,
        quantity: Double?,
        perkID: String?,
        expiresAt: Int64?,
        reportedReason: PerkGoneReason?,
        timeUnixNano: Int64
    ) {
        self.app = app
        self.kind = kind
        self.currency = currency
        self.quantity = quantity
        self.perkID = perkID
        self.expiresAt = expiresAt
        self.reportedReason = reportedReason
        self.timeUnixNano = timeUnixNano
    }
}

/// The attributes the Perk gauge and the Perk events share. A nil return means
/// the record breaks the spec; a `Found` with a nil value means the attribute
/// is legitimately absent.
enum PerkAttributes {
    struct Found<Value> {
        let value: Value?
    }

    static func currency(of kind: PerkKind, in attributes: [KeyValue]) -> Found<String>? {
        guard kind == .creditGrant else {
            return Found(value: nil)
        }
        guard let code = attributes.string("perk.currency"), !code.isEmpty else {
            return nil
        }
        return Found(value: code)
    }

    /// Optional when unknown, so a present one that isn't a positive int is a
    /// broken record rather than a missing expiry.
    static func expiresAt(in attributes: [KeyValue]) -> Found<Int64>? {
        guard let attribute = attributes.attribute("perk.expires_at") else {
            return Found(value: nil)
        }
        guard let seconds = attribute.intValue, seconds > 0 else {
            return nil
        }
        return Found(value: seconds)
    }
}
