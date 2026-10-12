import Foundation

/// One card in the Overview's current Limits strip.
public struct LimitCard: Sendable, Hashable, Identifiable {
    public enum Severity: Sendable, Hashable {
        case normal
        case runningLow
        case nearLimit

        public var label: String? {
            switch self {
            case .normal: nil
            case .runningLow: "Running low"
            case .nearLimit: "Near limit"
            }
        }

        init(utilization: Double) {
            switch utilization {
            case 90...: self = .nearLimit
            case 75...: self = .runningLow
            default: self = .normal
            }
        }
    }

    public let app: BarApp
    public let limitID: String
    public let windowName: String
    public let utilization: Double
    public let percentUsed: Int
    public let severity: Severity
    public let resetsAt: Date?
    public let resetText: String

    public var id: String {
        "\(app.rawValue)/\(limitID)"
    }

    public var appName: String {
        app.displayName
    }

    /// Cards for the Limits of Bar Apps that are Tracking right now. A Bar App
    /// with Tracking off keeps its Limits in the Archive, but their last
    /// values aren't current, so they don't belong in this strip.
    public static func cards(for limits: [CurrentLimit], states: [BarApp: TrackingState], now: Date) -> [LimitCard] {
        limits
            .filter { states[$0.app] == .tracking }
            .sorted(by: displayOrder)
            .map { LimitCard(limit: $0, now: now) }
    }

    init(limit: CurrentLimit, now: Date) {
        app = limit.app
        limitID = limit.limit.id
        windowName = limit.limit.name
        utilization = limit.utilization
        percentUsed = Int(limit.utilization.rounded())
        severity = Severity(utilization: limit.utilization)
        resetsAt = limit.resetsAt
        resetText = Self.resetText(until: limit.resetsAt, now: now)
    }

    /// Bar Apps in their sidebar order, then shortest Window first, so the
    /// Limit that resets soonest leads. Unknown Windows go last.
    private static func displayOrder(_ lhs: CurrentLimit, _ rhs: CurrentLimit) -> Bool {
        let apps = BarApp.allCases
        if lhs.app != rhs.app {
            return (apps.firstIndex(of: lhs.app) ?? apps.count) < (apps.firstIndex(of: rhs.app) ?? apps.count)
        }
        let lhsMinutes = lhs.limit.windowDurationMinutes ?? .max
        let rhsMinutes = rhs.limit.windowDurationMinutes ?? .max
        if lhsMinutes != rhsMinutes {
            return lhsMinutes < rhsMinutes
        }
        // The ID rather than the name, so a tool renaming a label doesn't
        // reshuffle the strip.
        return lhs.limit.id < rhs.limit.id
    }

    static func resetText(until resetsAt: Date?, now: Date) -> String {
        guard let resetsAt else {
            return "Reset time unknown"
        }
        let seconds = resetsAt.timeIntervalSince(now)
        guard seconds > 0 else {
            return "Resetting now"
        }
        // Rounding down keeps the countdown from promising more time than
        // there is.
        let totalMinutes = Int(seconds / 60)
        let days = totalMinutes / (24 * 60)
        let hours = (totalMinutes / 60) % 24
        let minutes = totalMinutes % 60
        let parts: [String] = if days > 0 {
            ["\(days)d", hours > 0 ? "\(hours)h" : nil].compactMap(\.self)
        } else if hours > 0 {
            ["\(hours)h", minutes > 0 ? "\(minutes)m" : nil].compactMap(\.self)
        } else if minutes > 0 {
            ["\(minutes)m"]
        } else {
            ["under a minute"]
        }
        return "Resets in " + parts.joined(separator: " ")
    }
}
