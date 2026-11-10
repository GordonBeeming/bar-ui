/// How the Menu Bar Preview lays its cards out: two columns, filled across
/// a row at a time, or one full-width column when there is only one card.
public enum MenuBarGrid {
    public static func columnCount(forCards count: Int) -> Int {
        count > 1 ? 2 : 1
    }

    /// The tallest the card area may be so the whole panel fits the screen it is
    /// on: what is left of the visible height after the summary, the footer
    /// and the spacing between them. A screen too small for even those leaves
    /// no room for cards, which is 0, not some minimum that would push the
    /// footer off the screen.
    public static func cardAreaLimit(visibleHeight: Double, summaryHeight: Double, footerHeight: Double, spacing: Double) -> Double {
        max(0, visibleHeight - summaryHeight - footerHeight - spacing)
    }

    /// The items in row-major order, `columns` to a row. The last row may be
    /// short.
    public static func rows<Item>(of items: [Item], columns: Int) -> [[Item]] {
        guard columns > 0 else {
            return []
        }
        return stride(from: 0, to: items.count, by: columns).map { start in
            Array(items[start..<min(start + columns, items.count)])
        }
    }
}
