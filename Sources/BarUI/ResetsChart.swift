import BarUICore
import Charts
import SwiftUI

/// A bar per reset, as tall as the share of the Window left unused, so a tall
/// bar is a Window that was barely touched; Perk changes sit as diamonds above
/// the bars. Spans the same range as the Tokens chart.
struct ResetsChart: View {
    let data: ResetsChartData
    let unit: Calendar.Component

    @State private var pointerDate: Date?

    private static let barWidth = 10.0
    /// Resets at the same moment (ClaudeBar's Weekly and Weekly Fable) would
    /// draw on top of each other. They keep their real time on the axis and
    /// spread sideways in points, so none is pushed past now or the range.
    private static let sideBySideGap = 2.0
    /// Diamonds sit above the 100% line, clear of the tallest bar.
    private static let perkRowValue = 112.0

    private struct PlacedBar: Identifiable {
        let bar: ResetsChartData.Bar
        let offset: CGFloat
        var id: String { bar.id }
    }

    private var placedBars: [PlacedBar] {
        let groupSize = Dictionary(grouping: data.bars, by: \.date).mapValues(\.count)
        var seen: [Date: Int] = [:]
        return data.bars.map { bar in
            let index = seen[bar.date, default: 0]
            seen[bar.date] = index + 1
            let centred = Double(index) - Double(groupSize[bar.date, default: 1] - 1) / 2
            return PlacedBar(bar: bar, offset: centred * (Self.barWidth + Self.sideBySideGap))
        }
    }

    private var moment: ResetsChartData.Moment? {
        pointerDate.flatMap(data.moment(near:))
    }

    var body: some View {
        Chart {
            ForEach(placedBars) { placed in
                BarMark(
                    x: .value("Reset", placed.bar.date),
                    y: .value("Unused", placed.bar.unusedPercent),
                    width: .fixed(Self.barWidth),
                    // Coincident bars share an x value, and stacking would
                    // lift each onto the one before it.
                    stacking: .unstacked
                )
                .foregroundStyle(by: .value("Bar App", placed.bar.app.displayName))
                .cornerRadius(3)
                .offset(x: placed.offset)
            }
            ForEach(data.perks) { perk in
                PointMark(x: .value("Perk", perk.date), y: .value("Perk", Self.perkRowValue))
                    .symbol(.diamond)
                    .symbolSize(70)
                    .foregroundStyle(perk.app.brandColor)
            }
            if let moment {
                HoverRule(date: moment.date, extent: data.domain) {
                    callout(for: moment)
                }
            }
        }
        .chartXScale(domain: data.domain)
        .chartYScale(domain: 0...(Self.perkRowValue + 8))
        .chartYAxis {
            AxisMarks(position: .trailing, values: [0, 50, 100]) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let percent = value.as(Double.self) {
                        Text("\(Int(percent))%")
                    }
                }
            }
        }
        .edgeSafeTimeAxis(unit: unit, span: data.domain, desiredCount: 6)
        .chartForegroundStyleScale(
            domain: BarApp.allCases.map(\.displayName),
            range: BarApp.allCases.map(\.brandColor)
        )
        .chartLegend(.hidden)
        .chartXSelection(value: $pointerDate)
        .accessibilityLabel("Unused at each reset, \(data.bars.count) resets and \(data.perks.count) Perk changes")
    }

    private func callout(for moment: ResetsChartData.Moment) -> some View {
        ChartCallout {
            ForEach(moment.bars) { bar in
                Text("\(bar.app.displayName) · \(bar.limitName) reset")
                    .fontWeight(.semibold)
                Text("\(DisplayFormat.points(Int(bar.unusedPercent.rounded()))) unused")
            }
            ForEach(moment.perks) { perk in
                Text("\(perk.app.displayName) · \(perk.title)")
                    .fontWeight(.semibold)
                Text(perk.detail)
            }
            Text(moment.date.formatted(date: .abbreviated, time: .shortened))
                .foregroundStyle(.secondary)
        }
    }
}

/// The chart's key: each Bar App's colour and the Perk diamond.
struct ResetsChartLegend: View {
    var body: some View {
        HStack(spacing: 16) {
            Text("How much of each Window went unused when it reset")
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            ForEach(BarApp.allCases, id: \.self) { app in
                Label {
                    Text(app.displayName)
                } icon: {
                    RoundedRectangle(cornerRadius: 2).fill(app.brandColor).frame(width: 10, height: 10)
                }
            }
            Label {
                Text("Perk change")
            } icon: {
                Image(systemName: "diamond.fill").foregroundStyle(.secondary)
            }
        }
        .font(.caption)
        .labelStyle(.titleAndIcon)
    }
}
