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

    /// Resets at the same moment (ClaudeBar's Weekly and Weekly Fable) would
    /// draw on top of each other; each after the first moves right by this
    /// share of the range so they stand side by side.
    private static let sideBySideShare = 0.008
    /// Diamonds sit above the 100% line, clear of the tallest bar.
    private static let perkRowValue = 112.0
    /// How close, as a share of the range, the pointer must be to pick a mark.
    private static let pickShare = 0.03

    private struct PlacedBar: Identifiable {
        let bar: ResetsChartData.Bar
        let x: Date
        var id: String { bar.id }
    }

    private var placedBars: [PlacedBar] {
        let span = data.domain.upperBound.timeIntervalSince(data.domain.lowerBound)
        var seen: [Date: Int] = [:]
        return data.bars.map { bar in
            let index = seen[bar.date, default: 0]
            seen[bar.date] = index + 1
            return PlacedBar(bar: bar, x: bar.date.addingTimeInterval(Double(index) * span * Self.sideBySideShare))
        }
    }

    private enum Picked {
        case bar(ResetsChartData.Bar)
        case perk(ResetsChartData.PerkMarker)

        var date: Date {
            switch self {
            case .bar(let bar): bar.date
            case .perk(let perk): perk.date
            }
        }
    }

    private var picked: Picked? {
        guard let pointerDate else {
            return nil
        }
        let reach = data.domain.upperBound.timeIntervalSince(data.domain.lowerBound) * Self.pickShare
        let candidates = data.bars.map(Picked.bar) + data.perks.map(Picked.perk)
        return candidates
            .map { ($0, abs($0.date.timeIntervalSince(pointerDate))) }
            .filter { $0.1 <= reach }
            .min { $0.1 < $1.1 }?
            .0
    }

    var body: some View {
        Chart {
            ForEach(placedBars) { placed in
                BarMark(
                    x: .value("Reset", placed.x),
                    y: .value("Unused", placed.bar.unusedPercent),
                    width: .fixed(10)
                )
                .foregroundStyle(by: .value("Bar App", placed.bar.app.displayName))
                .cornerRadius(3)
            }
            ForEach(data.perks) { perk in
                PointMark(x: .value("Perk", perk.date), y: .value("Perk", Self.perkRowValue))
                    .symbol(.diamond)
                    .symbolSize(70)
                    .foregroundStyle(perk.app.brandColor)
            }
            if let picked {
                HoverRule(date: picked.date, extent: data.domain) {
                    callout(for: picked)
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

    private func callout(for picked: Picked) -> some View {
        ChartCallout {
            switch picked {
            case .bar(let bar):
                Text("\(bar.app.displayName) · \(bar.limitName) reset")
                    .fontWeight(.semibold)
                Text("\(DisplayFormat.points(Int(bar.unusedPercent.rounded()))) unused")
                Text(bar.date.formatted(date: .abbreviated, time: .shortened))
                    .foregroundStyle(.secondary)
            case .perk(let perk):
                Text("\(perk.app.displayName) · \(perk.title)")
                    .fontWeight(.semibold)
                Text(perk.detail)
                Text(perk.date.formatted(date: .abbreviated, time: .shortened))
                    .foregroundStyle(.secondary)
            }
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
