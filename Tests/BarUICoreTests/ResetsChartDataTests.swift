import Foundation
import Testing
@testable import BarUICore

@Suite("Resets & Perks chart")
struct ResetsChartDataTests {
    private static let now = Date(timeIntervalSince1970: 1_792_000_000)
    private static let weekly = LimitDescriptor(id: "codex:10080", name: "Weekly", windowDurationMinutes: 10_080, modelID: nil)
    private static let session = LimitDescriptor(id: "session", name: "Session (5h)", windowDurationMinutes: 300, modelID: nil)

    private static func reset(_ limit: LimitDescriptor, app: BarApp, used: Double, hoursAgo: Double) -> LimitReset {
        LimitReset(
            app: app,
            limit: limit,
            timeUnixNano: Int64((now.timeIntervalSince1970 - hoursAgo * 3_600) * 1_000_000_000),
            utilizationLast: used,
            nextResetsAt: nil
        )
    }

    private static func timeline(resets: [LimitReset], gone: [GonePerk] = [], tracking: [TrackingStartedEvent] = []) -> [OverviewEvent] {
        let histories = Dictionary(grouping: resets) { "\($0.app.rawValue)/\($0.limit.id)" }.values.map { group in
            LimitHistory(app: group[0].app, limit: group[0].limit, utilization: [], latest: nil, resets: group)
        }
        return OverviewEvent.timeline(
            histories: histories,
            limitEvents: [],
            trackingStarts: tracking,
            perkAvailable: [],
            gonePerks: gone,
            locale: Locale(identifier: "en_US"),
            timeZone: TimeZone(identifier: "UTC") ?? .gmt
        )
    }

    @Test("A reset event carries how much went unused and which Limit it was")
    func resetCarriesUnusedAndLimit() throws {
        let events = Self.timeline(resets: [Self.reset(Self.weekly, app: .codexBar, used: 71.5, hoursAgo: 5)])

        let reset = try #require(events.first)
        #expect(reset.unusedPercent == 28.5)
        #expect(reset.limitName == "Weekly")
    }

    @Test("Resets become bars and Perk changes become markers; other events stay list-only")
    func barsAndMarkers() {
        let gone = GonePerk(
            app: .codexBar,
            kind: .resetCredit,
            currency: nil,
            quantity: 1,
            perkID: "a",
            expiresAt: Self.now.addingTimeInterval(-48 * 3_600),
            goneAt: Self.now.addingTimeInterval(-48 * 3_600),
            reason: .expired
        )
        let tracking = TrackingStartedEvent(app: .codexBar, intervalMinutes: 5, timeUnixNano: Int64((Self.now.timeIntervalSince1970 - 3_600) * 1_000_000_000))
        let events = Self.timeline(
            resets: [Self.reset(Self.weekly, app: .codexBar, used: 2, hoursAgo: 5)],
            gone: [gone],
            tracking: [tracking]
        )

        let data = ResetsChartData(events: events, range: .week, now: Self.now)

        #expect(data.bars.count == 1)
        #expect(data.bars.first?.unusedPercent == 98)
        #expect(data.bars.first?.app == .codexBar)
        #expect(data.bars.first?.limitName == "Weekly")
        #expect(data.perks.count == 1)
        #expect(data.perks.first?.date == gone.goneAt)
    }

    @Test("The chart spans the range, ending now, so it lines up with the Tokens chart")
    func domainIsTheRange() {
        let data = ResetsChartData(events: [], range: .week, now: Self.now)

        #expect(data.domain == Self.now.addingTimeInterval(-7 * 86_400)...Self.now)
        #expect(data.isEmpty)
    }

    @Test("All time spans from the oldest reset or Perk to now")
    func allTimeDomain() {
        let events = Self.timeline(resets: [Self.reset(Self.weekly, app: .codexBar, used: 50, hoursAgo: 400)])

        let data = ResetsChartData(events: events, range: .all, now: Self.now)

        #expect(data.domain.lowerBound == Self.now.addingTimeInterval(-400 * 3_600))
        #expect(data.domain.upperBound == Self.now)
    }

    @Test("Session resets the list hides aren't bars either")
    func hiddenSessionResets() {
        let events = Self.timeline(resets: [
            Self.reset(Self.session, app: .claudeBar, used: 10, hoursAgo: 3),
            Self.reset(Self.weekly, app: .codexBar, used: 2, hoursAgo: 5)
        ])

        let data = ResetsChartData(events: OverviewEvent.hidingShortWindowResets(events), range: .week, now: Self.now)

        #expect(data.bars.map(\.limitName) == ["Weekly"])
    }
}
