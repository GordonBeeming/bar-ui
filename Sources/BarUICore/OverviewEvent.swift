import Foundation

/// One entry in the Overview's Events list: something that happened to a Bar
/// App's Limits, Perks or Tracking, in words ready to show.
public struct OverviewEvent: Sendable, Hashable, Identifiable {
    public enum Kind: Sendable, Hashable {
        case limitReset
        case limitAppeared
        case limitDisappeared
        case runningLow
        case nearLimit
        case perkAvailable
        case perkGone
        case trackingStarted
    }

    public let id: String
    public let app: BarApp
    public let kind: Kind
    public let title: String
    public let detail: String
    public let date: Date

    /// Every event the Archive can tell, newest first. Limits crossing into
    /// running low or near limit aren't logged by the Bar Apps; they come from
    /// the utilisation samples, using the same thresholds as the Limits strip.
    public static func timeline(
        histories: [LimitHistory],
        limitEvents: [LimitLifecycleEvent],
        trackingStarts: [TrackingStartedEvent],
        perkAvailable: [PerkAvailableEvent],
        gonePerks: [GonePerk],
        locale: Locale = .current,
        timeZone: TimeZone = .current
    ) -> [OverviewEvent] {
        var events: [OverviewEvent] = []

        for history in histories {
            for reset in history.resets {
                events.append(OverviewEvent(
                    id: "reset/\(history.app.rawValue)/\(history.limit.id)/\(reset.timeUnixNano)",
                    app: history.app,
                    kind: .limitReset,
                    title: "\(reset.limit.name) reset",
                    detail: "\(Int((100 - reset.utilizationLast).rounded()))% unused at reset",
                    date: Date(unixNano: reset.timeUnixNano)
                ))
            }
            events += crossings(in: history)
        }

        for event in limitEvents {
            let appeared = event.kind == .appeared
            events.append(OverviewEvent(
                id: "limit-\(event.kind.rawValue)/\(event.app.rawValue)/\(event.limit.id)/\(event.timeUnixNano)",
                app: event.app,
                kind: appeared ? .limitAppeared : .limitDisappeared,
                title: "\(event.limit.name) \(event.kind.rawValue)",
                detail: appeared
                    ? LimitHistoryRow.windowText(minutes: event.limit.windowDurationMinutes)
                    : "The Bar App stopped reporting it",
                date: Date(unixNano: event.timeUnixNano)
            ))
        }

        for event in trackingStarts {
            let interval = event.intervalMinutes == 1 ? "minute" : "\(event.intervalMinutes) minutes"
            events.append(OverviewEvent(
                id: "tracking/\(event.app.rawValue)/\(event.timeUnixNano)",
                app: event.app,
                kind: .trackingStarted,
                title: "Tracking started",
                detail: "Sampling every \(interval)",
                date: Date(unixNano: event.timeUnixNano)
            ))
        }

        for event in perkAvailable {
            var detail = PerkText.quantity(kind: event.kind, quantity: event.quantity, currency: event.currency, locale: locale)
            if let expiresAt = event.expiresAt {
                let expiry = Date(timeIntervalSince1970: TimeInterval(expiresAt))
                let style = Date.FormatStyle(locale: locale, timeZone: timeZone).month(.abbreviated).day()
                detail += " · expires \(expiry.formatted(style))"
            }
            events.append(OverviewEvent(
                id: "perk-available/\(event.app.rawValue)/\(event.kind.rawValue)/\(event.currency ?? "")/\(event.perkID ?? "")/\(event.quantity ?? -1)/\(event.timeUnixNano)",
                app: event.app,
                kind: .perkAvailable,
                title: "\(PerkText.title(of: event.kind)) available",
                detail: detail,
                date: Date(unixNano: event.timeUnixNano)
            ))
        }

        for perk in gonePerks {
            let quantity = PerkText.quantity(kind: perk.kind, quantity: perk.quantity, currency: perk.currency, locale: locale)
            events.append(OverviewEvent(
                id: "perk-gone/\(perk.app.rawValue)/\(perk.kind.rawValue)/\(perk.currency ?? "")/\(perk.perkID ?? "")/\(perk.quantity ?? -1)/\(perk.goneAt.timeIntervalSince1970)",
                app: perk.app,
                kind: .perkGone,
                title: "\(PerkText.title(of: perk.kind)) gone",
                detail: "\(quantity) · \(PerkText.label(for: perk.reason))",
                date: perk.goneAt
            ))
        }

        return events.sorted { ($0.date, $1.id) > ($1.date, $0.id) }
    }

    /// The events inside the range, nothing from the future (a Bar App with a
    /// wrong clock) and nothing older than the range reaches back.
    public static func within(_ events: [OverviewEvent], range: TimeRange, now: Date) -> [OverviewEvent] {
        let start = range.start(now: now)
        return events.filter { event in event.date <= now && start.map { event.date > $0 } != false }
    }

    /// Each Window says running low and near limit at most once, the first
    /// time the Limit gets there, so a Limit hovering on a threshold doesn't
    /// fill the list. A reset starts a new Window from normal. The Limit's
    /// first sample ever has nothing before it, so how it got there is
    /// unknown and it never counts as a crossing.
    private static func crossings(in history: LimitHistory) -> [OverviewEvent] {
        var events: [OverviewEvent] = []
        let resets = history.resets.map(\.timeUnixNano).sorted()
        var nextReset = resets.startIndex
        // The worst the current Window has been; nil until the Limit has a sample.
        var reached = history.peakBeforeRange.map(LimitCard.Severity.init(utilization:))
        for sample in history.utilization.sorted(by: { $0.timeUnixNano < $1.timeUnixNano }) {
            while nextReset < resets.endIndex, resets[nextReset] <= sample.timeUnixNano {
                if reached != nil {
                    reached = .normal
                }
                nextReset += 1
            }
            let severity = LimitCard.Severity(utilization: sample.value)
            guard let previous = reached else {
                reached = severity
                continue
            }
            guard severity.rank > previous.rank else {
                continue
            }
            reached = severity
            let kind: Kind = severity == .nearLimit ? .nearLimit : .runningLow
            events.append(OverviewEvent(
                id: "\(kind)/\(history.app.rawValue)/\(history.limit.id)/\(sample.timeUnixNano)",
                app: history.app,
                kind: kind,
                title: "\(history.limit.name) \(severity == .nearLimit ? "near limit" : "running low")",
                detail: "Reached \(Int(sample.value.rounded()))% used",
                date: Date(unixNano: sample.timeUnixNano)
            ))
        }
        return events
    }

    /// "5 minutes ago", or "Just now" inside the first minute.
    public func relativeTime(now: Date, locale: Locale = .current) -> String {
        guard now.timeIntervalSince(date) >= 60 else {
            return "Just now"
        }
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = locale
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: now)
    }
}

private extension LimitCard.Severity {
    var rank: Int {
        switch self {
        case .normal: 0
        case .runningLow: 1
        case .nearLimit: 2
        }
    }
}
