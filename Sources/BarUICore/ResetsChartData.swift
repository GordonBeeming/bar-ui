import Foundation

/// What the Resets & Perks chart draws, from the same events the list below
/// it shows: a bar per reset, as tall as the share of the Window left unused,
/// and a marker per Perk change. Running low, Limits appearing and Tracking
/// starting stay in the list only.
public struct ResetsChartData: Sendable, Equatable {
    public struct Bar: Sendable, Equatable, Identifiable {
        public let id: String
        public let app: BarApp
        public let limitName: String
        public let date: Date
        public let unusedPercent: Double
    }

    public struct PerkMarker: Sendable, Equatable, Identifiable {
        public let id: String
        public let app: BarApp
        public let title: String
        public let detail: String
        public let date: Date
    }

    /// Everything drawn at one instant, so a hover can list resets and Perk
    /// changes that share a timestamp instead of hiding all but one.
    public struct Moment: Sendable, Equatable {
        public let date: Date
        public let bars: [Bar]
        public let perks: [PerkMarker]
    }

    public let bars: [Bar]
    public let perks: [PerkMarker]
    /// The Tokens chart's span when given, so the two line up; otherwise the
    /// range ending now, with All time reaching back to the oldest mark.
    public let domain: ClosedRange<Date>

    public var isEmpty: Bool {
        bars.isEmpty && perks.isEmpty
    }

    public init(events: [OverviewEvent], range: TimeRange, now: Date, alignedTo tokensDomain: ClosedRange<Date>? = nil) {
        var bars: [Bar] = []
        var perks: [PerkMarker] = []
        for event in events {
            switch event.kind {
            case .limitReset:
                guard let unused = event.unusedPercent else {
                    continue
                }
                bars.append(Bar(
                    id: event.id,
                    app: event.app,
                    limitName: event.limitName ?? event.title,
                    date: event.date,
                    unusedPercent: min(max(unused, 0), 100)
                ))
            case .perkAvailable, .perkGone:
                perks.append(PerkMarker(id: event.id, app: event.app, title: event.title, detail: event.detail, date: event.date))
            case .limitAppeared, .limitDisappeared, .runningLow, .nearLimit, .trackingStarted:
                continue
            }
        }
        self.bars = bars.sorted { $0.date < $1.date }
        self.perks = perks.sorted { $0.date < $1.date }

        let oldest = (bars.map(\.date) + perks.map(\.date)).min()
        if let tokensDomain {
            // All time's token history can start after the first reset; the
            // chart still has to reach back to every mark it draws.
            let start = min(tokensDomain.lowerBound, oldest ?? tokensDomain.lowerBound)
            domain = start...tokensDomain.upperBound
        } else {
            let start = range.start(now: now) ?? oldest ?? now
            domain = min(start, now)...now
        }
    }

    /// The marks at the instant nearest `date`, if one is within 3% of the
    /// chart's span; further than that the pointer isn't on anything.
    public func moment(near date: Date) -> Moment? {
        let reach = domain.upperBound.timeIntervalSince(domain.lowerBound) * 0.03
        let dates = bars.map(\.date) + perks.map(\.date)
        guard let nearest = dates.min(by: { abs($0.timeIntervalSince(date)) < abs($1.timeIntervalSince(date)) }),
              abs(nearest.timeIntervalSince(date)) <= reach else {
            return nil
        }
        return Moment(
            date: nearest,
            bars: bars.filter { $0.date == nearest },
            perks: perks.filter { $0.date == nearest }
        )
    }
}
