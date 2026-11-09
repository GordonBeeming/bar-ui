import BarUICore
import SwiftUI

/// The Bar Apps' resets and Perk changes in the range the Overview is showing:
/// a chart of how much each Window left unused, then the list, newest first,
/// which also carries Limits running low and Tracking changes.
struct ResetsAndPerksSection: View {
    let overview: LimitsOverview
    let events: [OverviewEvent]
    let range: TimeRange
    let now: Date
    /// The Tokens chart's span, so this chart's days sit under the same days.
    let tokensDomain: ClosedRange<Date>?
    /// The page's own range control; nil on the Overview, where the Tokens
    /// chart's control drives both sections.
    var rangeSelection: Binding<TimeRange>?

    private var shown: [OverviewEvent] {
        OverviewEvent.hidingShortWindowResets(events)
    }

    var body: some View {
        let events = shown
        let chart = ResetsChartData(events: events, range: range, now: now, alignedTo: tokensDomain)
        let series = ResetsChartSeries.all(in: overview)
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Resets & Perks")
                    .font(.headline)
                Spacer()
                if let rangeSelection {
                    Picker("Range", selection: rangeSelection) {
                        ForEach(TimeRange.allCases) { range in
                            Text(range.label).tag(range)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                }
            }

            if !chart.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    ResetsChartLegend(series: series)
                    ResetsChart(data: chart, unit: range.bucketComponent, series: series)
                        .frame(height: 220)
                }
                .padding(18)
                .background(.background, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(.separator, lineWidth: 1)
                }
            }

            if events.isEmpty {
                ContentUnavailableView(
                    "No resets or Perks in this range",
                    systemImage: "chart.bar",
                    description: Text("Resets, Perks and Tracking changes your Bar Apps record show up here.")
                )
                .frame(height: 160)
            } else {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(events) { event in
                        EventRow(event: event, now: now, label: overview.seriesLabel(of: event.account), step: overview.colorStep(of: event.account))
                        if event.id != events.last?.id {
                            Divider()
                        }
                    }
                }
                .padding(.horizontal, 18)
                .background(.background, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(.separator, lineWidth: 1)
                }
            }
        }
    }
}

private struct EventRow: View {
    let event: OverviewEvent
    let now: Date
    let label: String
    let step: Int

    private static let exactFormat = Date.FormatStyle(date: .abbreviated, time: .shortened)

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Circle()
                .fill(event.app.brandColor(step: step))
                .frame(width: 8, height: 8)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(event.title)
                    .fontWeight(.medium)
                Text("\(label) · \(event.detail)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 12)
            Text(event.relativeTime(now: now))
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .help(event.date.formatted(Self.exactFormat))
        }
        .padding(.vertical, 10)
        .accessibilityElement(children: .combine)
    }
}
