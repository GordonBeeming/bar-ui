import BarUICore
import SwiftUI

/// A Bar App's tokens by model for a chosen range, with what each would have
/// cost at API prices.
struct ModelTokensSection: View {
    let app: BarApp
    let overview: LimitsOverview

    @Environment(PricingCatalog.self) private var pricing
    @AppStorage(CurrencySetting.key) private var currencyCode = Currency.default.rawValue
    @State private var range: TimeRange = .week
    /// Who this view is to the overview, which reads as far back as the
    /// longest range any view shows.
    @State private var viewer = UUID()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Tokens by model")
                    .font(.headline)
                Spacer()
                Picker("Range", selection: $range) {
                    ForEach(TimeRange.allCases) { range in
                        Text(range.label).tag(range)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            }

            // Samples arrive every few minutes, so the range only needs to
            // slide that often.
            TimelineView(.everyMinute) { context in
                let usage = overview.tokenUsage(range: range, now: context.date)
                let table = ModelTokensTable(usage: usage, app: app, prices: pricing.prices)
                if table.isEmpty {
                    ContentUnavailableView(
                        "No tokens in this range",
                        systemImage: "tablecells",
                        description: Text("Tokens \(app.displayName) counts show up here.")
                    )
                    .frame(height: 160)
                } else {
                    ModelTokensGrid(
                        table: table,
                        currency: Currency(storedCode: currencyCode),
                        rates: pricing.rates,
                        pricesLoaded: pricing.prices != nil
                    )
                }
            }
        }
        .task(id: range) {
            await overview.show(range, by: viewer)
        }
        .onDisappear {
            overview.stopShowing(by: viewer)
        }
    }
}

private struct ModelTokensGrid: View {
    let table: ModelTokensTable
    let currency: Currency
    let rates: ExchangeRates?
    let pricesLoaded: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Grid(alignment: .trailing, horizontalSpacing: 20, verticalSpacing: 8) {
                GridRow {
                    Text("Model").gridColumnAlignment(.leading)
                    ForEach(table.columns, id: \.self) { type in
                        Text(Self.label(for: type))
                    }
                    Text("Total")
                    Text("API Cost")
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                Divider()

                ForEach(table.rows, id: \.model) { row in
                    line(row)
                }

                Divider()

                line(table.totals)
                    .fontWeight(.semibold)
            }
            .monospacedDigit()

            if let note = totalCostSummary?.exclusionNote {
                Label(note, systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(.separator, lineWidth: 1)
        }
    }

    private var totalCostSummary: ApiCostSummary? {
        summary(of: table.totals)
    }

    private func summary(of row: ModelTokensTable.Row) -> ApiCostSummary? {
        row.cost.map { ApiCostSummary(cost: $0, currency: currency, rates: rates) }
    }

    private func line(_ row: ModelTokensTable.Row) -> some View {
        GridRow {
            Text(row.model)
                .gridColumnAlignment(.leading)
                .textSelection(.enabled)
            ForEach(table.columns, id: \.self) { type in
                if let count = row.tokens[type] {
                    Text(count.formatted())
                } else {
                    Text("–").foregroundStyle(.secondary)
                }
            }
            Text(row.total.formatted())
            costCell(row)
        }
    }

    @ViewBuilder
    private func costCell(_ row: ModelTokensTable.Row) -> some View {
        if row.hasNoPricing {
            Text("No pricing").foregroundStyle(.secondary)
        } else if let summary = summary(of: row) {
            Text(summary.value).help(summary.rateNote)
        } else {
            Text(pricesLoaded ? "–" : "Loading prices").foregroundStyle(.secondary)
        }
    }

    private static func label(for type: TokenType) -> String {
        switch type {
        case .input: "Input"
        case .cacheRead: "Cache read"
        case .cacheWrite5m: "Cache write 5m"
        case .cacheWrite1h: "Cache write 1h"
        case .cacheWrite: "Cache write"
        case .output: "Output"
        case .reasoning: "Reasoning"
        }
    }
}
