import Foundation
import SQLite3
import Testing
@testable import BarUICore

@Suite("Tracking, Limit and Perk-available events in the Archive")
struct LifecycleEventArchiveTests {
    private let t0: Int64 = 1_791_791_100_000_000_000
    private let minute: Int64 = 60_000_000_000

    private func writeEvents(to fixture: ImportFixture) throws {
        try fixture.write(
            LifecycleEventLine.logs(service: "claudebar", events: [
                .tracking(minutes: 5, time: t0),
                .limit("bar.limit.appeared", id: "session", name: "Session (5h)", minutes: 300, time: t0 + minute),
                .limit("bar.limit.disappeared", id: "old", name: "Old limit", minutes: nil, time: t0 + 2 * minute),
                .perk("bar.perk.available", kind: "guest_pass", quantity: 2, expiresAt: 1_792_000_000, time: t0 + 3 * minute)
            ]),
            named: "claudebar-logs-2026-10-12.jsonl", in: fixture.claudeFolder
        )
    }

    @Test("Imported events can be read back, each with its Bar App")
    func storesAndReadsBack() async throws {
        let fixture = try ImportFixture()
        try writeEvents(to: fixture)

        _ = try await fixture.importer.importMetrics(of: .claudeBar, from: fixture.claudeFolder)

        let archive = fixture.archive
        #expect(try await archive.trackingStarts() == [TrackingStartedEvent(app: .claudeBar, intervalMinutes: 5, timeUnixNano: t0)])
        let limitEvents = try await archive.limitLifecycleEvents()
        #expect(limitEvents.map(\.kind) == [.appeared, .disappeared])
        #expect(limitEvents.map(\.limit.name) == ["Session (5h)", "Old limit"])
        #expect(limitEvents.first?.limit.windowDurationMinutes == 300)
        let perks = try await archive.perkAvailableEvents()
        #expect(perks.map(\.kind) == [.guestPass])
        #expect(perks.first?.quantity == 2)
        #expect(perks.first?.expiresAt == 1_792_000_000)
    }

    @Test("Opening a version 1 Archive again keeps its logs files' read positions and skipped-record counts")
    func reopeningKeepsLogsProgress() async throws {
        let fixture = try ImportFixture()
        var logs = LifecycleEventLine.logs(service: "claudebar", events: [.tracking(minutes: 5, time: t0)])
        logs.append(Data("not a Telemetry line\n".utf8))
        try fixture.write(logs, named: "claudebar-logs-2026-10-12.jsonl", in: fixture.claudeFolder)
        _ = try await fixture.importer.importMetrics(of: .claudeBar, from: fixture.claudeFolder)
        let before = try await fixture.archive.progress(of: .claudeBar, fileName: "claudebar-logs-2026-10-12.jsonl")
        try markArchiveAsVersion(1, at: fixture.archiveURL)

        let reopened = try Archive(url: fixture.archiveURL)

        let after = try await reopened.progress(of: .claudeBar, fileName: "claudebar-logs-2026-10-12.jsonl")
        #expect(before?.droppedRecords == 1)
        #expect(after == before)
        #expect(try await reopened.skippedRecords(of: .claudeBar).map(\.count) == [1])
        #expect(try await TelemetryImporter(archive: reopened).importMetrics(of: .claudeBar, from: fixture.claudeFolder).filesRead == 0)
    }

    @Test("An Archive already at the current version keeps its progress")
    func currentArchiveKeepsProgress() async throws {
        let fixture = try ImportFixture()
        try writeEvents(to: fixture)
        _ = try await fixture.importer.importMetrics(of: .claudeBar, from: fixture.claudeFolder)

        let reopened = try Archive(url: fixture.archiveURL)

        #expect(try await reopened.progress(of: .claudeBar, fileName: "claudebar-logs-2026-10-12.jsonl") != nil)
    }

    private func markArchiveAsVersion(_ version: Int, at url: URL) throws {
        var handle: OpaquePointer?
        guard sqlite3_open_v2(url.path, &handle, SQLITE_OPEN_READWRITE, nil) == SQLITE_OK, let handle else {
            throw ArchiveError(operation: "open the test Archive", message: "sqlite3_open_v2 failed", code: SQLITE_CANTOPEN)
        }
        defer { sqlite3_close(handle) }
        guard sqlite3_exec(handle, "PRAGMA user_version = \(version)", nil, nil, nil) == SQLITE_OK else {
            throw ArchiveError(operation: "set the test Archive's version", message: String(cString: sqlite3_errmsg(handle)), code: SQLITE_ERROR)
        }
    }
}
