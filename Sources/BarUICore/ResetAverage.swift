import Foundation

/// The average Unused at Reset for a Limit, over a lookback that suits its
/// Window rather than whatever range the chart shows, so it reflects recent
/// habits: the last week for Windows of a day or less, the last five
/// Windows for longer ones (five weeks for a weekly Limit). Windows used
/// 10% or less are left out, so a quiet overnight Session doesn't drag the
/// average towards 100% unused.
public struct ResetAverage: Sendable, Equatable {
    public struct Reset: Sendable, Equatable {
        public let date: Date
        /// Utilisation just before the reset, 0 to 100.
        public let utilizationLast: Double

        public init(date: Date, utilizationLast: Double) {
            self.date = date
            self.utilizationLast = utilizationLast
        }
    }

    static let shortWindowLookback: TimeInterval = 7 * 86_400
    static let longWindowCount = 5
    /// A Window has to be used more than this, in percent, to count.
    static let minimumUtilization: Double = 10

    public let lookback: TimeInterval
    /// "last 7d", "last 5 weeks" or "last 5 Windows".
    public let label: String
    /// Nil when no Window in the lookback was busy enough to count.
    public let unusedPercent: Double?
    /// How many resets the average came from.
    public let count: Int

    public init(resets: [Reset], windowMinutes: Int?, now: Date) {
        let window = windowMinutes.map { TimeInterval($0) * 60 } ?? 0
        if window > 86_400 {
            lookback = window * TimeInterval(Self.longWindowCount)
            label = window == 7 * 86_400 ? "last \(Self.longWindowCount) weeks" : "last \(Self.longWindowCount) Windows"
        } else {
            lookback = Self.shortWindowLookback
            label = "last 7d"
        }
        let start = now.addingTimeInterval(-lookback)
        let counted = resets.filter { $0.date >= start && $0.date <= now && $0.utilizationLast > Self.minimumUtilization }
        count = counted.count
        unusedPercent = counted.isEmpty
            ? nil
            : counted.map { 100 - $0.utilizationLast }.reduce(0, +) / Double(counted.count)
    }
}
