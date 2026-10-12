import Foundation

/// The words and figures the API Cost tile shows for one total.
public struct ApiCostSummary: Equatable, Sendable {
    public let value: String
    /// The conversion behind the value, for a tooltip.
    public let rateNote: String
    /// How many tokens the total leaves out and why. Nil when it leaves none.
    public let exclusionNote: String?

    public init(cost: ApiCost, currency: Currency, rates: ExchangeRates?, locale: Locale = .current) {
        let usd = cost.totalUSD
        if currency == .usd {
            value = Currency.usd.format(usd, locale: locale)
            rateNote = "Vendors' public API prices are in US dollars"
        } else if let rates, let converted = rates.convert(usd: usd, to: currency), let rate = rates.rate(for: currency) {
            value = currency.format(converted, locale: locale)
            let rateText = rate.formatted(.number.precision(.fractionLength(2...4)).locale(locale))
            let date = rates.date.formatted(Date.FormatStyle(date: .abbreviated, time: .omitted, locale: locale, timeZone: .gmt))
            rateNote = "\(Currency.usd.prefix)1 = \(currency.prefix)\(rateText), rates from \(date)"
        } else {
            // Showing a USD number under another currency's symbol would be
            // wrong, so fall back to the vendors' own currency and say so.
            value = Currency.usd.format(usd, locale: locale)
            rateNote = "No \(currency.rawValue) rate available, shown in US dollars"
        }

        if cost.excludedTokens > 0 {
            let tokens = cost.excludedTokens.formatted(.number.locale(locale))
            exclusionNote = cost.unpricedModels.isEmpty
                ? "Excludes \(tokens) tokens"
                : "Excludes \(tokens) tokens. No pricing: \(cost.unpricedModels.joined(separator: ", "))"
        } else {
            exclusionNote = nil
        }
    }
}
