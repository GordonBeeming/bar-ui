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
        burnRateText = Self.burnRateText(percentPerHour: burnRate.percentPerHour)
        projectionText = burnRate
            .timeUntilFullBeforeReset(from: card.utilization, resetsAt: card.resetsAt, now: now)
            .map { "On pace to run out in " + LimitCard.durationText(seconds: $0) + ", before it resets" }
    }

    /// The sign says the Window is filling up; a rate that shows as zero at
    /// one decimal place reads as steady rather than "0%/h".
    static func burnRateText(percentPerHour: Double) -> String {
        let rounded = (percentPerHour * 10).rounded() / 10
        guard rounded > 0 else {
            return "Steady"
        }
        return "+" + rounded.formatted(.number.precision(.fractionLength(0...1))) + "%/h"
    }
}
