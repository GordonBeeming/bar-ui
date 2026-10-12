import BarUICore
import Charts
import SwiftUI

/// The Limits section of a Bar App's page: one row per Limit, each with its
/// utilisation over the chosen range and a marker at every reset.
struct LimitHistorySection: View {
    /// Bar Apps sample every few minutes at most, and the Overview imports on
    /// its own schedule; re-reading the Archive at this pace picks both up.
    private static let reloadInterval: Duration = .seconds(15)

    let app: BarApp
    let model: LimitHistoryModel

    @State private var range: TimeRange = .week

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Limits")
                    .font(.title3.weight(.semibold))
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

            if let problem = model.problem {
                Label(problem, systemImage: "exclamationmark.triangle")
                    .font(.callout)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
            }

            if model.rows.isEmpty {
                ContentUnavailableView(
                    "No Limits recorded yet",
                    systemImage: "chart.xyaxis.line",
                    description: Text("\(app.displayName)'s Limits show up here once it has recorded Telemetry.")
                )
            } else {
                ForEach(model.rows) { row in
                    LimitHistoryRowView(row: row, brand: app.brandColor, range: range)
                }
            }
        }
        .task(id: range) {
            while !Task.isCancelled {
                await model.load(app: app, range: range, now: .now)
                do {
                    try await Task.sleep(for: Self.reloadInterval)
                } catch {
                    // Cancelled because the range changed or the page went away.
                    return
                }
            }
        }
    }
}

private struct LimitHistoryRowView: View {
    let row: LimitHistoryRow
    let brand: Color
    let range: TimeRange

    @State private var pointerDate: Date?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(row.name)
                        .fontWeight(.semibold)
                    Text(row.windowText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                stat(
                    row.percentUsedNow.map(DisplayFormat.points) ?? "No samples",
                    caption: row.latestSampleAt.map { "used, as of \($0.formatted(Self.sampleFormat))" } ?? "used"
                )
                stat(row.unusedAtLastReset.map(DisplayFormat.points) ?? "None yet", caption: "unused at last reset")
                stat(row.averageUnusedAtReset.map(DisplayFormat.points) ?? "None yet", caption: "avg unused at reset · \(row.averageLabel)")
            }

            chart
                .frame(height: 140)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(.separator, lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
    }

    private static let hoverFormat = Date.FormatStyle().day().month(.abbreviated).hour().minute()
    private static let sampleFormat = Date.FormatStyle(date: .abbreviated, time: .shortened)

    private func stat(_ value: String, caption: String) -> some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text(value)
                .font(.title3.weight(.semibold))
                .monospacedDigit()
            Text(caption)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.leading, 12)
        .accessibilityElement(children: .combine)
    }

    private var hover: LimitHistoryRow.Hover? {
        pointerDate.flatMap { row.hover(at: $0) }
    }

    private var bridgedDates: Set<Date> {
        Set(row.bridges.flatMap { $0.map(\.date) })
    }

    private var dataExtent: ClosedRange<Date>? {
        guard let first = row.segments.first?.first?.date, let last = row.segments.last?.last?.date else {
            return nil
        }
        return first...last
    }

    /// A series per run, so Charts never joins the end of one run to the start
    /// of the next by itself; the bridges do that, drawn fainter.
    @ChartContentBuilder
    private var runMarks: some ChartContent {
        ForEach(Array(row.segments.enumerated()), id: \.offset) { index, segment in
            ForEach(segment, id: \.date) { (point: LimitHistoryRow.Point) in
                LineMark(
                    x: .value("Time", point.date),
                    y: .value("Used", point.percent),
                    series: .value("Run", "run-\(index)")
                )
                .foregroundStyle(brand)
                // A lone sample needs a dot to be seen, unless a bridge
                // already runs into it.
                if segment.count == 1, !bridgedDates.contains(point.date) {
                    PointMark(x: .value("Time", point.date), y: .value("Used", point.percent))
                        .foregroundStyle(brand)
                }
            }
        }
    }

    @ChartContentBuilder
    private var bridgeMarks: some ChartContent {
        ForEach(Array(row.bridges.enumerated()), id: \.offset) { index, bridge in
            ForEach(bridge, id: \.date) { (point: LimitHistoryRow.Point) in
                LineMark(
                    x: .value("Time", point.date),
                    y: .value("Used", point.percent),
                    series: .value("Run", "bridge-\(index)")
                )
                .foregroundStyle(brand.opacity(0.45))
                .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
            }
        }
    }

    private var chart: some View {
        Chart {
            runMarks
            bridgeMarks
            ForEach(row.resetMarkers, id: \.date) { marker in
                RuleMark(x: .value("Reset", marker.date))
                    .foregroundStyle(.secondary.opacity(0.6))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    .annotation(position: .top, spacing: 2, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                        Text("\(Int(marker.unusedPercent.rounded()))% unused")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
            }
            if let hover, let extent = dataExtent {
                HoverRule(date: hover.point.date, extent: extent) {
                    ChartCallout {
                        Text("\(hover.point.date.formatted(Self.hoverFormat)) · \(DisplayFormat.points(hover.point.percent)) used")
                        if let reset = hover.reset {
                            Text("Reset: \(DisplayFormat.points(reset.unusedPercent)) unused at reset")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                PointMark(x: .value("Time", hover.point.date), y: .value("Used", hover.point.percent))
                    .foregroundStyle(brand)
            }
        }
        .chartXSelection(value: $pointerDate)
        .edgeSafeTimeAxis(unit: range.bucketComponent, desiredCount: 6)
        .chartYScale(domain: 0...100)
        .chartYAxis {
            AxisMarks(values: [0, 50, 100]) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let percent = value.as(Int.self) {
                        Text(DisplayFormat.points(percent))
                    }
                }
            }
        }
        .accessibilityLabel("\(row.name) used over the \(range.label) range, \(row.resetMarkers.count) resets")
    }
}
