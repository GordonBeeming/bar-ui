import Foundation
import Observation

/// What the Menu Bar Preview shows, read out of the Archive: the last day's
/// tokens, and each Window's Burn Rate.
@MainActor
@Observable
public final class MenuBarPreview {
    public private(set) var rows: [MenuBarLimitRow] = []
    public private(set) var problem: String?

    private let archive: Archive
    private let overview: LimitsOverview

    public init(archive: Archive, overview: LimitsOverview) {
        self.archive = archive
        self.overview = overview
    }

    public func tokenUsage(now: Date, calendar: Calendar = .current) -> TokenUsage {
        overview.tokenUsage(range: .day, now: now, calendar: calendar)
    }

    public func pace(now: Date, calendar: Calendar = .current) -> TokenPace {
        TokenPace(samples: overview.tokenSamples, now: now, calendar: calendar)
    }

    /// Imports through the shared overview first, so the panel never shows
    /// older data than the window would, even when the window is closed.
    public func refresh(statuses: [BarApp: BarAppStatus], now: Date) async {
        await overview.refresh(statuses: statuses)
        await reload(now: now)
    }

    public func reload(now: Date) async {
        let cards = overview.cards(now: now)
        var burnRates: [String: BurnRate] = [:]
        var problems: [String] = []
        for app in Set(cards.map(\.app)) {
            do {
                let histories = try await archive.limitHistories(of: app, since: now.addingTimeInterval(-BurnRate.lookback))
                for history in histories {
                    burnRates["\(app.rawValue)/\(history.limit.id)"] = BurnRate(
                        samples: history.utilization,
                        resetTimes: history.resets.map { Date(unixNano: $0.timeUnixNano) },
                        now: now
                    )
                }
            } catch {
                // That app's rows still show their usage, just without a rate.
                problems.append("\(app.displayName): \(error.localizedDescription)")
            }
        }
        rows = cards.map { MenuBarLimitRow(card: $0, burnRate: burnRates[$0.id], now: now) }
        problem = problems.isEmpty ? nil : problems.joined(separator: "\n")
    }
}
