import AppKit
import BarUICore
import SwiftUI

struct SidebarRow: View {
    let item: SidebarItem

    var body: some View {
        switch item {
        case .overview:
            Label(item.title, systemImage: "square.grid.2x2")
        case .barApp(let app):
            Label {
                Text(item.title)
            } icon: {
                BarAppTile(app: app)
            }
        case .archive(let page):
            Label(item.title, systemImage: page.systemImage)
        }
    }
}

private struct BarAppTile: View {
    let app: BarApp

    var body: some View {
        RoundedRectangle(cornerRadius: 5, style: .continuous)
            .fill(app.brandColor)
            .frame(width: 18, height: 18)
            .overlay {
                Image(systemName: app.systemImage)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white)
            }
            .accessibilityHidden(true)
    }
}

private extension ArchivePage {
    var systemImage: String {
        switch self {
        case .events: "text.alignleft"
        case .imports: "square.and.arrow.down"
        }
    }
}

private extension BarApp {
    var systemImage: String {
        switch self {
        case .claudeBar: "asterisk"
        case .codexBar: "chevron.forward"
        }
    }

    /// Dynamic so the tile re-resolves when the system appearance flips,
    /// using the design's light and dark brand values.
    var brandColor: Color {
        switch self {
        case .claudeBar: Color(light: 0xD97757, dark: 0xE08A6C)
        case .codexBar: Color(light: 0x2449B8, dark: 0x6A8BFF)
        }
    }
}

private extension Color {
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
