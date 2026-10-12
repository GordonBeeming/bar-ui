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

    @Test("A Limit event keeps the name and Window it was recorded with after the Limit is renamed")
    func eventKeepsItsDescriptor() async throws {
        let folder = try TemporaryFolder()
        let archive = try Archive(url: folder.url.appendingPathComponent("Archive.sqlite"))
        let progress = ImportProgress(app: .claudeBar, fileName: "claudebar-metrics-2026-10-12.jsonl", byteOffset: 1, droppedRecords: 0)
        let before = LimitDescriptor(id: "weekly_scoped", name: "Weekly · Opus", windowDurationMinutes: 10080, modelID: "claude-opus-4-1")
        let after = LimitDescriptor(id: "weekly_scoped", name: "Weekly · Sonnet", windowDurationMinutes: 4320, modelID: "claude-sonnet-4-5")

        try await archive.record(TelemetryRecords(
            limitEvents: [LimitLifecycleEvent(app: .claudeBar, limit: before, kind: .appeared, timeUnixNano: t0)]
        ), progress: progress)
        try await archive.record(TelemetryRecords(
            limitSamples: [LimitSample(app: .claudeBar, limit: after, metric: .utilization, timeUnixNano: t0 + minute, value: 3)]
        ), progress: progress)

        #expect(try await archive.limitLifecycleEvents().map(\.limit) == [before])
        #expect(try await archive.currentLimits().map(\.limit) == [after])
    }

    @Test("An Archive whose Limit events were stored without their own name takes it from the Limit, and keeps it after a rename")
    func olderEventsTakeTheLimitsDescriptor() async throws {
        let folder = try TemporaryFolder()
        let url = folder.url.appendingPathComponent("Archive.sqlite")
        try execute("""
            CREATE TABLE limits (
                app TEXT NOT NULL, limit_id TEXT NOT NULL, name TEXT NOT NULL,
                window_minutes INTEGER, model_id TEXT, described_at INTEGER NOT NULL,
                PRIMARY KEY (app, limit_id)) WITHOUT ROWID;
            CREATE TABLE limit_events (
                app TEXT NOT NULL, limit_id TEXT NOT NULL, kind TEXT NOT NULL, time_unix_nano INTEGER NOT NULL,
                PRIMARY KEY (app, limit_id, kind, time_unix_nano)) WITHOUT ROWID;
            INSERT INTO limits VALUES ('claudeBar', 'session', 'Session (5h)', 300, NULL, \(t0));
            INSERT INTO limit_events VALUES ('claudeBar', 'session', 'appeared', \(t0));
            PRAGMA user_version = 1;
            """, at: url)

        let archive = try Archive(url: url)
        let renamed = LimitDescriptor(id: "session", name: "Session", windowDurationMinutes: 240, modelID: nil)
        try await archive.record(TelemetryRecords(
            limitSamples: [LimitSample(app: .claudeBar, limit: renamed, metric: .utilization, timeUnixNano: t0 + minute, value: 3)]
        ), progress: ImportProgress(app: .claudeBar, fileName: "claudebar-metrics-2026-10-12.jsonl", byteOffset: 1, droppedRecords: 0))
        let reopened = try Archive(url: url)

        let original = LimitDescriptor(id: "session", name: "Session (5h)", windowDurationMinutes: 300, modelID: nil)
        let events = try await reopened.limitLifecycleEvents()
        #expect(events.map(\.limit) == [original])
    }

    private func execute(_ sql: String, at url: URL) throws {
        var handle: OpaquePointer?
        guard sqlite3_open_v2(url.path, &handle, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nil) == SQLITE_OK, let handle else {
            throw ArchiveError(operation: "open the test Archive", message: "sqlite3_open_v2 failed", code: SQLITE_CANTOPEN)
        }
        defer { sqlite3_close(handle) }
        guard sqlite3_exec(handle, sql, nil, nil, nil) == SQLITE_OK else {
            throw ArchiveError(operation: "build the test Archive", message: String(cString: sqlite3_errmsg(handle)), code: SQLITE_ERROR)
        }
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
