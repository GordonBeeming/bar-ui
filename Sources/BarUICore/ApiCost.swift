/// What a set of tokens would have cost at the vendors' public API prices, in
/// USD. A what-if figure, not spend. Tokens that can't be priced are counted
/// as excluded so a total never quietly understates the usage behind it.
public struct ApiCost: Sendable, Equatable {
    public struct ModelCost: Sendable, Equatable {
        /// Nil when the model has no price at all ("No pricing").
        public let usd: Double?
        public let excludedTokens: Int64
    }

    public let byModel: [String: ModelCost]

    public var totalUSD: Double {
        byModel.values.reduce(0) { $0 + ($1.usd ?? 0) }
    }

    public var excludedTokens: Int64 {
        byModel.values.reduce(0) { $0 + $1.excludedTokens }
    }

    /// Models with usage but no price, in name order.
    public var unpricedModels: [String] {
        byModel.filter { $0.value.usd == nil }.keys.sorted()
    }

    public init(tokensByModel: [String: [TokenType: Int64]], prices: PriceTable) {
        var byModel: [String: ModelCost] = [:]
        for (model, tokens) in tokensByModel {
            guard let price = prices.price(for: model) else {
                byModel[model] = ModelCost(usd: nil, excludedTokens: tokens.values.reduce(0, +))
                continue
            }
            var usd = 0.0
            var excluded: Int64 = 0
            for (type, count) in tokens {
                if let rate = price.usdPerToken(for: type) {
                    usd += Double(count) * rate
                } else {
                    excluded += count
                }
            }
            byModel[model] = ModelCost(usd: usd, excludedTokens: excluded)
        }
        self.byModel = byModel
    }
}

extension TokenUsage {
    public func apiCost(prices: PriceTable) -> ApiCost {
        ApiCost(tokensByModel: tokensByModel, prices: prices)
    }
}
