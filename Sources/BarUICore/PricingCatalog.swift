import Foundation
import Observation

/// The copies of the price list and exchange rates shipped inside the app, for
/// when there is no cache and no network.
public enum BundledFeeds {
    public struct Missing: Error, LocalizedError {
        public let name: String
        public var errorDescription: String? { "The app is missing its bundled \(name)." }
    }

    public static func prices() throws -> Data {
        try data(named: "litellm-prices")
    }

    public static func exchangeRates() throws -> Data {
        try data(named: "exchange-rates")
    }

    private static func data(named name: String) throws -> Data {
        guard let url = Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Resources") else {
            throw Missing(name: name)
        }
        return try Data(contentsOf: url)
    }
}

/// Model prices and exchange rates for API Cost. Each is downloaded at most
/// daily and kept on disk; the bundled copy covers a first launch offline.
@MainActor
@Observable
public final class PricingCatalog {
    private static let priceURL = URL(string: "https://raw.githubusercontent.com/BerriAI/litellm/main/model_prices_and_context_window.json")
    private static let rateURL: URL? = {
        let symbols = Currency.allCases.filter { $0 != .usd }.map(\.rawValue).joined(separator: ",")
        return URL(string: "https://api.frankfurter.dev/v1/latest?base=USD&symbols=\(symbols)")
    }()

    public private(set) var prices: PriceTable?
    public private(set) var rates: ExchangeRates?
    public private(set) var priceOrigin: FeedSnapshot<PriceTable>.Origin?
    public private(set) var rateOrigin: FeedSnapshot<ExchangeRates>.Origin?
    /// Why a feed couldn't be brought up to date or loaded, for Settings to
    /// show. The figures are still shown from the best copy available.
    public private(set) var notes: [String] = []

    private let priceFeed: RefreshingFeed<PriceTable>?
    private let rateFeed: RefreshingFeed<ExchangeRates>?
    private let setupProblem: String?
    private let now: @Sendable () -> Date

    /// `cacheDirectory` is created if needed; nil keeps nothing between launches.
    public init(source: any DocumentSource = URLSessionDocumentSource(), cacheDirectory: URL?, now: @escaping @Sendable () -> Date = { Date() }) {
        self.now = now
        var problem: String?
        var directory = cacheDirectory
        if let cacheDirectory {
            do {
                try FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
            } catch {
                problem = "Can't keep prices for offline use: \(error.localizedDescription)"
                directory = nil
            }
        }

        // The addresses are literals and the bundled copies ship with the
        // app, so a failure here is a broken build; it is surfaced in Settings
        // rather than crashing.
        var priceFeed: RefreshingFeed<PriceTable>?
        var rateFeed: RefreshingFeed<ExchangeRates>?
        do {
            guard let priceURL = Self.priceURL, let rateURL = Self.rateURL else {
                throw BundledFeeds.Missing(name: "feed addresses")
            }
            priceFeed = RefreshingFeed(
                url: priceURL, cacheFile: directory?.appendingPathComponent("litellm-prices.json"),
                bundled: try BundledFeeds.prices(), source: source, parse: { try PriceTable(litellmJSON: $0) }
            )
            rateFeed = RefreshingFeed(
                url: rateURL, cacheFile: directory?.appendingPathComponent("exchange-rates.json"),
                bundled: try BundledFeeds.exchangeRates(), source: source, parse: { try ExchangeRates(frankfurterJSON: $0) }
            )
        } catch {
            problem = error.localizedDescription
        }
        self.priceFeed = priceFeed
        self.rateFeed = rateFeed
        self.setupProblem = problem
    }

    public func refresh() async {
        var notes = setupProblem.map { [$0] } ?? []
        if let priceFeed {
            do {
                let snapshot = try await priceFeed.load(now: now())
                prices = snapshot.value
                priceOrigin = snapshot.origin
                notes += snapshot.refreshFailure.map { ["Model prices: \($0)"] } ?? []
            } catch {
                notes.append("Model prices: \(error.localizedDescription)")
            }
        }
        if let rateFeed {
            do {
                let snapshot = try await rateFeed.load(now: now())
                rates = snapshot.value
                rateOrigin = snapshot.origin
                notes += snapshot.refreshFailure.map { ["Exchange rates: \($0)"] } ?? []
            } catch {
                notes.append("Exchange rates: \(error.localizedDescription)")
            }
        }
        self.notes = notes
    }
}
