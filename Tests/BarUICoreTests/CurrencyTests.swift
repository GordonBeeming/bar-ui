import Foundation
import Testing
@testable import BarUICore

@Suite("Currency and exchange rates")
struct CurrencyTests {
    private static let locale = Locale(identifier: "en_US")
    private static let rates = """
    {"amount":1.0,"base":"USD","date":"2026-10-09","rates":{"AUD":1.4324,"EUR":0.89238}}
    """

    @Test("A$ is the default, and a stored code that isn't a supported currency falls back to it")
    func defaults() {
        #expect(Currency.default == .aud)
        #expect(Currency(storedCode: "EUR") == .eur)
        #expect(Currency(storedCode: "XXX") == .aud)
        #expect(Currency(storedCode: nil) == .aud)
    }

    @Test("Rates convert USD to the currency, and USD needs no rate")
    func conversion() throws {
        let rates = try ExchangeRates(frankfurterJSON: Data(Self.rates.utf8))

        #expect(abs((rates.convert(usd: 10, to: .aud) ?? 0) - 14.324) < 1e-9)
        #expect(rates.convert(usd: 10, to: .usd) == 10)
        #expect(rates.convert(usd: 10, to: .gbp) == nil)
    }

    @Test("The date the rates are for is kept")
    func rateDate() throws {
        let rates = try ExchangeRates(frankfurterJSON: Data(Self.rates.utf8))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt

        #expect(calendar.dateComponents([.year, .month, .day], from: rates.date) == DateComponents(year: 2026, month: 10, day: 9))
    }

    @Test("Rates that are missing, non-positive, or undated are rejected")
    func rejectsBadRates() {
        for json in [
            "[]",
            #"{"base":"USD","date":"2026-10-09","rates":{}}"#,
            #"{"base":"USD","date":"2026-10-09","rates":{"AUD":0}}"#,
            #"{"base":"EUR","date":"2026-10-09","rates":{"AUD":1.5}}"#,
            #"{"base":"USD","date":"yesterday","rates":{"AUD":1.5}}"#
        ] {
            #expect(throws: ExchangeRates.ParseError.self) { try ExchangeRates(frankfurterJSON: Data(json.utf8)) }
        }
    }

    @Test("Amounts carry the currency's prefix, so A$ is never confused with US$")
    func formatting() {
        #expect(Currency.aud.format(1234.5, locale: Self.locale) == "A$1,234.50")
        #expect(Currency.usd.format(0, locale: Self.locale) == "US$0.00")
        #expect(Currency.gbp.format(3, locale: Self.locale) == "£3.00")
    }
}
