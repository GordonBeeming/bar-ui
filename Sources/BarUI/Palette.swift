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
        case .grokBar: Color(light: 0x1A1A1A, dark: 0xF2F2F2)
        }
    }

    /// The colour of an app's further Accounts. The first keeps the brand
    /// colour; each next one is a clearly lighter or darker step of it, picked
    /// per theme so it stays readable on that theme's background. Steps past
    /// the table reuse its last.
    func brandColor(step: Int) -> Color {
        guard step > 0 else {
            return brandColor
        }
        let steps: [(light: UInt32, dark: UInt32)] = switch self {
        case .claudeBar: [(0x9C4A2F, 0xF2B49C), (0x5E2A1A, 0xF9D8C9)]
        case .codexBar: [(0x142F7A, 0xA5BAFF), (0x0A1A4D, 0xD0DBFF)]
        case .grokBar: [(0x6B6B6B, 0xB0B0B0), (0x858585, 0x808080)]
        }
        let pick = steps[min(step, steps.count) - 1]
        return Color(light: pick.light, dark: pick.dark)
    }

    /// The sidebar glyph. GrokBar's dark fill is near white, so the sparkle
    /// flips to black there. The other tiles stay dark enough for white.
    var symbolColor: Color {
        switch self {
        case .claudeBar, .codexBar: .white
        case .grokBar: Color(light: 0xFFFFFF, dark: 0x1A1A1A)
        }
    }
}

extension TokenKind {
    /// Cache reads are most of every total, so they get the quietest colour;
    /// new input and output differ in lightness as well as hue so they stay
    /// apart when stacked.
    var color: Color {
        switch self {
        case .cacheRead: Color(light: 0xA3A3AB, dark: 0x6E6E78)
        case .newInput: Color(light: 0x2F6FEB, dark: 0x6A9BFF)
        case .output: Color(light: 0xC77700, dark: 0xF2B544)
        }
    }
}

extension LimitCard.Severity {
    /// The meter fill. A Limit that's fine keeps its Bar App's colour, so
    /// amber and red only appear when they mean something.
    func meterColor(for app: BarApp, step: Int = 0) -> Color {
        switch self {
        case .normal: app.brandColor(step: step)
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
