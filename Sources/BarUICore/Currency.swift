import Foundation

/// A currency API Cost can be shown in. Vendors price in USD; the others are
/// converted at a published rate.
public enum Currency: String, CaseIterable, Identifiable, Sendable {
    case aud = "AUD"
    case usd = "USD"
    case eur = "EUR"
    case gbp = "GBP"
    case nzd = "NZD"
    case cad = "CAD"

    public static let `default`: Currency = .aud

    public var id: String { rawValue }

    /// A stored preference can hold a code from a build that supported more
    /// currencies, or nothing yet; both mean the default.
    public init(storedCode: String?) {
        self = storedCode.flatMap(Currency.init(rawValue:)) ?? .default
    }

    public var name: String {
        switch self {
        case .aud: "Australian dollar"
        case .usd: "US dollar"
        case .eur: "Euro"
        case .gbp: "British pound"
        case .nzd: "New Zealand dollar"
        case .cad: "Canadian dollar"
        }
    }

    /// Dollar currencies carry a country prefix so A$ is never read as US$.
    public var prefix: String {
        switch self {
        case .aud: "A$"
        case .usd: "US$"
        case .eur: "€"
        case .gbp: "£"
        case .nzd: "NZ$"
        case .cad: "CA$"
        }
    }

    public func format(_ amount: Double, locale: Locale = .current) -> String {
        prefix + amount.formatted(.number.precision(.fractionLength(2)).locale(locale))
    }
}

/// How many units of each currency one US dollar buys, on one date.
public struct ExchangeRates: Sendable, Equatable {
    public enum ParseError: Error, Equatable, LocalizedError {
        case notUSDRates
        case noRates
        case badDate

        public var errorDescription: String? {
            switch self {
            case .notUSDRates: "The exchange rates aren't quoted against USD."
            case .noRates: "The exchange rates have no usable rates."
            case .badDate: "The exchange rates have no valid date."
            }
        }
    }

    /// The day the rates were published for.
    public let date: Date
    private let perUSD: [Currency: Double]

    public init(date: Date, perUSD: [Currency: Double]) {
        self.date = date
        self.perUSD = perUSD
    }

    /// Reads Frankfurter's `/latest?base=USD` response.
    public init(frankfurterJSON data: Data) throws {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              root["base"] as? String == "USD",
              let rates = root["rates"] as? [String: Any] else {
            throw ParseError.notUSDRates
        }
        var perUSD: [Currency: Double] = [:]
        for (code, value) in rates {
            if let currency = Currency(rawValue: code), let rate = (value as? NSNumber)?.doubleValue, rate > 0, rate.isFinite {
                perUSD[currency] = rate
            }
        }
        guard !perUSD.isEmpty else {
            throw ParseError.noRates
        }
        let format = Date.ISO8601FormatStyle(timeZone: .gmt).year().month().day()
        guard let text = root["date"] as? String, let date = try? Date(text, strategy: format) else {
            throw ParseError.badDate
        }
        self.init(date: date, perUSD: perUSD)
    }

    /// Nil when there is no rate for the currency; the caller shows USD or
    /// says so, never an unconverted number labelled as another currency.
    public func convert(usd: Double, to currency: Currency) -> Double? {
        if currency == .usd {
            return usd
        }
        return perUSD[currency].map { usd * $0 }
    }

    public func rate(for currency: Currency) -> Double? {
        currency == .usd ? 1 : perUSD[currency]
    }
}
