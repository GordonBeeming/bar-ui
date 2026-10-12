import Foundation

/// One Window of one Bar App in the Menu Bar Preview: how much is used, how
/// fast it is climbing, and whether it will run out before it resets.
public struct MenuBarLimitRow: Sendable, Hashable, Identifiable {
    public let id: String
    public let app: BarApp
    public let appName: String
    public let windowName: String
    public let utilization: Double
    public let percentUsed: Int
    public let severity: LimitCard.Severity
    public let resetText: String
    public let burnRateText: String
    /// Set only when 100% comes before the Window resets.
    public let projectionText: String?

    public var isBurnRateHighlighted: Bool {
        projectionText != nil
    }

    public init(card: LimitCard, burnRate: BurnRate?, now: Date) {
        id = card.id
        app = card.app
        appName = card.appName
        windowName = card.windowName
        utilization = card.utilization
        percentUsed = card.percentUsed
        severity = card.severity
        resetText = card.resetText

        guard let burnRate else {
            burnRateText = "Not enough data yet"
            projectionText = nil
            return
        }
        let points = burnRate.percentPerHour.formatted(.number.precision(.fractionLength(0...1)))
        burnRateText = "\(points) pts/h"
        projectionText = burnRate
            .timeUntilFullBeforeReset(from: card.utilization, resetsAt: card.resetsAt, now: now)
            .map { "At this rate it hits 100% in " + LimitCard.durationText(seconds: $0) }
    }
}
