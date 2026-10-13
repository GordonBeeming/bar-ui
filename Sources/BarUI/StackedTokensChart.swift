import BarUICore
import Charts
import SwiftUI

/// Tokens per bucket, stacked by kind (cache reads, new input, output). The
/// Overview shows it full size with an axis and legend; the Menu Bar Preview
/// shows it `compact`, as a sparkline.
struct StackedTokensChart: View {
    let usage: TokenUsage
    let unit: Calendar.Component
    var compact = false

    @State private var pointerDate: Date?

    private var hoveredBucket: TokenUsage.Bucket? {
        pointerDate.flatMap { usage.bucket(containing: $0, component: unit) }
    }

    private var bucketExtent: ClosedRange<Date>? {
        guard let first = usage.buckets.first?.start, let last = usage.buckets.last?.start else {
            return nil
        }
        return first...last
    }

    var body: some View {
        Chart {
            ForEach(usage.buckets, id: \.start) { bucket in
                ForEach(TokenKind.allCases, id: \.self) { kind in
                    if let tokens = bucket.tokensByKind[kind], tokens > 0 {
                        BarMark(
                            x: .value("Time", bucket.start, unit: unit),
                            y: .value("Tokens", tokens)
                        )
                        .foregroundStyle(by: .value("Kind", kind.label))
                    }
                }
            }
            if let bucket = hoveredBucket, let extent = bucketExtent {
                HoverRule(date: bucket.start.addingTimeInterval(bucketMidpoint(bucket)), extent: extent) {
                    callout(for: bucket)
                }
            }
        }
        .chartXSelection(value: $pointerDate)
        .edgeSafeTimeAxis(unit: unit, span: usage.timeDomain(component: unit), desiredCount: compact ? 4 : 6)
        .chartForegroundStyleScale(
            domain: TokenKind.allCases.map(\.label),
            range: TokenKind.allCases.map(\.color)
        )
        .chartLegend(compact ? .hidden : .automatic)
        .tokensXDomain(usage.timeDomain(component: unit))
        .tokensYAxis(compact: compact)
    }

    /// Half a bucket, so the rule sits on the middle of the bar rather than its left edge.
    private func bucketMidpoint(_ bucket: TokenUsage.Bucket) -> TimeInterval {
        guard let end = Calendar.current.date(byAdding: unit, value: 1, to: bucket.start) else {
            return 0
        }
        return end.timeIntervalSince(bucket.start) / 2
    }

    private func callout(for bucket: TokenUsage.Bucket) -> some View {
        ChartCallout {
            Text(bucket.rangeText(component: unit))
                .fontWeight(.semibold)
            ForEach(TokenKind.allCases.reversed(), id: \.self) { kind in
                if let tokens = bucket.tokensByKind[kind], tokens > 0 {
                    Text("\(kind.label): \(tokens.formatted())")
                }
            }
            Text("Total: \(bucket.tokensByKind.values.reduce(0, +).formatted())")
                .fontWeight(.semibold)
            ForEach(BarApp.allCases, id: \.self) { app in
                if let tokens = bucket.tokensByApp[app], tokens > 0 {
                    Text("\(app.displayName): \(tokens.formatted())")
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

private extension View {
    /// Quiet buckets draw no mark, so without an explicit domain the axis
    /// would shrink to the buckets that had usage.
    @ViewBuilder
    func tokensXDomain(_ domain: ClosedRange<Date>?) -> some View {
        if let domain {
            chartXScale(domain: domain)
        } else {
            self
        }
    }

    /// A sparkline has no y-axis at all; any custom axis would bring its marks
    /// and the space they take back.
    @ViewBuilder
    func tokensYAxis(compact: Bool) -> some View {
        if compact {
            chartYAxis(.hidden)
        } else {
            chartYAxis {
                AxisMarks { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let tokens = value.as(Int64.self) {
                            Text(DisplayFormat.tokens(tokens))
                        }
                    }
                }
            }
        }
    }
}
