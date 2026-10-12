import BarUICore
import Charts
import SwiftUI

/// Tokens per bucket, stacked by Bar App in each Bar App's colour. The
/// Overview shows it full size with an axis and legend; the Menu Bar Preview
/// shows it `compact`, as a sparkline.
struct StackedTokensChart: View {
    let usage: TokenUsage
    let unit: Calendar.Component
    var compact = false

    var body: some View {
        Chart {
            ForEach(usage.buckets, id: \.start) { bucket in
                ForEach(BarApp.allCases, id: \.self) { app in
                    if let tokens = bucket.tokensByApp[app], tokens > 0 {
                        BarMark(
                            x: .value("Time", bucket.start, unit: unit),
                            y: .value("Tokens", tokens)
                        )
                        .foregroundStyle(by: .value("Bar App", app.displayName))
                    }
                }
            }
        }
        .chartForegroundStyleScale(
            domain: BarApp.allCases.map(\.displayName),
            range: BarApp.allCases.map(\.brandColor)
        )
        .chartLegend(compact ? .hidden : .automatic)
        .chartYAxis(compact ? .hidden : .automatic)
        .chartYAxis {
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
