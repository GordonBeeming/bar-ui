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

    public let bars: [Bar]
    public let perks: [PerkMarker]
    /// The range, ending now, so the chart lines up with the Tokens chart;
    /// All time reaches back to the oldest thing drawn.
    public let domain: ClosedRange<Date>

    public var isEmpty: Bool {
        bars.isEmpty && perks.isEmpty
    }

    public init(events: [OverviewEvent], range: TimeRange, now: Date) {
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
        let start = range.start(now: now) ?? oldest ?? now
        domain = min(start, now)...now
    }
}
