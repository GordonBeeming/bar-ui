import Foundation
import Testing
@testable import BarUICore

@MainActor
@Suite("Limit history on a Bar App's page")
struct LimitHistoryModelTests {
    /// The fixtures' newest sample is 1791791400, a little after the resets.
    private static let now = Date(timeIntervalSince1970: 1_791_791_400)

    @Test("Every Limit in the Archive gets a row with its history, fixture resets included")
    func loadsEveryLimit() async throws {
        let fixture = try ImportFixture()
        try fixture.copyFixture("claudebar-metrics-2026-10-12.jsonl", to: fixture.claudeFolder)
        try fixture.copyFixture("claudebar-logs-2026-10-12.jsonl", to: fixture.claudeFolder)
        _ = try await fixture.importer.importMetrics(of: .claudeBar, from: fixture.claudeFolder)
        let model = LimitHistoryModel(archive: fixture.archive)

        await model.load(app: .claudeBar, range: .all, now: Self.now)

        #expect(model.rows.map(\.limitID) == ["session", "weekly_all", "weekly_scoped:claude-opus-4-1"])
        let session = try #require(model.rows.first)
        #expect(session.resetMarkers.map(\.unusedPercent) == [70, 28.5])
        #expect(session.unusedAtLastReset == 28.5)
        #expect(session.averageUnusedAtReset == 49.25)
        #expect(session.percentUsedNow == 42)
        #expect(model.problem == nil)
    }

    @Test("A range keeps only the resets inside it")
    func rangeFiltersResets() async throws {
        let fixture = try ImportFixture()
        try fixture.copyFixture("claudebar-logs-2026-10-12.jsonl", to: fixture.claudeFolder)
        _ = try await fixture.importer.importMetrics(of: .claudeBar, from: fixture.claudeFolder)
        let model = LimitHistoryModel(archive: fixture.archive)

        // The weekly reset is a day and a half before the fixtures' newest sample.
        await model.load(app: .claudeBar, range: .day, now: Self.now)

        let weekly = try #require(model.rows.first { $0.limitID == "weekly_all" })
        #expect(weekly.resetMarkers.isEmpty)
        let session = try #require(model.rows.first { $0.limitID == "session" })
        #expect(session.resetMarkers.count == 2)
    }

    @Test("A Bar App with nothing archived has no rows and no problem")
    func nothingArchived() async throws {
        let fixture = try ImportFixture()
        let model = LimitHistoryModel(archive: fixture.archive)
        await model.load(app: .codexBar, range: .all, now: Self.now)

        #expect(model.rows.isEmpty)
        #expect(model.problem == nil)
    }
}
