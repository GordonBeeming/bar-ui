import Foundation
import Testing
@testable import BarUICore

@Suite("Overview events by range and relative time")
@MainActor
struct OverviewEventsRangeTests {
    private static let second: Int64 = 1_000_000_000
    private static let now = Date(timeIntervalSince1970: 1_791_791_400)
    private static let nowNano = 1_791_791_400 * second
    private static let hour = 3_600 * second
    private static let day = 24 * hour

    private static func status(_ state: TrackingState, folder: URL) -> BarAppStatus {
        BarAppStatus(state: state, settings: TrackingSettings(enabled: state == .tracking, intervalMinutes: 5, retentionDays: 90, folder: folder))
    }

    private func event(at nano: Int64) -> OverviewEvent {
        OverviewEvent(id: "\(nano)", app: .claudeBar, kind: .trackingStarted, title: "Tracking started", detail: "", date: Date(unixNano: nano))
    }

    @Test("Each range keeps what falls inside it, and All time keeps everything up to now")
    func rangeFilter() {
        let events = [
            event(at: Self.nowNano - 2 * Self.hour),
            event(at: Self.nowNano - 3 * Self.day),
            event(at: Self.nowNano - 20 * Self.day),
            event(at: Self.nowNano - 100 * Self.day),
            event(at: Self.nowNano + Self.hour)
        ]

        func count(_ range: TokenRange) -> Int {
            OverviewEvent.within(events, range: range, now: Self.now).count
        }

        #expect(count(.day) == 1)
        #expect(count(.week) == 2)
        #expect(count(.month) == 3)
        #expect(count(.all) == 4)
    }

    @Test("Relative time reads like a person would say it")
    func relativeTime() {
        let locale = Locale(identifier: "en_US")

        #expect(event(at: Self.nowNano - 20 * Self.second).relativeTime(now: Self.now, locale: locale) == "Just now")
        #expect(event(at: Self.nowNano - 5 * 60 * Self.second).relativeTime(now: Self.now, locale: locale) == "5 minutes ago")
        #expect(event(at: Self.nowNano - 3 * Self.day).relativeTime(now: Self.now, locale: locale) == "3 days ago")
    }

    @Test("Refreshing merges both Bar Apps' events, and the Overview lists the ones in the chosen range")
    func overviewListsEvents() async throws {
        let fixture = try ImportFixture()
        let old = Self.nowNano - 20 * Self.day
        let recent = Self.nowNano - 2 * Self.hour
        try fixture.write(
            LifecycleEventLine.logs(service: "claudebar", events: [
                .tracking(minutes: 5, time: old),
                .limit("bar.limit.appeared", id: "session", name: "Session (5h)", minutes: 300, time: recent)
            ]),
            named: "claudebar-logs-2026-10-12.jsonl", in: fixture.claudeFolder
        )
        try fixture.write(
            LifecycleEventLine.logs(service: "codexbar", events: [.tracking(minutes: 10, time: recent + Self.hour)]),
            named: "codexbar-logs-2026-10-12.jsonl", in: fixture.codexFolder
        )
        let overview = LimitsOverview(archive: fixture.archive)

        await overview.refresh(statuses: [
            .claudeBar: Self.status(.tracking, folder: fixture.claudeFolder),
            .codexBar: Self.status(.tracking, folder: fixture.codexFolder)
        ])

        let week = overview.events(range: .week, now: Self.now)
        #expect(week.map(\.title) == ["Tracking started", "Session (5h) appeared"])
        #expect(week.map(\.app) == [.codexBar, .claudeBar])
        let month = overview.events(range: .month, now: Self.now)
        #expect(month.map(\.title) == ["Tracking started", "Session (5h) appeared", "Tracking started"])
        #expect(overview.problem == nil)
    }
}
