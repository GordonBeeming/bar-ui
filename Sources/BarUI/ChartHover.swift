import Charts
import SwiftUI

/// The small panel a chart shows beside its hover rule.
struct ChartCallout<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            content
        }
        .font(.caption)
        .monospacedDigit()
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(.separator, lineWidth: 1)
        }
        .fixedSize()
        .allowsHitTesting(false)
    }
}

/// A thin rule at `date` with `callout` beside it. In the right half of the
/// data the callout sits left of the rule, so it never runs off the plot.
struct HoverRule<Callout: View>: ChartContent {
    let date: Date
    let extent: ClosedRange<Date>
    @ViewBuilder let callout: Callout

    var body: some ChartContent {
        RuleMark(x: .value("Pointer", date))
            .foregroundStyle(.secondary)
            .lineStyle(StrokeStyle(lineWidth: 1))
            .annotation(
                position: Self.flipsLeft(date, in: extent) ? .leading : .trailing,
                alignment: .top,
                spacing: 6,
                overflowResolution: .init(x: .fit(to: .chart), y: .fit(to: .chart))
            ) {
                callout
            }
    }

    private static func flipsLeft(_ date: Date, in extent: ClosedRange<Date>) -> Bool {
        let span = extent.upperBound.timeIntervalSince(extent.lowerBound)
        guard span > 0 else {
            return false
        }
        return date.timeIntervalSince(extent.lowerBound) / span > 0.5
    }
}

extension View {
    /// A time axis whose last label hangs back from the trailing edge instead
    /// of being cut to "1…" by it.
    func edgeSafeTimeAxis() -> some View {
        chartXAxis {
            AxisMarks { value in
                AxisGridLine()
                AxisTick()
                AxisValueLabel(anchor: value.index == value.count - 1 ? .topTrailing : nil)
            }
        }
    }
}
