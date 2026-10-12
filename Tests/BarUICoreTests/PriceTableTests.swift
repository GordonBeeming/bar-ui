import Foundation
import Testing
@testable import BarUICore

@Suite("Price table from the LiteLLM list")
struct PriceTableTests {
    private static let list = """
    {
      "sample_spec": { "code": "documentation, not a model" },
      "claude-opus-4-8": {
        "litellm_provider": "anthropic",
        "input_cost_per_token": 5E-6,
        "output_cost_per_token": 0.000025,
        "cache_read_input_token_cost": 5E-7,
        "cache_creation_input_token_cost": 0.00000625,
        "cache_creation_input_token_cost_above_1hr": 0.00001
      },
      "gpt-5": {
        "input_cost_per_token": 0.00000125,
        "output_cost_per_token": 0.00001,
        "cache_read_input_token_cost": 1.25E-7
      },
      "text-embedding": { "input_cost_per_token": 1E-7 }
    }
    """

    private static func table() throws -> PriceTable {
        try PriceTable(litellmJSON: Data(list.utf8))
    }

    @Test("Each Token Type reads its own rate, and an unsplit cache write is the 5 minute rate")
    func ratesPerTokenType() throws {
        let price = try #require(try Self.table().price(for: "claude-opus-4-8"))

        #expect(price.usdPerToken(for: .input) == 5E-6)
        #expect(price.usdPerToken(for: .output) == 0.000025)
        #expect(price.usdPerToken(for: .cacheRead) == 5E-7)
        #expect(price.usdPerToken(for: .cacheWrite5m) == 0.00000625)
        #expect(price.usdPerToken(for: .cacheWrite) == 0.00000625)
        #expect(price.usdPerToken(for: .cacheWrite1h) == 0.00001)
    }

    @Test("A rate the list doesn't give is missing, not guessed")
    func missingRateStaysMissing() throws {
        let price = try #require(try Self.table().price(for: "gpt-5"))

        #expect(price.usdPerToken(for: .cacheWrite5m) == nil)
        #expect(price.usdPerToken(for: .cacheWrite1h) == nil)
    }

    @Test("Entries without both an input and an output price are not models")
    func skipsNonModels() throws {
        let table = try Self.table()

        #expect(table.price(for: "sample_spec") == nil)
        #expect(table.price(for: "text-embedding") == nil)
    }

    @Test("A model is found by its ID however the tool cased it, and an unknown ID has no price")
    func lookup() throws {
        let table = try Self.table()

        #expect(table.price(for: "Claude-Opus-4-8") != nil)
        #expect(table.price(for: "unknown") == nil)
    }

    @Test("A document that isn't a price list, or has no prices, is rejected")
    func rejectsBadDocuments() {
        #expect(throws: PriceTable.ParseError.self) { try PriceTable(litellmJSON: Data("[]".utf8)) }
        #expect(throws: PriceTable.ParseError.self) { try PriceTable(litellmJSON: Data("not json".utf8)) }
        #expect(throws: PriceTable.ParseError.self) { try PriceTable(litellmJSON: Data("{\"sample_spec\":{}}".utf8)) }
    }
}
