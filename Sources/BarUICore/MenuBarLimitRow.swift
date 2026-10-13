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
    /// "Resets Tomorrow 5:00 PM · in 1d 9h".
    public let resetDetailText: String
    /// Where the meter would be with usage spread evenly over the Window.
    public let windowElapsed: Double?
    /// "24% headroom" or "10% over", or nil when the Window's length or reset
    /// is unknown or usage is too low to judge.
    public let paceText: String?
    /// Positive is over, negative is headroom.
    public let paceGap: Double?
    public let burnRateText: String
    /// Set only when 100% comes before the Window resets.
    public let projectionText: String?

    public var isBurnRateHighlighted: Bool {
        projectionText != nil
    }

    /// `burnRate` is the last hour, shown as the rate. `pace` looks back
    /// further and is what a warning is judged on, so a short burst doesn't
    /// flash a warning on and off.
    public init(card: LimitCard, burnRate: BurnRate?, pace: BurnRate?, now: Date) {
        id = card.id
        app = card.app
        appName = card.appName
        windowName = card.windowName
        utilization = card.utilization
        percentUsed = card.percentUsed
        severity = card.severity
        resetText = card.resetText
        resetDetailText = card.resetDetailText
        windowElapsed = card.windowElapsed
        paceText = card.paceText
        paceGap = card.paceGap

        // Samples a few minutes apart can leave the last hour with one point;
        // the longer pace still says how fast the Window is filling.
        let sustainedPace = pace.flatMap { $0.isSustained ? $0 : nil }
        if let shown = burnRate ?? sustainedPace {
            burnRateText = Self.burnRateText(percentPerHour: shown.percentPerHour)
        } else {
            burnRateText = "Not enough data yet"
        }
        // A few points of change at the start of a Window says little about
        // the pace, and any start would read as too fast, so no warning yet.
        guard card.utilization >= LimitCard.minimumUtilizationForPace, let sustainedPace else {
            projectionText = nil
            return
        }
        projectionText = sustainedPace
            .timeUntilFullBeforeReset(from: card.utilization, resetsAt: card.resetsAt, now: now)
            .map { "On pace to run out in " + LimitCard.durationText(seconds: $0) + ", before it resets" }
    }

    /// The sign says the Window is filling up; a rate that rounds to zero at
    /// one decimal place shows as 0%/h with no sign.
    static func burnRateText(percentPerHour: Double) -> String {
        let rounded = (percentPerHour * 10).rounded() / 10
        guard rounded > 0 else {
            return "0%/h"
        }
        return "+" + rounded.formatted(.number.precision(.fractionLength(0...1))) + "%/h"
    }
}
