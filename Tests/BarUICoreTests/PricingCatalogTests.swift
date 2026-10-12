import Foundation
import Testing
@testable import BarUICore

private struct OfflineSource: DocumentSource {
    struct Offline: Error {}
    func data(from url: URL) async throws -> Data { throw Offline() }
}

private struct StaticSource: DocumentSource {
    let responses: [String: String]

    func data(from url: URL) async throws -> Data {
        guard let body = responses[url.host() ?? ""] else {
            throw OfflineSource.Offline()
        }
        return Data(body.utf8)
    }
}

@MainActor
@Suite("Pricing catalog")
struct PricingCatalogTests {
    private nonisolated static let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test("The bundled copies are usable on their own, so the app works offline from first launch")
    func bundledCopies() throws {
        let prices = try PriceTable(litellmJSON: BundledFeeds.prices())
        let rates = try ExchangeRates(frankfurterJSON: BundledFeeds.exchangeRates())

        #expect(prices.price(for: "claude-opus-4-8") != nil)
        #expect(prices.price(for: "gpt-5") != nil)
        #expect(rates.rate(for: .aud) != nil)
    }

    @Test("Offline with no cache, the catalog is loaded from the bundled copies")
    func offline() async throws {
        let catalog = PricingCatalog(source: OfflineSource(), cacheDirectory: nil, now: { Self.now })

        await catalog.refresh()

        #expect(catalog.prices?.price(for: "claude-opus-4-8") != nil)
        #expect(catalog.rates?.rate(for: .aud) != nil)
        #expect(catalog.priceOrigin == .bundled)
        #expect(catalog.rateOrigin == .bundled)
        #expect(catalog.notes.count == 2)
    }

    @Test("Online, fetched prices and rates replace the bundled ones")
    func online() async throws {
        let source = StaticSource(responses: [
            "raw.githubusercontent.com": #"{"m":{"input_cost_per_token":1,"output_cost_per_token":2}}"#,
            "api.frankfurter.dev": #"{"base":"USD","date":"2026-10-10","rates":{"AUD":2}}"#
        ])
        let catalog = PricingCatalog(source: source, cacheDirectory: nil, now: { Self.now })

        await catalog.refresh()

        #expect(catalog.prices?.price(for: "m") != nil)
        #expect(catalog.prices?.price(for: "claude-opus-4-8") == nil)
        #expect(catalog.rates?.rate(for: .aud) == 2)
        #expect(catalog.priceOrigin == .fetched)
        #expect(catalog.notes.isEmpty)
    }
}

@Suite("API Cost summary")
struct ApiCostSummaryTests {
    private static let locale = Locale(identifier: "en_US")
    private static let rates = ExchangeRates(date: Date(timeIntervalSince1970: 1_791_504_000), perUSD: [.aud: 1.5])
    private static let price = ModelPrice(input: 1.0 / 1_000_000, output: 1.0 / 1_000_000)

    private static func summary(_ tokens: [String: [TokenType: Int64]], _ currency: Currency = .aud, rates: ExchangeRates? = rates) -> ApiCostSummary {
        ApiCostSummary(
            cost: ApiCost(tokensByModel: tokens, prices: PriceTable(prices: ["m": price])),
            currency: currency, rates: rates, locale: locale
        )
    }

    @Test("The total is shown in the chosen currency, and the tooltip gives the rate and its date")
    func converted() {
        let summary = Self.summary(["m": [.input: 4_000_000]])

        #expect(summary.value == "A$6.00")
        #expect(summary.rateNote == "US$1 = A$1.50, rates from Oct 9, 2026")
        #expect(summary.exclusionNote == nil)
    }

    @Test("Totals say how many tokens they leave out and which models have no pricing")
    func exclusions() {
        let summary = Self.summary(["m": [.input: 1_000_000], "mystery": [.output: 1_500]])

        #expect(summary.exclusionNote == "Excludes 1,500 tokens. No pricing: mystery")
    }

    @Test("Without a rate for the currency the total stays in US dollars and says so")
    func noRate() {
        let summary = Self.summary(["m": [.input: 4_000_000]], .gbp)

        #expect(summary.value == "US$4.00")
        #expect(summary.rateNote == "No GBP rate available, shown in US dollars")
    }

    @Test("USD needs no conversion note")
    func usd() {
        let summary = Self.summary(["m": [.input: 4_000_000]], .usd, rates: nil)

        #expect(summary.value == "US$4.00")
        #expect(summary.rateNote == "Vendors' public API prices are in US dollars")
    }
}
