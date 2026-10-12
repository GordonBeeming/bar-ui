/// One Bar App's "Tokens by model" table for a range: a row per model, a
/// column per Token Type the Bar App reported, and a totals row.
public struct ModelTokensTable: Sendable, Equatable {
    public struct Row: Sendable, Equatable {
        /// The model ID, or "Total" on the totals row.
        public let model: String
        /// Includes Reasoning, which is part of output and so not in `total`.
        public let tokens: [TokenType: Int64]
        public let total: Int64
        /// Nil until prices have loaded.
        public let cost: ApiCost?

        /// True only when prices are loaded and this model has none.
        public var hasNoPricing: Bool {
            cost?.unpricedModels.contains(model) ?? false
        }
    }

    /// Only the Token Types with usage, in `TokenType.allCases` order.
    public let columns: [TokenType]
    /// Busiest model first.
    public let rows: [Row]
    public let totals: Row

    public var isEmpty: Bool { rows.isEmpty }

    public init(usage: TokenUsage, app: BarApp, prices: PriceTable?) {
        let byModel = usage.tokens(of: app)

        func row(_ name: String, _ tokens: [TokenType: Int64], costed: [String: [TokenType: Int64]]) -> Row {
            Row(
                model: name,
                tokens: tokens,
                total: Self.total(tokens),
                cost: prices.map { ApiCost(tokensByModel: costed, prices: $0) }
            )
        }

        rows = byModel
            .map { model, tokens in row(model, tokens, costed: [model: Self.withoutReasoning(tokens)]) }
            .sorted { ($0.total, $1.model) > ($1.total, $0.model) }

        var summed: [TokenType: Int64] = [:]
        for tokens in byModel.values {
            for (type, count) in tokens {
                summed[type, default: 0] += count
            }
        }
        totals = row("Total", summed, costed: byModel.mapValues(Self.withoutReasoning))
        columns = TokenType.allCases.filter { (summed[$0] ?? 0) > 0 }
    }

    private static func total(_ tokens: [TokenType: Int64]) -> Int64 {
        tokens.filter { $0.key != .reasoning }.values.reduce(0, +)
    }

    private static func withoutReasoning(_ tokens: [TokenType: Int64]) -> [TokenType: Int64] {
        tokens.filter { $0.key != .reasoning }
    }
}
