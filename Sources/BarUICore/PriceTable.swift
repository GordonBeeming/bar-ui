import Foundation

/// What one model costs per token at the vendor's public API prices, in USD.
/// Only input and output are required; a cache rate the price list doesn't
/// give stays nil so the tokens it would have priced are reported as
/// excluded instead of being priced by a guess.
public struct ModelPrice: Sendable, Equatable {
    public let input: Double
    public let output: Double
    public let cacheRead: Double?
    public let cacheWrite5m: Double?
    public let cacheWrite1h: Double?

    public init(input: Double, output: Double, cacheRead: Double? = nil, cacheWrite5m: Double? = nil, cacheWrite1h: Double? = nil) {
        self.input = input
        self.output = output
        self.cacheRead = cacheRead
        self.cacheWrite5m = cacheWrite5m
        self.cacheWrite1h = cacheWrite1h
    }

    /// Nil for Reasoning, which output already pays for, and for any rate the
    /// price list doesn't carry.
    public func usdPerToken(for type: TokenType) -> Double? {
        switch type {
        case .input: input
        case .output: output
        case .cacheRead: cacheRead
        // Claude's unsplit cache write defaults to a 5 minute lifetime (see
        // the Telemetry Spec), so it is billed at that rate.
        case .cacheWrite5m, .cacheWrite: cacheWrite5m
        case .cacheWrite1h: cacheWrite1h
        case .reasoning: nil
        }
    }
}

/// Model prices keyed by the model ID a Bar App reports.
public struct PriceTable: Sendable, Equatable {
    public enum ParseError: Error, Equatable, LocalizedError {
        case notAPriceList
        case noPrices

        public var errorDescription: String? {
            switch self {
            case .notAPriceList: "The price list isn't a JSON object."
            case .noPrices: "The price list has no model prices."
            }
        }
    }

    private let prices: [String: ModelPrice]

    public var modelCount: Int { prices.count }

    public init(prices: [String: ModelPrice]) {
        self.prices = Dictionary(prices.map { ($0.key.lowercased(), $0.value) }, uniquingKeysWith: { first, _ in first })
    }

    /// Reads LiteLLM's `model_prices_and_context_window.json`. Entries that
    /// aren't priced per input and output token (its `sample_spec`, image or
    /// embedding models) are skipped rather than failing the whole list.
    public init(litellmJSON data: Data) throws {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            throw ParseError.notAPriceList
        }
        var prices: [String: ModelPrice] = [:]
        for (model, value) in root {
            guard let entry = value as? [String: Any],
                  let input = (entry["input_cost_per_token"] as? NSNumber)?.doubleValue,
                  let output = (entry["output_cost_per_token"] as? NSNumber)?.doubleValue else {
                continue
            }
            prices[model] = ModelPrice(
                input: input,
                output: output,
                cacheRead: (entry["cache_read_input_token_cost"] as? NSNumber)?.doubleValue,
                cacheWrite5m: (entry["cache_creation_input_token_cost"] as? NSNumber)?.doubleValue,
                cacheWrite1h: (entry["cache_creation_input_token_cost_above_1hr"] as? NSNumber)?.doubleValue
            )
        }
        guard !prices.isEmpty else {
            throw ParseError.noPrices
        }
        self.init(prices: prices)
    }

    public func price(for model: String) -> ModelPrice? {
        prices[model.lowercased()]
    }
}
