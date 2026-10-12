import Foundation

/// How token counts and percentages read everywhere in the Dashboard, so the
/// Overview, the Bar App pages and the Menu Bar Preview can't drift apart.
enum DisplayFormat {
    /// A token count, shortened: "1.2M".
    static func tokens(_ tokens: Int64) -> String {
        tokens.formatted(.number.notation(.compactName).precision(.fractionLength(0...1)))
    }

    /// A share from 0 to 1, such as the part of output that was reasoning.
    static func share(_ share: Double) -> String {
        share.formatted(.percent.precision(.fractionLength(0)))
    }

    /// Percentage points from 0 to 100, such as how much of a Limit is used.
    static func points(_ points: Int) -> String {
        "\(points)%"
    }

    static func points(_ points: Double) -> String {
        Self.points(Int(points.rounded()))
    }
}
