import Foundation
import Testing
@testable import BarUICore

@MainActor
@Suite("Menu Bar Preview")
struct MenuBarPreviewTests {
    /// The fixtures' newest sample; the one before it is five minutes earlier.
    private static let now = Date(timeIntervalSince1970: 1_791_791_400)

    private static func status(_ state: TrackingState, folder: URL) -> BarAppStatus {
        BarAppStatus(state: state, settings: TrackingSettings(enabled: state == .tracking, intervalMinutes: 5, retentionDays: 90, folder: folder))
    }

    @Test("Each Limit shows its Burn Rate, and a projection only when 100% comes before the reset")
    func fixtureRows() async throws {
        let fixture = try ImportFixture()
        try fixture.copyFixture("claudebar-metrics-2026-10-12.jsonl", to: fixture.claudeFolder)
        let preview = MenuBarPreview(archive: fixture.archive, overview: LimitsOverview(archive: fixture.archive))

        await preview.refresh(statuses: [.claudeBar: Self.status(.tracking, folder: fixture.claudeFolder)], now: Self.now)

        let rows = Dictionary(uniqueKeysWithValues: preview.rows.map { ($0.id, $0) })
        #expect(preview.rows.map(\.id) == ["claudeBar/session", "claudeBar/weekly_all", "claudeBar/weekly_scoped:claude-opus-4-1"])

        // 40% to 42% in five minutes is 24 points an hour: 100% is 2h25m away
        // but the Window resets in 1h20m.
        let session = try #require(rows["claudeBar/session"])
        #expect(session.percentUsed == 42)
        #expect(session.burnRateText == "24 pts/h")
        #expect(session.projectionText == nil)
        #expect(session.isBurnRateHighlighted == false)
        #expect(session.resetText == "Resets in 1h 20m")

        // 60% to 61% is 12 an hour, so 100% is 3h15m away; the week has two days left.
        let weekly = try #require(rows["claudeBar/weekly_all"])
        #expect(weekly.burnRateText == "12 pts/h")
        #expect(weekly.projectionText == "At this rate it hits 100% in 3h 15m")
        #expect(weekly.isBurnRateHighlighted)

        #expect(preview.problem == nil)
    }

    @Test("Right after a reset there is no Burn Rate yet, and nothing carries over from before it")
    func justAfterAReset() async throws {
        let fixture = try ImportFixture()
        let session = LimitDescriptor(id: "session", name: "Session (5h)", windowDurationMinutes: 300, modelID: nil)
        let nano: (Int) -> Int64 = { 1_791_791_400_000_000_000 + Int64($0) * 60 * 1_000_000_000 }
        func sample(_ minutes: Int, _ metric: LimitMetric, _ value: Double) -> LimitSample {
            LimitSample(app: .claudeBar, limit: session, metric: metric, timeUnixNano: nano(minutes), value: value)
        }
        try await fixture.archive.record(
            [
                sample(-50, .utilization, 80), sample(-40, .utilization, 95), sample(-1, .utilization, 2),
                sample(-1, .resetsAt, Self.now.timeIntervalSince1970 + 5 * 3_600)
            ],
            resets: [LimitReset(app: .claudeBar, limit: session, timeUnixNano: nano(-2), utilizationLast: 95, nextResetsAt: nil)],
            progress: ImportProgress(app: .claudeBar, fileName: "x.jsonl", byteOffset: 1, droppedRecords: 0)
        )
        let overview = LimitsOverview(archive: fixture.archive)
        let preview = MenuBarPreview(archive: fixture.archive, overview: overview)

        await preview.refresh(statuses: [.claudeBar: Self.status(.tracking, folder: fixture.claudeFolder)], now: Self.now)

        let row = try #require(preview.rows.first)
        #expect(row.percentUsed == 2)
        #expect(row.burnRateText == "Not enough data yet")
        #expect(row.projectionText == nil)
    }

    @Test("Tokens come from the Archive: the last 24 hours, and their pace")
    func tokens() async throws {
        let fixture = try ImportFixture()
        try fixture.copyFixture("claudebar-metrics-2026-10-12.jsonl", to: fixture.claudeFolder)
        let overview = LimitsOverview(archive: fixture.archive)
        let preview = MenuBarPreview(archive: fixture.archive, overview: overview)

        await preview.refresh(statuses: [.claudeBar: Self.status(.tracking, folder: fixture.claudeFolder)], now: Self.now)

        let usage = preview.tokenUsage(now: Self.now)
        #expect(usage.total == overview.tokenUsage(range: .day, now: Self.now).total)
        #expect(usage.total > 0)
        #expect(preview.pace(now: Self.now).perHourAverage == Double(usage.total) / 24)
    }
}
