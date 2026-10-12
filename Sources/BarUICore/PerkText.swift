import Foundation

/// The words Perks are shown with, kept out of the views so they can be tested.
public enum PerkText {
    public static func title(of kind: PerkKind) -> String {
        switch kind {
        case .resetCredit: "Reset Credit"
        case .guestPass: "Guest Pass"
        case .creditGrant: "Credit Grant"
        }
    }

    /// "2 Guest Passes" for counted Perks, "$12.50 Credit Grant" for a Credit
    /// Grant, whose amount is already in major units of its own currency.
    public static func quantity(kind: PerkKind, quantity: Double?, currency: String?, locale: Locale = .current) -> String {
        let title = title(of: kind)
        switch kind {
        case .resetCredit, .guestPass:
            let count = Int((quantity ?? 1).rounded())
            let plural = kind == .guestPass ? "Guest Passes" : "Reset Credits"
            return "\(count) \(count == 1 ? title : plural)"
        case .creditGrant:
            guard let quantity else {
                return "\(title), amount unknown"
            }
            guard let currency, !currency.isEmpty else {
                return "\(quantity.formatted(.number.locale(locale))) \(title)"
            }
            return "\(quantity.formatted(.currency(code: currency).locale(locale))) \(title)"
        }
    }

    /// "Expires 23 Oct 2026", or "No expiry known".
    public static func expiry(_ date: Date?, locale: Locale = .current, timeZone: TimeZone = .current) -> String {
        guard let date else {
            return "No expiry known"
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let style = Date.FormatStyle(locale: locale, calendar: calendar, timeZone: timeZone)
            .day().month(.abbreviated).year()
        return "Expires \(date.formatted(style))"
    }

    /// "1 Reset Credit \u{00B7} Expires 23 Oct 2026".
    public static func itemLine(
        kind: PerkKind,
        currency: String?,
        item: AvailablePerkItem,
        locale: Locale = .current,
        timeZone: TimeZone = .current
    ) -> String {
        let quantity = quantity(kind: kind, quantity: item.quantity, currency: currency, locale: locale)
        return "\(quantity) \u{00B7} \(expiry(item.expiresAt, locale: locale, timeZone: timeZone))"
    }

    public static func label(for reason: PerkGoneReason) -> String {
        switch reason {
        case .used: "Used"
        case .expired: "Expired"
        case .unknown: "Reason unknown"
        }
    }
}
