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
    /// How much of the Window has gone, 0 to 1: the point the meter would be
    /// at if usage were spread evenly. Nil when the Window's length or reset
    /// time isn't known, or the reset is already due.
    public let windowElapsed: Double?
    /// Positive is over, negative is headroom; nil when `windowElapsed` is.
    public let paceGap: Double?
    /// "24% headroom" or "10% over", or nil when `windowElapsed` is.
    public let paceText: String?
    /// "Resets Tomorrow 5:00 PM · in 1d 9h".
    public let resetDetailText: String

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
        windowElapsed = Self.windowElapsed(minutes: limit.limit.windowDurationMinutes, resetsAt: limit.resetsAt, now: now)
        paceGap = Self.paceGap(utilization: limit.utilization, windowElapsed: windowElapsed)
        paceText = Self.paceText(utilization: limit.utilization, windowElapsed: windowElapsed)
        resetDetailText = Self.resetDetail(until: limit.resetsAt, now: now)
    }

    static func windowElapsed(minutes: Int?, resetsAt: Date?, now: Date) -> Double? {
        guard let minutes, minutes > 0, let resetsAt else {
            return nil
        }
        let remaining = resetsAt.timeIntervalSince(now)
        guard remaining > 0 else {
            return nil
        }
        let length = TimeInterval(minutes) * 60
        // A reset further out than one Window (clock skew, a stale sample)
        // reads as the Window just starting rather than a negative share.
        return min(max(1 - remaining / length, 0), 1)
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
        return "Resets in " + durationText(seconds: seconds)
    }

    /// How far usage is from an even spread over the Window, in whole
    /// percentage points: positive is over (using allowance meant for later in
    /// the Window), negative is headroom that can be used now.
    static func paceGap(utilization: Double, windowElapsed: Double?) -> Double? {
        windowElapsed.map { utilization - $0 * 100 }
    }

    /// "24% headroom" or "10% over". The line isn't a target: headroom is
    /// what can still be used without running out before the reset. The side
    /// comes from the unrounded gap, so a fraction past the tick reads as
    /// "<1% over" rather than looking level.
    static func paceText(utilization: Double, windowElapsed: Double?) -> String? {
        guard let gap = paceGap(utilization: utilization, windowElapsed: windowElapsed) else {
            return nil
        }
        let points = Int(abs(gap).rounded())
        let amount = points == 0 && gap != 0 ? "<1%" : "\(points)%"
        return gap > 0 ? "\(amount) over" : "\(amount) headroom"
    }

    /// The reset as a clock time plus a countdown: the time on its own for
    /// today, "Tomorrow" or the weekday within a week, the date beyond that.
    static func resetDetail(until resetsAt: Date?, now: Date, calendar: Calendar = .current) -> String {
        guard let resetsAt else {
            return "Reset time unknown"
        }
        let seconds = resetsAt.timeIntervalSince(now)
        guard seconds > 0 else {
            return "Resetting now"
        }
        let locale = calendar.locale ?? .current
        let time = Self.formatted(resetsAt, template: "jmm", calendar: calendar, locale: locale)
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: resetsAt)).day ?? 0
        let when: String = switch days {
        case 0: time
        case 1: "Tomorrow \(time)"
        case 2..<7: Self.formatted(resetsAt, template: "EEE", calendar: calendar, locale: locale) + " \(time)"
        default: Self.formatted(resetsAt, template: "MMMd", calendar: calendar, locale: locale) + ", \(time)"
        }
        return "Resets \(when) · in \(durationText(seconds: seconds))"
    }

    private static func formatted(_ date: Date, template: String, calendar: Calendar, locale: Locale) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = locale
        formatter.setLocalizedDateFormatFromTemplate(template)
        return formatter.string(from: date)
    }

    /// Rounding down keeps a countdown from promising more time than there is.
    static func durationText(seconds: TimeInterval) -> String {
        let totalMinutes = Int(max(seconds, 0) / 60)
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
        return parts.joined(separator: " ")
    }
}
