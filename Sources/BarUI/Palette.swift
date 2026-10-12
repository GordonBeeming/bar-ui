import AppKit
import BarUICore
import SwiftUI

extension BarApp {
    /// Dynamic so the tile re-resolves when the system appearance flips,
    /// using the design's light and dark brand values.
    var brandColor: Color {
        switch self {
        case .claudeBar: Color(light: 0xD97757, dark: 0xE08A6C)
        case .codexBar: Color(light: 0x2449B8, dark: 0x6A8BFF)
        }
    }
}

extension LimitCard.Severity {
    /// The meter fill. A Limit that's fine keeps its Bar App's colour, so
    /// amber and red only appear when they mean something.
    func meterColor(for app: BarApp) -> Color {
        switch self {
        case .normal: app.brandColor
        case .runningLow: Color(light: 0xC77700, dark: 0xC77700)
        case .nearLimit: Color(light: 0xD1242F, dark: 0xD1242F)
        }
    }

    /// Darker than the meter in light mode so the label passes contrast as text.
    var labelColor: Color {
        switch self {
        case .normal: .secondary
        case .runningLow: Color(light: 0x8A5300, dark: 0xF2B544)
        case .nearLimit: Color(light: 0xB3141E, dark: 0xFF7B7B)
        }
    }
}

extension Color {
    init(light: UInt32, dark: UInt32) {
        self.init(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return NSColor(rgb: isDark ? dark : light)
        })
    }
}

private extension NSColor {
    convenience init(rgb: UInt32) {
        self.init(
            srgbRed: CGFloat((rgb >> 16) & 0xFF) / 255,
            green: CGFloat((rgb >> 8) & 0xFF) / 255,
            blue: CGFloat(rgb & 0xFF) / 255,
            alpha: 1
        )
    }
}
