import Foundation
import Testing
@testable import BarUICore

@Suite("Overview tokens")
@MainActor
struct OverviewTokensTests {
    @Test("Refreshing imports tokens, and the Overview reports usage for a range from the Archive")
    func refreshShowsUsage() async throws {
        let fixture = try ImportFixture()
        try fixture.copyFixture("claudebar-metrics-2026-10-12.jsonl", to: fixture.claudeFolder)
        try fixture.copyFixture("codexbar-metrics-2026-10-12.jsonl", to: fixture.codexFolder)
        let overview = LimitsOverview(archive: fixture.archive)
        let folder = { (url: URL) in
            BarAppStatus(state: .tracking, settings: TrackingSettings(enabled: true, intervalMinutes: 5, retentionDays: 90, folder: url))
        }

        await overview.refresh(statuses: [.claudeBar: folder(fixture.claudeFolder), .codexBar: folder(fixture.codexFolder)])

        let usage = overview.tokenUsage(range: .all, now: Date(timeIntervalSince1970: 1_791_791_460))
        #expect(usage.totalByApp == [.claudeBar: 575_292, .codexBar: 59_896])
    }
}
