import SwiftUI

/// A Limit's usage bar, with a tick where usage would be if it were spread
/// evenly over the Window. A fill short of the tick has headroom; past it,
/// the Window is being used faster than it refills.
///
/// Drawn directly rather than with `Gauge`: the linear Gauge styles show
/// their label inside the bar even when labels are hidden.
struct LimitMeter: View {
    /// 0 to 1.
    let fraction: Double
    let color: Color
    /// 0 to 1, or nil when the Window's length or reset isn't known.
    let paceMark: Double?
    var height: CGFloat = 6

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary)
                Capsule()
                    .fill(color)
                    .frame(width: max(width * clamped(fraction), fraction > 0 ? height : 0))
                if let paceMark {
                    Rectangle()
                        .fill(.primary.opacity(0.75))
                        .frame(width: 2, height: height + 6)
                        .offset(x: min(max(width * clamped(paceMark) - 1, 0), width - 2))
                        .accessibilityHidden(true)
                }
            }
            .frame(height: height + 6)
        }
        .frame(height: height + 6)
    }

    private func clamped(_ value: Double) -> Double {
        min(max(value, 0), 1)
    }
}
