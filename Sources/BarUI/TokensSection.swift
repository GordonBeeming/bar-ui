import BarUICore
import SwiftUI

/// Tokens over time, stacked by kind, with the tiles that sum the same
/// range. One range control drives both so they can't disagree. The range
/// belongs to the Overview, which also uses it for the Events list.
struct TokensSection: View {
    let overview: LimitsOverview
    let now: Date

    @Binding var range: TimeRange

    var body: some View {
        let usage = overview.tokenUsage(range: range, now: now)
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Tokens over time")
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

            TokensChart(usage: usage, range: range)

            TokenTiles(usage: usage)
        }
    }
}

private struct TokensChart: View {
    let usage: TokenUsage
    let range: TimeRange

    var body: some View {
        if usage.total == 0 {
            ContentUnavailableView(
                "No tokens in this range",
                systemImage: "chart.bar",
                description: Text("Tokens your Bar Apps count show up here.")
            )
            .frame(height: 220)
        } else {
            StackedTokensChart(usage: usage, unit: range.bucketComponent)
                .frame(height: 220)
                .accessibilityLabel("Tokens over time, stacked by cache reads, input and output")
        }
    }
}

private struct TokenTiles: View {
    let usage: TokenUsage

    private let columns = [GridItem(.adaptive(minimum: 220), spacing: 16, alignment: .top)]

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 16) {
            TokenTile(
                title: "Total tokens",
                value: DisplayFormat.tokens(usage.total),
                detail: BarApp.allCases
                    .compactMap { app in usage.totalByApp[app].map { "\(app.displayName) \(DisplayFormat.tokens($0))" } }
                    .joined(separator: " · ")
            )
            TokenTile(
                title: "Output tokens",
                value: DisplayFormat.tokens(usage.output),
                detail: usage.reasoningShareOfOutput.map { "\(DisplayFormat.share($0)) reasoning" } ?? "No output yet"
            )
            TokenTile(
                title: "Read from cache",
                value: usage.cacheReadShareOfInput.map(DisplayFormat.share) ?? "–",
                detail: usage.cacheReadShareOfInput == nil
                    ? "No input yet"
                    : "\(DisplayFormat.tokens(usage.cacheRead)) of \(DisplayFormat.tokens(usage.input)) input"
            )
        }
    }
}

private struct TokenTile: View {
    let title: String
    let value: String
    let detail: String

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
    }
}
