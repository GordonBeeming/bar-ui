import Foundation
import Testing
@testable import BarUICore

@Suite("Tokens by model table")
struct ModelTokensTableTests {
    private static func perMillion(_ dollars: Double) -> Double { dollars / 1_000_000 }

    private static let prices = PriceTable(prices: [
        "priced": ModelPrice(input: perMillion(5), output: perMillion(25))
    ])

    private static func sample(_ type: TokenType, _ model: String, _ count: Int64, app: BarApp = .codexBar) -> TokenSample {
        ModelTokensFixture.sample(type, app: app, model: model, count: count)
    }

    private static func table(_ samples: [TokenSample], app: BarApp = .codexBar, prices: PriceTable? = ModelTokensTableTests.prices) -> ModelTokensTable {
        ModelTokensTable(usage: ModelTokensFixture.usage(samples), app: app, prices: prices)
    }

    @Test("Columns are only the Token Types the Bar App reported, in a fixed order")
    func columns() {
        let table = Self.table([
            Self.sample(.output, "priced", 1),
            Self.sample(.cacheWrite, "priced", 1),
            Self.sample(.input, "priced", 1),
            Self.sample(.cacheRead, "other", 1, app: .claudeBar)
        ])

        #expect(table.columns == [.input, .cacheWrite, .output])
    }

    @Test("Reasoning gets a column but is not added to a row's total")
    func reasoningIsPartOfOutput() {
        let table = Self.table([
            Self.sample(.input, "priced", 10),
            Self.sample(.output, "priced", 20),
            Self.sample(.reasoning, "priced", 15)
        ])

        #expect(table.columns == [.input, .output, .reasoning])
        #expect(table.rows.map(\.total) == [30])
        #expect(table.rows.first?.tokens[.reasoning] == 15)
    }

    @Test("Rows are the busiest model first, and the totals row sums them")
    func rowsAndTotals() {
        let table = Self.table([
            Self.sample(.input, "small", 5),
            Self.sample(.input, "big", 100),
            Self.sample(.output, "big", 50),
            Self.sample(.output, "small", 7)
        ])

        #expect(table.rows.map(\.model) == ["big", "small"])
        #expect(table.totals.tokens == [.input: 105, .output: 57])
        #expect(table.totals.total == 162)
    }

    @Test("The totals row matches the Overview's figure for the Bar App")
    func matchesOverview() {
        let usage = ModelTokensFixture.usage([
            Self.sample(.input, "a", 100),
            Self.sample(.cacheRead, "a", 40),
            Self.sample(.output, "b", 30),
            Self.sample(.reasoning, "b", 12),
            Self.sample(.input, "a", 999, app: .claudeBar)
        ])

        let table = ModelTokensTable(usage: usage, app: .codexBar, prices: Self.prices)

        #expect(table.totals.total == usage.totalByApp[.codexBar])
    }

    @Test("A model with no price says so, and is left out of the cost total")
    func noPricing() throws {
        let table = Self.table([
            Self.sample(.input, "priced", 1_000_000),
            Self.sample(.input, "mystery", 2_000_000)
        ])

        let mystery = try #require(table.rows.first { $0.model == "mystery" })
        let priced = try #require(table.rows.first { $0.model == "priced" })
        #expect(mystery.hasNoPricing)
        #expect(priced.hasNoPricing == false)
        let totalCost = try #require(table.totals.cost)
        #expect(abs(totalCost.totalUSD - 5.0) < 1e-9)
        #expect(totalCost.unpricedModels == ["mystery"])
        #expect(totalCost.excludedTokens == 2_000_000)
    }

    @Test("Reasoning is never priced on top of output")
    func reasoningNotPriced() throws {
        let table = Self.table([
            Self.sample(.output, "priced", 1_000_000),
            Self.sample(.reasoning, "priced", 400_000)
        ])

        let cost = try #require(table.totals.cost)
        #expect(abs(cost.totalUSD - 25.0) < 1e-9)
        #expect(cost.excludedTokens == 0)
    }

    @Test("Without prices there is no cost and nothing is called unpriced")
    func pricesNotLoaded() {
        let table = Self.table([Self.sample(.input, "priced", 1)], prices: nil)

        #expect(table.totals.cost == nil)
        #expect(table.rows.allSatisfy { $0.cost == nil && !$0.hasNoPricing })
    }

    @Test("A Bar App with no usage in the range has an empty table")
    func empty() {
        let table = Self.table([Self.sample(.input, "priced", 1, app: .claudeBar)])

        #expect(table.isEmpty)
        #expect(table.columns.isEmpty)
    }
}
