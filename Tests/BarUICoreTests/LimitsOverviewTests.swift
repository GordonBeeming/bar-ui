import Foundation
import Testing
@testable import BarUICore

@Suite("Overview Limits")
@MainActor
struct LimitsOverviewTests {
    private static let now = Date(timeIntervalSince1970: 1_791_791_400)

    private static func status(_ state: TrackingState, folder: URL) -> BarAppStatus {
        BarAppStatus(state: state, settings: TrackingSettings(enabled: state == .tracking, intervalMinutes: 5, retentionDays: 90, folder: folder))
    }

    @Test("Refreshing imports every Bar App's Telemetry Folder and shows a card per Limit")
    func refreshShowsCards() async throws {
        let fixture = try ImportFixture()
        try fixture.copyFixture("claudebar-metrics-2026-10-12.jsonl", to: fixture.claudeFolder)
        try fixture.copyFixture("codexbar-metrics-2026-10-12.jsonl", to: fixture.codexFolder)
        let overview = LimitsOverview(archive: fixture.archive)

        await overview.refresh(statuses: [
            .claudeBar: Self.status(.tracking, folder: fixture.claudeFolder),
            .codexBar: Self.status(.tracking, folder: fixture.codexFolder)
        ])

        let cards = overview.cards(now: Self.now)
        #expect(cards.map(\.id) == [
            "claudeBar/session",
            "claudeBar/weekly_all",
            "claudeBar/weekly_scoped:claude-opus-4-1",
            "codexBar/codex:10080"
        ])
        #expect(cards.first?.resetText == "Resets in 1h 20m")
        #expect(overview.problem == nil)
    }

    @Test("History is imported while Tracking is off, so it reaches the Archive before retention deletes it")
    func historyIsArchived() async throws {
        let fixture = try ImportFixture()
        let file = try fixture.copyFixture("codexbar-metrics-2026-10-12.jsonl", to: fixture.codexFolder)
        let overview = LimitsOverview(archive: fixture.archive)

        await overview.refresh(statuses: [.codexBar: Self.status(.offWithHistory, folder: fixture.codexFolder)])
        try FileManager.default.removeItem(at: file)
        await overview.refresh(statuses: [.codexBar: Self.status(.tracking, folder: fixture.codexFolder)])

        #expect(overview.cards(now: Self.now).map(\.percentUsed) == [19])
    }
}
