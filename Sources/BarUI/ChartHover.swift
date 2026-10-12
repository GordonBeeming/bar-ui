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
    /// A time axis with short labels ("6 PM" for hourly buckets, "12 Oct" for
    /// daily ones) whose last label hangs back from the trailing edge instead
    /// of being cut to "1…" by it. Left to itself, Swift Charts picks a full
    /// date and time once the domain is set explicitly, and the labels
    /// collide; any label that would still overlap its neighbour is dropped.
    func edgeSafeTimeAxis(unit: Calendar.Component, desiredCount: Int = 5) -> some View {
        let format: Date.FormatStyle = unit == .hour
            ? .dateTime.hour()
            : .dateTime.day().month(.abbreviated)
        // Day labels on automatic marks can land twice in one day ("13 Oct"
        // at midnight and at noon), so daily axes mark each midnight.
        let values: AxisMarkValues = unit == .hour
            ? .automatic(desiredCount: desiredCount)
            : .stride(by: .day)
        return chartXAxis {
            AxisMarks(values: values) { value in
                AxisGridLine()
                AxisTick()
                AxisValueLabel(
                    format: format,
                    anchor: value.index == value.count - 1 ? .topTrailing : nil,
                    collisionResolution: .greedy(minimumSpacing: 6)
                )
            }
        }
    }
}
