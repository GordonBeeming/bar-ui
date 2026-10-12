import AppKit

/// The app icon's glyph (a progress ring around two Limit meters) drawn for
/// the menu bar. It is a template image: macOS tints the menu bar, so the
/// icon's colours can't show there, and the tracks are told apart from the
/// fills by opacity instead.
enum MenuBarIcon {
    static let image: NSImage = {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: false) { _ in
            let center = NSPoint(x: 9, y: 9)
            let radius: CGFloat = 7.4
            let lineWidth: CGFloat = 1.7
            let track = NSColor.black.withAlphaComponent(0.3)
            let fill = NSColor.black

            let ringTrack = NSBezierPath()
            ringTrack.appendArc(withCenter: center, radius: radius, startAngle: 0, endAngle: 360)
            ringTrack.lineWidth = lineWidth
            track.setStroke()
            ringTrack.stroke()

            // Three quarters, clockwise from twelve o'clock, as on the app icon.
            let ring = NSBezierPath()
            ring.appendArc(withCenter: center, radius: radius, startAngle: 90, endAngle: 180, clockwise: true)
            ring.lineWidth = lineWidth
            ring.lineCapStyle = .round
            fill.setStroke()
            ring.stroke()

            let meterWidth: CGFloat = 8
            let meterHeight: CGFloat = 2
            let meterX = center.x - meterWidth / 2
            for (offset, share) in [(CGFloat(1.6), CGFloat(0.72)), (CGFloat(-1.6), CGFloat(0.46))] {
                let y = center.y + offset - meterHeight / 2
                track.setFill()
                NSBezierPath(roundedRect: NSRect(x: meterX, y: y, width: meterWidth, height: meterHeight), xRadius: 1, yRadius: 1).fill()
                fill.setFill()
                NSBezierPath(roundedRect: NSRect(x: meterX, y: y, width: meterWidth * share, height: meterHeight), xRadius: 1, yRadius: 1).fill()
            }
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Bar UI"
        return image
    }()
}
