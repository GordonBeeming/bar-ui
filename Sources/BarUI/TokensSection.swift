import BarUICore
import Charts
import SwiftUI

/// Tokens over time, stacked by Bar App, with the tiles that sum the same
/// range. One range control drives both so they can't disagree. The range
/// belongs to the Overview, which also uses it for the Events list.
struct TokensSection: View {
    let overview: LimitsOverview
    let now: Date

    @Environment(PricingCatalog.self) private var pricing
    @AppStorage(CurrencySetting.key) private var currencyCode = Currency.default.rawValue
    @Binding var range: TokenRange

    var body: some View {
        let usage = overview.tokenUsage(range: range, now: now)
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Tokens over time")
                    .font(.headline)
                Spacer()
                Picker("Range", selection: $range) {
                    ForEach(TokenRange.allCases) { range in
                        Text(range.label).tag(range)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            }

            TokensChart(usage: usage, range: range)

            TokenTiles(usage: usage, cost: apiCostSummary(for: usage))
        }
    }
}

extension TokensSection {
    /// Nil until prices have loaded, which is only the first moment of a
    /// launch: the bundled copy makes them available even offline.
    fileprivate func apiCostSummary(for usage: TokenUsage) -> ApiCostSummary? {
        pricing.prices.map { prices in
            ApiCostSummary(
                cost: usage.apiCost(prices: prices),
                currency: Currency(storedCode: currencyCode),
                rates: pricing.rates
            )
        }
    }
}

private struct TokensChart: View {
    let usage: TokenUsage
    let range: TokenRange

    private var unit: Calendar.Component { range == .day ? .hour : .day }

    var body: some View {
        if usage.total == 0 {
            ContentUnavailableView(
                "No tokens in this range",
                systemImage: "chart.bar",
                description: Text("Tokens your Bar Apps count show up here.")
            )
            .frame(height: 220)
        } else {
            Chart {
                ForEach(usage.buckets, id: \.start) { bucket in
                    ForEach(BarApp.allCases, id: \.self) { app in
                        if let tokens = bucket.tokensByApp[app], tokens > 0 {
                            BarMark(
                                x: .value("Time", bucket.start, unit: unit),
                                y: .value("Tokens", tokens)
                            )
                            .foregroundStyle(by: .value("Bar App", app.displayName))
                        }
                    }
                }
            }
            .chartForegroundStyleScale(
                domain: BarApp.allCases.map(\.displayName),
                range: BarApp.allCases.map(\.brandColor)
            )
            .chartYAxis {
                AxisMarks { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let tokens = value.as(Int64.self) {
                            Text(TokenFormat.compact(tokens))
                        }
                    }
                }
            }
            .frame(height: 220)
            .accessibilityLabel("Tokens over time, stacked by Bar App")
        }
    }
}

private struct TokenTiles: View {
    let usage: TokenUsage
    let cost: ApiCostSummary?

    private let columns = [GridItem(.adaptive(minimum: 220), spacing: 16, alignment: .top)]

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 16) {
            TokenTile(
                title: "Total tokens",
                value: TokenFormat.compact(usage.total),
                detail: BarApp.allCases
                    .compactMap { app in usage.totalByApp[app].map { "\(app.displayName) \(TokenFormat.compact($0))" } }
                    .joined(separator: " · ")
            )
            TokenTile(
                title: "Output tokens",
                value: TokenFormat.compact(usage.output),
                detail: usage.reasoningShareOfOutput.map { "\(TokenFormat.percent($0)) reasoning" } ?? "No output yet"
            )
            TokenTile(
                title: "Read from cache",
                value: usage.cacheReadShareOfInput.map(TokenFormat.percent) ?? "–",
                detail: usage.cacheReadShareOfInput == nil
                    ? "No input yet"
                    : "\(TokenFormat.compact(usage.cacheRead)) of \(TokenFormat.compact(usage.input)) input"
            )
            TokenTile(
                title: "API Cost",
                value: cost?.value ?? "–",
                detail: cost.map { $0.exclusionNote ?? "What it would cost at API prices" } ?? "Loading prices",
                help: cost?.rateNote
            )
        }
    }
}

private struct TokenTile: View {
    let title: String
    let value: String
    let detail: String
    var help: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 28, weight: .bold))
                .monospacedDigit()
            Text(detail.isEmpty ? " " : detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(.separator, lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
        .help(help ?? "")
    }
}

enum TokenFormat {
    static func compact(_ tokens: Int64) -> String {
        tokens.formatted(.number.notation(.compactName).precision(.fractionLength(0...1)))
    }

    static func percent(_ share: Double) -> String {
        share.formatted(.percent.precision(.fractionLength(0)))
    }
}
