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
        #expect(session.burnRateText == "+24%/h")
        #expect(session.projectionText == nil)
        #expect(session.isBurnRateHighlighted == false)
        #expect(session.resetText == "Resets in 1h 20m")

        // 60% to 61% is 12 an hour, but five minutes of a week is too short a
        // sample to warn on; the rate still shows.
        let weekly = try #require(rows["claudeBar/weekly_all"])
        #expect(weekly.burnRateText == "+12%/h")
        #expect(weekly.projectionText == nil)
        #expect(weekly.isBurnRateHighlighted == false)

        #expect(preview.problem == nil)
    }

    @Test("A weekly Limit that has climbed steadily for most of a day warns that it will run out first")
    func sustainedWeeklyPace() async throws {
        let fixture = try ImportFixture()
        let weekly = LimitDescriptor(id: "weekly_all", name: "Weekly (all models)", windowDurationMinutes: 10_080, modelID: nil)
        let nano: (Int) -> Int64 = { 1_791_791_400_000_000_000 + Int64($0) * 60 * 1_000_000_000 }
        func sample(_ minutes: Int, _ metric: LimitMetric, _ value: Double) -> LimitSample {
            LimitSample(app: .claudeBar, limit: weekly, metric: metric, timeUnixNano: nano(minutes), value: value)
        }
        // 40% to 60% over ten hours is 2 points an hour: 100% in 20 hours,
        // before the reset in two days. Ten hours covers more than half of the
        // 16.8 hour pace lookback a week gets.
        try await fixture.archive.record(
            TelemetryRecords(limitSamples: [
                sample(-600, .utilization, 40), sample(-300, .utilization, 50), sample(0, .utilization, 60),
                sample(0, .resetsAt, Self.now.timeIntervalSince1970 + 2 * 86_400)
            ]),
            progress: ImportProgress(app: .claudeBar, fileName: "x.jsonl", byteOffset: 1, droppedRecords: 0)
        )
        let preview = MenuBarPreview(archive: fixture.archive, overview: LimitsOverview(archive: fixture.archive))

        await preview.refresh(statuses: [.claudeBar: Self.status(.tracking, folder: fixture.claudeFolder)], now: Self.now)

        let row = try #require(preview.rows.first)
        #expect(row.projectionText == "On pace to run out in 20h, before it resets")
        #expect(row.isBurnRateHighlighted)
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
            TelemetryRecords(
                limitSamples: [
                sample(-50, .utilization, 80), sample(-40, .utilization, 95), sample(-1, .utilization, 2),
                sample(-1, .resetsAt, Self.now.timeIntervalSince1970 + 5 * 3_600)
            ],
            resets: [LimitReset(app: .claudeBar, limit: session, timeUnixNano: nano(-2), utilizationLast: 95, nextResetsAt: nil)]),
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

    @Test("Under 5% used there is too little change to warn about the pace, though the rate still shows")
    func noPaceWarningUnderFivePercent() async throws {
        let fixture = try ImportFixture()
        let session = LimitDescriptor(id: "session", name: "Session (5h)", windowDurationMinutes: 300, modelID: nil)
        let nano: (Int) -> Int64 = { 1_791_791_400_000_000_000 + Int64($0) * 60 * 1_000_000_000 }
        func sample(_ minutes: Int, _ metric: LimitMetric, _ value: Double) -> LimitSample {
            LimitSample(app: .claudeBar, limit: session, metric: metric, timeUnixNano: nano(minutes), value: value)
        }
        // 1% to 3% in five minutes is 24 points an hour, so 100% would come
        // in about 4 hours, before the reset in 5.
        try await fixture.archive.record(
            TelemetryRecords(limitSamples: [
                sample(-5, .utilization, 1), sample(0, .utilization, 3),
                sample(0, .resetsAt, Self.now.timeIntervalSince1970 + 5 * 3_600)
            ]),
            progress: ImportProgress(app: .claudeBar, fileName: "x.jsonl", byteOffset: 1, droppedRecords: 0)
        )
        let preview = MenuBarPreview(archive: fixture.archive, overview: LimitsOverview(archive: fixture.archive))

        await preview.refresh(statuses: [.claudeBar: Self.status(.tracking, folder: fixture.claudeFolder)], now: Self.now)

        let row = try #require(preview.rows.first)
        #expect(row.percentUsed == 3)
        #expect(row.burnRateText == "+24%/h")
        #expect(row.projectionText == nil)
        #expect(row.isBurnRateHighlighted == false)
    }

    @Test("Tokens come from the Archive: the last 24 hours, and their pace")
    func tokens() async throws {
        let fixture = try ImportFixture()
        try fixture.copyFixture("claudebar-metrics-2026-10-12.jsonl", to: fixture.claudeFolder)
        let overview = LimitsOverview(archive: fixture.archive, now: { Self.now })
        let preview = MenuBarPreview(archive: fixture.archive, overview: overview)

        await preview.refresh(statuses: [.claudeBar: Self.status(.tracking, folder: fixture.claudeFolder)], now: Self.now)

        let usage = preview.tokenUsage(now: Self.now)
        #expect(usage.total == overview.tokenUsage(range: .day, now: Self.now).total)
        #expect(usage.total > 0)
        #expect(preview.pace(now: Self.now).perHourAverage == Double(usage.total) / 24)
    }
}
