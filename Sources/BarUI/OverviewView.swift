import BarUICore
import SwiftUI

struct OverviewView: View {
    /// Nil when the Archive couldn't be opened; `archiveFailure` says why.
    let overview: LimitsOverview?
    let archiveFailure: String?

    @State private var range: TimeRange = .week
    /// Who this view is to the overview, which reads as far back as the
    /// longest range any view shows.
    @State private var viewer = UUID()

    var body: some View {
        Group {
            if let overview {
                // The countdowns move on their own; samples only arrive every
                // few minutes, so a half-minute tick keeps them honest.
                TimelineView(.periodic(from: .now, by: 30)) { context in
                    content(overview: overview, cards: overview.cards(now: context.date), problem: overview.problem, now: context.date)
                }
                .task(id: range) {
                    await overview.show(range, by: viewer)
                }
                .onDisappear {
                    overview.stopShowing(by: viewer)
                }
            } else {
                ContentUnavailableView(
                    "The Archive couldn't be opened",
                    systemImage: "externaldrive.badge.exclamationmark",
                    description: Text(archiveFailure ?? "")
                )
            }
        }
        .navigationTitle("Overview")
    }

    @ViewBuilder
    private func content(overview: LimitsOverview, cards: [LimitCard], problem: String?, now: Date) -> some View {
        switch overview.layout {
        case .nothingArchived:
            ContentUnavailableView {
                Label("No Telemetry yet", systemImage: "chart.bar.xaxis")
            } description: {
                Text("Usage from your Bar Apps shows up here once they record Telemetry.")
            } actions: {
                if let problem {
                    ProblemLabel(problem: problem)
                }
            }
        case .sections:
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if let problem {
                        ProblemLabel(problem: problem)
                    }
                    LimitsStrip(cards: cards)
                    TokensSection(overview: overview, now: now, range: $range)
                    ResetsAndPerksSection(
                        events: overview.events(range: range, now: now),
                        range: range,
                        now: now,
                        tokensDomain: overview.tokenUsage(range: range, now: now).timeDomain(component: range.bucketComponent)
                    )
                }
                .padding(.horizontal, 32)
                .padding(.vertical, 16)
            }
        }
    }
}

struct ProblemLabel: View {
    let problem: String

    var body: some View {
        Label(problem, systemImage: "exclamationmark.triangle")
            .font(.callout)
            .foregroundStyle(.red)
            .textSelection(.enabled)
    }
}

private struct LimitsStrip: View {
    let cards: [LimitCard]

    private let columns = [GridItem(.adaptive(minimum: 220), spacing: 16, alignment: .top)]

    var body: some View {
        if cards.isEmpty {
            ContentUnavailableView(
                "No Limits being Tracked",
                systemImage: "gauge.with.dots.needle.0percent",
                description: Text("Current Limits show here while a Bar App is Tracking. Each Bar App's page keeps its Limit history.")
            )
            .frame(height: 160)
        } else {
            LazyVGrid(columns: columns, alignment: .leading, spacing: 16) {
                ForEach(cards) { card in
                    LimitCardView(card: card)
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Current limits")
        }
    }
}

private struct LimitCardView: View {
    let card: LimitCard

    private static let resetFormat = Date.FormatStyle(date: .abbreviated, time: .shortened)

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Circle()
                    .fill(card.app.brandColor)
                    .frame(width: 8, height: 8)
                    .accessibilityHidden(true)
                Text(card.appName)
                    .fontWeight(.semibold)
                Text("· \(card.windowName)")
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(DisplayFormat.points(card.percentUsed))
                    .font(.system(size: 34, weight: .bold))
                    .monospacedDigit()
                Text("used")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                if let label = card.severity.label {
                    Text(label)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(card.severity.labelColor)
                }
            }

            LimitMeter(fraction: card.utilization / 100, color: card.severity.meterColor(for: card.app), paceMark: card.windowElapsed)
                .accessibilityLabel("\(card.appName) \(card.windowName) used")
                .accessibilityValue(DisplayFormat.points(card.percentUsed))

            // The cards sit side by side, so a Limit with no pace reading yet
            // keeps the line's space: every card stays the same height and the
            // reset lines stay level.
            if let pace = card.paceText, let gap = card.paceGap {
                PaceLabel(text: pace, gap: gap)
            } else {
                PaceLabel(text: "0% headroom", gap: 0)
                    .hidden()
                    .accessibilityHidden(true)
            }
            Text(card.resetDetailText)
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(.secondary)
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
