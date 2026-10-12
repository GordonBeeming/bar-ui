import BarUICore
import SwiftUI

/// "24% headroom" or "10% over", coloured by which side is safe: headroom
/// can be used without running out before the reset (green); over is using
/// allowance meant for later in the Window (amber). Level stays neutral.
struct PaceLabel: View {
    let text: String
    /// Positive is over, negative is headroom.
    let gap: Double
    var emphasised = false

    private static let behind = Color(light: 0x1F7A3A, dark: 0x5BD17F)
    private static let ahead = LimitCard.Severity.runningLow.labelColor

    var body: some View {
        Label {
            Text(text)
        } icon: {
            Image(systemName: icon)
        }
        .font(.caption)
        .monospacedDigit()
        .fontWeight(emphasised ? .semibold : .regular)
        .foregroundStyle(tint)
    }

    private var icon: String {
        gap > 0 ? "arrow.up.right" : gap < 0 ? "arrow.down.right" : "equal"
    }

    private var tint: Color {
        gap > 0 ? Self.ahead : gap < 0 ? Self.behind : .secondary
    }
}
