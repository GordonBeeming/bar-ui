import Foundation
import Testing
@testable import BarUICore

@Suite("Importing reset events into the Archive")
struct ResetImportTests {
    @Test("Logs files give every Limit its resets, alongside the samples from metrics files")
    func importsResets() async throws {
        let fixture = try ImportFixture()
        try fixture.copyFixture("claudebar-metrics-2026-10-12.jsonl", to: fixture.claudeFolder)
        try fixture.copyFixture("claudebar-logs-2026-10-12.jsonl", to: fixture.claudeFolder)

        let summary = try await fixture.importer.importMetrics(of: .claudeBar, from: fixture.claudeFolder)

        #expect(summary.resetsRead == 3)
        #expect(summary.droppedRecords == 0)
        let histories = try await fixture.archive.limitHistories(of: .claudeBar, since: nil)
        let session = try #require(histories.first { $0.limit.id == "session" })
        #expect(session.resets.map(\.utilizationLast) == [30, 71.5])
        #expect(session.utilization.map(\.value) == [40, 42])
        let weekly = try #require(histories.first { $0.limit.id == "weekly_all" })
        #expect(weekly.resets.map(\.utilizationLast) == [88])
    }

    @Test("Importing the same logs again adds no resets")
    func reimportDoesNotDuplicate() async throws {
        let fixture = try ImportFixture()
        try fixture.copyFixture("codexbar-logs-2026-10-12.jsonl", to: fixture.codexFolder)

        _ = try await fixture.importer.importMetrics(of: .codexBar, from: fixture.codexFolder)
        let again = try await fixture.importer.importMetrics(of: .codexBar, from: fixture.codexFolder)

        #expect(again.resetsRead == 0)
        let histories = try await fixture.archive.limitHistories(of: .codexBar, since: nil)
        #expect(histories.map(\.resets.count) == [1])
    }

    @Test("A Limit seen only in a reset event still appears, and a range keeps only what falls inside it")
    func rangeAndEventOnlyLimit() async throws {
        let fixture = try ImportFixture()
        try fixture.copyFixture("codexbar-logs-2026-10-12.jsonl", to: fixture.codexFolder)
        _ = try await fixture.importer.importMetrics(of: .codexBar, from: fixture.codexFolder)

        let all = try await fixture.archive.limitHistories(of: .codexBar, since: nil)
        let later = try await fixture.archive.limitHistories(of: .codexBar, since: Date(timeIntervalSince1970: 1_791_800_000))

        #expect(all.map(\.limit.id) == ["codex:10080"])
        #expect(later.map(\.limit.id) == ["codex:10080"])
        #expect(later.first?.resets.isEmpty == true)
    }

    @Test("All of a Bar App's resets are readable by Limit, whatever range a chart shows")
    func allResetsByLimit() async throws {
        let fixture = try ImportFixture()
        try fixture.copyFixture("codexbar-logs-2026-10-12.jsonl", to: fixture.codexFolder)
        _ = try await fixture.importer.importMetrics(of: .codexBar, from: fixture.codexFolder)

        let inRange = try await fixture.archive.limitHistories(of: .codexBar, since: nil).first?.resets ?? []
        let byLimit = try await fixture.archive.limitResets(of: .codexBar)

        #expect(!inRange.isEmpty)
        #expect(byLimit["codex:10080"]?.map(\.timeUnixNano) == inRange.map(\.timeUnixNano))
    }

    @Test("Resets survive the Bar App deleting its files")
    func survivesDeletedFiles() async throws {
        let fixture = try ImportFixture()
        let file = try fixture.copyFixture("codexbar-logs-2026-10-12.jsonl", to: fixture.codexFolder)
        _ = try await fixture.importer.importMetrics(of: .codexBar, from: fixture.codexFolder)

        try FileManager.default.removeItem(at: file)
        _ = try await fixture.importer.importMetrics(of: .codexBar, from: fixture.codexFolder)

        let histories = try await fixture.archive.limitHistories(of: .codexBar, since: nil)
        #expect(histories.first?.resets.map(\.utilizationLast) == [12])
    }

    @Test("The latest utilisation is reported even when the range holds no samples")
    func latestOutsideRange() async throws {
        let fixture = try ImportFixture()
        try fixture.copyFixture("codexbar-metrics-2026-10-12.jsonl", to: fixture.codexFolder)
        _ = try await fixture.importer.importMetrics(of: .codexBar, from: fixture.codexFolder)

        let histories = try await fixture.archive.limitHistories(of: .codexBar, since: Date(timeIntervalSince1970: 1_800_000_000))

        #expect(histories.first?.utilization.isEmpty == true)
        #expect(histories.first?.latest?.value == 18.5)
    }
}
