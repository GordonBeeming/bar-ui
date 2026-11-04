import Foundation
import Testing
@testable import BarUICore

@Suite("Tokens by model table")
struct ModelTokensTableTests {
    private static func sample(_ type: TokenType, _ model: String, _ count: Int64, app: BarApp = .codexBar) -> TokenSample {
        ModelTokensFixture.sample(type, app: app, model: model, count: count)
    }

    private static func table(_ samples: [TokenSample], app: BarApp = .codexBar) -> ModelTokensTable {
        ModelTokensTable(usage: ModelTokensFixture.usage(samples), app: app)
    }

    @Test("Columns are only the Token Types the Bar App reported, in a fixed order")
    func columns() {
        let table = Self.table([
            Self.sample(.output, "model-a", 1),
            Self.sample(.cacheWrite, "model-a", 1),
            Self.sample(.input, "model-a", 1),
            Self.sample(.cacheRead, "other", 1, app: .claudeBar)
        ])

        #expect(table.columns == [.input, .cacheWrite, .output])
    }

    @Test("Reasoning gets a column but is not added to a row's total")
    func reasoningIsPartOfOutput() {
        let table = Self.table([
            Self.sample(.input, "model-a", 10),
            Self.sample(.output, "model-a", 20),
            Self.sample(.reasoning, "model-a", 15)
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

        let table = ModelTokensTable(usage: usage, app: .codexBar)

        #expect(table.totals.total == usage.totalByApp[.codexBar])
    }

    @Test("Unknown model IDs still contribute all reported usage", arguments: BarApp.allCases)
    func unknownModels(app: BarApp) {
        let table = Self.table([
            Self.sample(.input, "unknown", 10, app: app),
            Self.sample(.cacheRead, "new-model", 20, app: app),
            Self.sample(.cacheWrite, "new-model", 5, app: app),
            Self.sample(.output, "new-model", 30, app: app),
            Self.sample(.reasoning, "new-model", 12, app: app)
        ], app: app)

        #expect(table.rows.map(\.model) == ["new-model", "unknown"])
        #expect(table.totals.total == 65)
        #expect(table.totals.tokens[.reasoning] == 12)
    }

    @Test("A Bar App with no usage in the range has an empty table")
    func empty() {
        let table = Self.table([Self.sample(.input, "model-a", 1, app: .claudeBar)])

        #expect(table.isEmpty)
        #expect(table.columns.isEmpty)
    }
}
