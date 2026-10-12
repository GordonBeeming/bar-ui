import AppKit
import BarUICore
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
                .font(.caption.weight(.semibold))
                .textCase(.uppercase)
                .tracking(0.4)
                .foregroundStyle(.secondary)
            HStack(alignment: .lastTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(DisplayFormat.tokens(usage.total))
                            .font(.system(size: 28, weight: .bold))
                            .monospacedDigit()
                        Text("tokens")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    Text("\(DisplayFormat.tokens(pace.perHourNow))/h now · \(DisplayFormat.tokens(Int64(pace.perHourAverage.rounded())))/h avg")
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(cost(for: usage)?.value ?? "–")
                        .font(.title3.weight(.bold))
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
            VStack(alignment: .leading, spacing: 10) {
                ForEach(BarApp.allCases, id: \.self) { app in
                    let rows = preview.rows.filter { $0.app == app }
                    if !rows.isEmpty {
                        BarAppLimitsCard(app: app, rows: rows)
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
            StackedTokensChart(usage: usage, unit: .hour, compact: true)
                .frame(height: 60)
                .accessibilityLabel("Tokens per hour over the last 24 hours, stacked by Bar App")
        }
    }
}

/// One Bar App's Limits grouped on a card, so the panel reads as one block
/// per Bar App rather than one long list.
private struct BarAppLimitsCard: View {
    let app: BarApp
    let rows: [MenuBarLimitRow]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Circle()
                    .fill(app.brandColor)
                    .frame(width: 8, height: 8)
                    .accessibilityHidden(true)
                Text(app.displayName)
                    .font(.callout.weight(.semibold))
                Spacer()
                Text(rows.count == 1 ? "1 Limit" : "\(rows.count) Limits")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
            ForEach(rows) { row in
                LimitRowView(row: row)
            }
        }
        .padding(12)
        .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct LimitRowView: View {
    let row: MenuBarLimitRow

    private static let paceTint = LimitCard.Severity.runningLow.labelColor

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline) {
                Text(row.windowName)
                    .font(.callout)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 8)
                Text(DisplayFormat.points(row.percentUsed))
                    .font(.system(size: 17, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(row.severity == .normal ? AnyShapeStyle(.primary) : AnyShapeStyle(row.severity.labelColor))
            }
            // A drawn bar rather than Gauge: the linear Gauge styles show
            // their label inside the bar even when labels are hidden.
            Meter(fraction: min(max(row.utilization, 0), 100) / 100, color: row.severity.meterColor(for: row.app))
                .accessibilityLabel("\(row.windowName) used")
                .accessibilityValue(DisplayFormat.points(row.percentUsed))
            HStack {
                Text(row.burnRateText)
                    .font(.caption)
                    .monospacedDigit()
                    .fontWeight(row.isBurnRateHighlighted ? .semibold : .regular)
                    .foregroundStyle(row.isBurnRateHighlighted ? Self.paceTint : .secondary)
                Spacer(minLength: 8)
                Text(row.resetText)
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            // A fast burn is a heads-up about pace, not a fault, so it uses the
            // running-low amber; red stays for a Limit that is nearly used up.
            if let projection = row.projectionText {
                Label(projection, systemImage: "flame.fill")
                    .font(.caption)
                    .foregroundStyle(Self.paceTint)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Self.paceTint.opacity(0.14), in: Capsule())
            }
        }
        .accessibilityElement(children: .combine)
    }
}

private struct Meter: View {
    let fraction: Double
    let color: Color

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary)
                Capsule()
                    .fill(color)
                    .frame(width: max(proxy.size.width * fraction, fraction > 0 ? 6 : 0))
            }
        }
        .frame(height: 6)
    }
}
