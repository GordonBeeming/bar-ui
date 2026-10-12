import Foundation
import Testing
@testable import BarUICore

@Suite("API Cost")
struct ApiCostTests {
    /// USD per million tokens, so the expected figures below are round numbers.
    private static func perMillion(_ dollars: Double) -> Double { dollars / 1_000_000 }

    private static let full = ModelPrice(
        input: perMillion(5),
        output: perMillion(25),
        cacheRead: perMillion(0.5),
        cacheWrite5m: perMillion(6.25),
        cacheWrite1h: perMillion(10)
    )

    private static func cost(_ tokens: [String: [TokenType: Int64]], _ prices: [String: ModelPrice]) -> ApiCost {
        ApiCost(tokensByModel: tokens, prices: PriceTable(prices: prices))
    }

    @Test(
        "Each Token Type is priced at its own rate",
        arguments: [
            (TokenType.input, Int64(1_000_000), 5.0),
            (.output, 1_000_000, 25.0),
            (.cacheRead, 1_000_000, 0.5),
            (.cacheWrite5m, 1_000_000, 6.25),
            (.cacheWrite, 1_000_000, 6.25),
            (.cacheWrite1h, 1_000_000, 10.0),
            (.input, 250_000, 1.25)
        ]
    )
    func pricedPerTokenType(type: TokenType, tokens: Int64, expectedUSD: Double) {
        let cost = Self.cost(["m": [type: tokens]], ["m": Self.full])

        #expect(abs(cost.totalUSD - expectedUSD) < 1e-9)
        #expect(cost.excludedTokens == 0)
    }

    @Test("A model's cost adds its Token Types, and the total adds its models")
    func totals() {
        let cost = Self.cost(
            ["a": [.input: 1_000_000, .output: 1_000_000], "b": [.cacheRead: 2_000_000]],
            ["a": Self.full, "b": Self.full]
        )

        #expect(abs(cost.totalUSD - 31.0) < 1e-9)
        #expect(abs((cost.byModel["a"]?.usd ?? -1) - 30.0) < 1e-9)
        #expect(abs((cost.byModel["b"]?.usd ?? -1) - 1.0) < 1e-9)
    }

    @Test("A model with no price has no cost, is never guessed, and its tokens are excluded from the total")
    func unknownModel() {
        let cost = Self.cost(
            ["m": [.input: 1_000_000], "unknown": [.input: 400, .output: 100]],
            ["m": Self.full]
        )

        #expect(abs(cost.totalUSD - 5.0) < 1e-9)
        #expect(cost.byModel["unknown"]?.usd == nil)
        #expect(cost.byModel["unknown"]?.excludedTokens == 500)
        #expect(cost.excludedTokens == 500)
        #expect(cost.unpricedModels == ["unknown"])
    }

    @Test("A Token Type the model has no rate for is excluded, while the rest of that model is still priced")
    func missingRate() {
        let noCacheWrites = ModelPrice(input: Self.perMillion(5), output: Self.perMillion(25))

        let cost = Self.cost(["m": [.input: 1_000_000, .cacheWrite1h: 300]], ["m": noCacheWrites])

        #expect(abs(cost.totalUSD - 5.0) < 1e-9)
        #expect(cost.byModel["m"]?.excludedTokens == 300)
        #expect(cost.excludedTokens == 300)
        #expect(cost.unpricedModels.isEmpty)
    }

    @Test("No usage costs nothing and excludes nothing")
    func empty() {
        let cost = Self.cost([:], ["m": Self.full])

        #expect(cost.totalUSD == 0)
        #expect(cost.excludedTokens == 0)
    }

    @Test("A usage period is priced from its tokens by model")
    func fromUsage() {
        let now = Date(timeIntervalSince1970: 1_799_971_200)
        let sample = TokenSample(
            app: .codexBar, model: "m", tokenType: .output, startTimeUnixNano: 1,
            timeUnixNano: Int64(now.timeIntervalSince1970) * 1_000_000_000 - 1_000_000_000, count: 2_000_000
        )
        let usage = TokenUsage(samples: [sample], range: .day, now: now)

        let cost = usage.apiCost(prices: PriceTable(prices: ["m": Self.full]))

        #expect(abs(cost.totalUSD - 50.0) < 1e-9)
    }
}
