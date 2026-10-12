import AppKit
import BarUICore
import Charts
import SwiftUI

/// The panel that opens from the menu bar icon. It follows the Mac's
/// appearance because nothing here sets a colour scheme.
struct MenuBarPreviewView: View {
    /// Nil when the Archive couldn't be opened; `archiveFailure` says why.
    let preview: MenuBarPreview?
    let monitor: BarAppMonitor
    let archiveFailure: String?

    /// Bar Apps sample every few minutes at most, so importing more often than
    /// this would mostly find nothing new.
    private static let refreshInterval: Duration = .seconds(15)

    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let preview {
                // Countdowns move on their own; samples only arrive every few
                // minutes, so a half-minute tick keeps them honest.
                TimelineView(.periodic(from: .now, by: 30)) { context in
                    PreviewContent(preview: preview, now: context.date)
                }
            } else {
                Label(archiveFailure ?? "The Archive couldn't be opened", systemImage: "externaldrive.badge.exclamationmark")
                    .font(.callout)
                    .foregroundStyle(.red)
            }
            Divider()
            footer
        }
        .padding(16)
        .frame(width: 360)
        .task {
            await keepFresh()
        }
    }

    private var footer: some View {
        HStack {
            Button("Open Bar UI") {
                openWindow(id: MainWindow.id)
                // The panel belongs to an accessory-style scene, so the app
                // isn't frontmost until it's asked to be.
                NSApp.activate()
            }
            .keyboardShortcut(.defaultAction)
            Spacer()
            SettingsLink {
                Image(systemName: "gearshape")
            }
            .help("Settings")
            .accessibilityLabel("Settings")
        }
    }

    private func keepFresh() async {
        guard let preview else {
            return
        }
        while !Task.isCancelled {
            monitor.refresh()
            await preview.refresh(statuses: monitor.statuses, now: .now)
            do {
                try await Task.sleep(for: Self.refreshInterval)
            } catch {
                // Cancelled when the panel closed; stop refreshing for it.
                return
            }
        }
    }
}

private struct PreviewContent: View {
    let preview: MenuBarPreview
    let now: Date

    @Environment(PricingCatalog.self) private var pricing
    @AppStorage(CurrencySetting.key) private var currencyCode = Currency.default.rawValue

    var body: some View {
        let usage = preview.tokenUsage(now: now)
        let pace = preview.pace(now: now)
        VStack(alignment: .leading, spacing: 14) {
            if let problem = preview.problem {
                Label(problem, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            tokens(usage: usage, pace: pace)
            Divider()
            limits
        }
    }

    private func tokens(usage: TokenUsage, pace: TokenPace) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Last 24 hours")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(TokenFormat.compact(usage.total))
                        .font(.system(size: 26, weight: .bold))
                        .monospacedDigit()
                    Text("\(TokenFormat.compact(pace.perHourNow))/h now · \(TokenFormat.compact(Int64(pace.perHourAverage.rounded())))/h avg")
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(cost(for: usage)?.value ?? "–")
                        .font(.title3.weight(.semibold))
                        .monospacedDigit()
                    Text("API Cost")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .help(cost(for: usage)?.rateNote ?? "Loading prices")
            }
            HourlyChart(usage: usage)
        }
        .accessibilityElement(children: .contain)
    }

    private func cost(for usage: TokenUsage) -> ApiCostSummary? {
        pricing.prices.map { prices in
            ApiCostSummary(
                cost: usage.apiCost(prices: prices),
                currency: Currency(storedCode: currencyCode),
                rates: pricing.rates
            )
        }
    }

    @ViewBuilder
    private var limits: some View {
        if preview.rows.isEmpty {
            Text("No Limits yet. They show up once a Bar App is tracking.")
                .font(.callout)
                .foregroundStyle(.secondary)
        } else {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(BarApp.allCases, id: \.self) { app in
                    let rows = preview.rows.filter { $0.app == app }
                    if !rows.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(app.brandColor)
                                    .frame(width: 8, height: 8)
                                    .accessibilityHidden(true)
                                Text(app.displayName)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                            }
                            ForEach(rows) { row in
                                LimitRowView(row: row)
                            }
                        }
                    }
                }
            }
        }
    }
}

private struct HourlyChart: View {
    let usage: TokenUsage

    var body: some View {
        if usage.total == 0 {
            Text("No tokens in the last 24 hours")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 60)
        } else {
            Chart {
                ForEach(usage.buckets, id: \.start) { bucket in
                    ForEach(BarApp.allCases, id: \.self) { app in
                        if let tokens = bucket.tokensByApp[app], tokens > 0 {
                            BarMark(
                                x: .value("Time", bucket.start, unit: .hour),
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
            .chartLegend(.hidden)
            .chartYAxis(.hidden)
            .frame(height: 60)
            .accessibilityLabel("Tokens per hour over the last 24 hours, stacked by Bar App")
        }
    }
}

private struct LimitRowView: View {
    let row: MenuBarLimitRow

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(row.windowName)
                    .font(.callout)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 8)
                Text("\(row.percentUsed)%")
                    .font(.callout.weight(.semibold))
                    .monospacedDigit()
            }
            Gauge(value: min(max(row.utilization, 0), 100), in: 0...100) {
                Text("\(row.appName) \(row.windowName) used")
            }
            .gaugeStyle(.linearCapacity)
            .tint(row.severity.meterColor(for: row.app))
            .labelsHidden()
            HStack {
                Text(row.burnRateText)
                    .font(.caption)
                    .monospacedDigit()
                    .fontWeight(row.isBurnRateHighlighted ? .semibold : .regular)
                    .foregroundStyle(row.isBurnRateHighlighted ? LimitCard.Severity.nearLimit.labelColor : .secondary)
                Spacer(minLength: 8)
                Text(row.resetText)
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            if let projection = row.projectionText {
                Text(projection)
                    .font(.caption)
                    .foregroundStyle(LimitCard.Severity.nearLimit.labelColor)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
