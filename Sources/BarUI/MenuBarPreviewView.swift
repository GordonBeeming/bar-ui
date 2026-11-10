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

    /// Wide enough for two columns of cards, so five Accounts fit a laptop
    /// screen without scrolling.
    static let width: CGFloat = 680

    /// The panel's padding, the four 14 pt gaps between its sections and the two
    /// dividers; everything else that takes height is measured.
    private static let layoutSpacing: Double = 32 + 4 * 14 + 2

    @Environment(\.openWindow) private var openWindow

    /// The visible height of the screen the panel is on, nil until it has a window.
    @State private var screenHeight: CGFloat?
    @State private var summaryHeight: CGFloat = 0
    @State private var footerHeight: CGFloat = 0

    private var cardAreaLimit: CGFloat {
        let visible = screenHeight ?? NSScreen.main?.visibleFrame.height ?? 800
        return CGFloat(MenuBarGrid.cardAreaLimit(
            visibleHeight: Double(visible),
            summaryHeight: Double(summaryHeight),
            footerHeight: Double(footerHeight),
            spacing: Self.layoutSpacing
        ))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let preview {
                // Countdowns move on their own; samples only arrive every few
                // minutes, so a half-minute tick keeps them honest.
                TimelineView(.periodic(from: .now, by: 30)) { context in
                    PreviewContent(preview: preview, now: context.date, cardAreaLimit: cardAreaLimit, summaryHeight: $summaryHeight)
                }
            } else {
                Label(archiveFailure ?? "The Archive couldn't be opened", systemImage: "externaldrive.badge.exclamationmark")
                    .font(.callout)
                    .foregroundStyle(.red)
            }
            Divider()
            footer
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { footerHeight = $0 }
        }
        .padding(16)
        .frame(width: Self.width)
        .background(WindowScreenReader { screenHeight = $0 })
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
            Text(AppVersion.current.short)
                .font(.caption)
                .foregroundStyle(.secondary)
                .help(AppVersion.current.display)
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

    /// The most height the cards may take, worked out by the panel from its
    /// own screen and the heights it measured.
    let cardAreaLimit: CGFloat
    /// Reports the height of what sits above the cards, for that sum.
    @Binding var summaryHeight: CGFloat

    @State private var cardsHeight: CGFloat = 0

    var body: some View {
        let usage = preview.tokenUsage(now: now)
        let pace = preview.pace(now: now)
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 14) {
                if let problem = preview.problem {
                    Label(problem, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                tokens(usage: usage, pace: pace)
            }
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { summaryHeight = $0 }
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
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(DisplayFormat.tokens(usage.total))
                        .font(.system(size: 28, weight: .bold))
                        .monospacedDigit()
                    Text("tokens")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                TokenKindSplit(totals: usage.totalByKind)
                Text("\(DisplayFormat.tokens(pace.perHourNow))/h now · \(DisplayFormat.tokens(Int64(pace.perHourAverage.rounded())))/h avg")
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            HourlyChart(usage: usage, label: preview.seriesLabel(of:))
        }
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var limits: some View {
        if preview.rows.isEmpty {
            Text("No Limits yet. They show up once a Bar App is tracking.")
                .font(.callout)
                .foregroundStyle(.secondary)
        } else {
            let accounts = Set(preview.rows.map(\.account)).sorted()
            let cards = Grid(alignment: .topLeading, horizontalSpacing: 10, verticalSpacing: 10) {
                // A row sizes to its tallest card, so neighbours stay level.
                ForEach(MenuBarGrid.rows(of: accounts, columns: MenuBarGrid.columnCount(forCards: accounts.count)), id: \.first) { pair in
                    GridRow {
                        ForEach(pair, id: \.self) { account in
                            BarAppLimitsCard(
                                app: account.app,
                                title: preview.seriesLabel(of: account),
                                step: preview.colorStep(of: account),
                                rows: preview.rows.filter { $0.account == account }
                            )
                        }
                    }
                }
            }
            // Offered no more than it needs, so a row is as tall as its tallest
            // card and extra panel height doesn't stretch the rows apart.
            .fixedSize(horizontal: false, vertical: true)
            // The panel can't grow past the screen, so cards that don't fit
            // scroll and the footer stays where it is. The scroll view is as
            // tall as its content, up to that limit, because it has no height
            // of its own to offer the panel.
            ScrollView {
                cards
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { cardsHeight = $0 }
            }
            .scrollBounceBehavior(.basedOnSize)
            .frame(height: min(cardsHeight, cardAreaLimit))
        }
    }
}

private struct HourlyChart: View {
    let usage: TokenUsage
    let label: (BarAppAccount) -> String

    var body: some View {
        if usage.total == 0 {
            Text("No tokens in the last 24 hours")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 60)
        } else {
            StackedTokensChart(usage: usage, unit: .hour, compact: true, label: label)
                .frame(height: 60)
                .accessibilityLabel("Tokens per hour over the last 24 hours, stacked by cache reads, input and output")
        }
    }
}

/// One Account's Limits grouped on a card, so the panel reads as one block
/// per Account rather than one long list.
private struct BarAppLimitsCard: View {
    let app: BarApp
    /// The Bar App's name, with the Account after it when the app has several.
    let title: String
    let step: Int
    let rows: [MenuBarLimitRow]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Circle()
                    .fill(app.brandColor(step: step))
                    .frame(width: 8, height: 8)
                    .accessibilityHidden(true)
                Text(title)
                    .font(.callout.weight(.semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .accessibilityElement(children: .combine)
            ForEach(rows) { row in
                LimitRowView(row: row, step: step)
            }
        }
        // Fills the row, so two cards side by side end level.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(12)
        .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct LimitRowView: View {
    let row: MenuBarLimitRow
    let step: Int

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
            LimitMeter(fraction: row.utilization / 100, color: row.severity.meterColor(for: row.app, step: step), paceMark: row.windowElapsed)
                .accessibilityLabel("\(row.windowName) used")
                .accessibilityValue(DisplayFormat.points(row.percentUsed))
            if let pace = row.paceText, let gap = row.paceGap {
                PaceLabel(text: pace, gap: gap, emphasised: row.isBurnRateHighlighted)
            }
            Text(row.resetDetailText)
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(.secondary)
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

/// Tells its owner the visible height of the screen the panel is on, and again
/// whenever the panel moves to another. `NSScreen.main` is the screen with the
/// key window, which isn't necessarily this one.
private struct WindowScreenReader: NSViewRepresentable {
    let onChange: (CGFloat?) -> Void

    func makeNSView(context: Context) -> ScreenView {
        let view = ScreenView()
        view.onChange = onChange
        return view
    }

    func updateNSView(_ view: ScreenView, context: Context) {
        view.onChange = onChange
    }

    final class ScreenView: NSView {
        var onChange: (CGFloat?) -> Void = { _ in }
        // Only touched on the main thread, and read in `deinit`, which Swift treats as nonisolated.
        nonisolated(unsafe) private var observer: (any NSObjectProtocol)?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let observer {
                NotificationCenter.default.removeObserver(observer)
                self.observer = nil
            }
            guard let window else {
                return
            }
            // queue: .main delivers on the main thread, which is what makes assumeIsolated safe here.
            observer = NotificationCenter.default.addObserver(forName: NSWindow.didChangeScreenNotification, object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.report()
                }
            }
            report()
        }

        private func report() {
            // Deferred: this can run while SwiftUI is still laying out.
            let height = window?.screen?.visibleFrame.height
            DispatchQueue.main.async { [weak self] in
                self?.onChange(height)
            }
        }

        deinit {
            if let observer {
                NotificationCenter.default.removeObserver(observer)
            }
        }
    }
}
