import Foundation
import Testing
@testable import BarUICore

@Suite("Archive")
struct ArchiveTests {
    @Test("The current Limit is its latest utilisation and reset time")
    func currentLimits() async throws {
        let folder = try TemporaryFolder()
        let archive = try Archive(url: folder.url.appendingPathComponent("Archive.sqlite"))
        let session = LimitDescriptor(id: "session", name: "Session (5h)", windowDurationMinutes: 300, modelID: nil)

        try await archive.record(TelemetryRecords(limitSamples: [
            LimitSample(app: .claudeBar, limit: session, metric: .utilization, timeUnixNano: 1_000_000_000, value: 40),
            LimitSample(app: .claudeBar, limit: session, metric: .resetsAt, timeUnixNano: 1_000_000_000, value: 5_000),
            LimitSample(app: .claudeBar, limit: session, metric: .utilization, timeUnixNano: 2_000_000_000, value: 42),
            LimitSample(app: .claudeBar, limit: session, metric: .resetsAt, timeUnixNano: 2_000_000_000, value: 6_000)
        ]), progress: ImportProgress(app: .claudeBar, fileName: "claudebar-metrics-2026-10-12.jsonl", byteOffset: 10, droppedRecords: 0))

        let limits = try await archive.currentLimits()

        #expect(limits == [
            CurrentLimit(
                app: .claudeBar,
                limit: session,
                utilization: 42,
                sampledAt: Date(timeIntervalSince1970: 2),
                resetsAt: Date(timeIntervalSince1970: 6_000)
            )
        ])
    }

    @Test("Limits are keyed by limit.id, so a renamed Limit stays one Limit under its latest name")
    func renamedLimit() async throws {
        let folder = try TemporaryFolder()
        let archive = try Archive(url: folder.url.appendingPathComponent("Archive.sqlite"))
        let before = LimitDescriptor(id: "codex:10080", name: "Primary", windowDurationMinutes: 10080, modelID: nil)
        let after = LimitDescriptor(id: "codex:10080", name: "Weekly", windowDurationMinutes: 10080, modelID: nil)
        let progress = ImportProgress(app: .codexBar, fileName: "codexbar-metrics-2026-10-12.jsonl", byteOffset: 1, droppedRecords: 0)

        // Newer first: a later import of an older file must not undo the rename.
        try await archive.record(TelemetryRecords(limitSamples: [LimitSample(app: .codexBar, limit: after, metric: .utilization, timeUnixNano: 2, value: 5)]), progress: progress)
        try await archive.record(TelemetryRecords(limitSamples: [LimitSample(app: .codexBar, limit: before, metric: .utilization, timeUnixNano: 1, value: 4)]), progress: progress)

        let limits = try await archive.currentLimits()

        #expect(limits.map(\.limit.name) == ["Weekly"])
        #expect(limits.map(\.utilization) == [5])
    }

    @Test("Recording the same samples twice keeps one copy of each")
    func idempotent() async throws {
        let folder = try TemporaryFolder()
        let archive = try Archive(url: folder.url.appendingPathComponent("Archive.sqlite"))
        let weekly = LimitDescriptor(id: "codex:10080", name: "Weekly", windowDurationMinutes: 10080, modelID: nil)
        let samples = [
            LimitSample(app: .codexBar, limit: weekly, metric: .utilization, timeUnixNano: 1, value: 3),
            LimitSample(app: .codexBar, limit: weekly, metric: .utilization, timeUnixNano: 2, value: 4)
        ]
        let progress = ImportProgress(app: .codexBar, fileName: "codexbar-metrics-2026-10-12.jsonl", byteOffset: 1, droppedRecords: 0)

        try await archive.record(TelemetryRecords(limitSamples: samples), progress: progress)
        try await archive.record(TelemetryRecords(limitSamples: samples), progress: progress)

        let history = try await archive.samples(of: .codexBar, limitID: "codex:10080", metric: .utilization)
        #expect(history.map(\.value) == [3, 4])
    }

    @Test("What was recorded is still there after the Archive is closed and opened again")
    func persists() async throws {
        let folder = try TemporaryFolder()
        let url = folder.url.appendingPathComponent("nested/Archive.sqlite")
        let weekly = LimitDescriptor(id: "codex:10080", name: "Weekly", windowDurationMinutes: nil, modelID: nil)
        do {
            let archive = try Archive(url: url)
            try await archive.record(
                TelemetryRecords(limitSamples: [LimitSample(app: .codexBar, limit: weekly, metric: .utilization, timeUnixNano: 1, value: 3)]),
                progress: ImportProgress(app: .codexBar, fileName: "codexbar-metrics-2026-10-12.jsonl", byteOffset: 77, droppedRecords: 2)
            )
        }

        let reopened = try Archive(url: url)

        #expect(try await reopened.currentLimits().map(\.limit) == [weekly])
        let progress = try await reopened.progress(of: .codexBar, fileName: "codexbar-metrics-2026-10-12.jsonl")
        #expect(progress?.byteOffset == 77)
        #expect(progress?.droppedRecords == 2)
    }
}

/// A folder under the system temp directory that is removed when the test
/// lets go of it, so no test leaves files behind.
final class TemporaryFolder {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("BarUICoreTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }
}
