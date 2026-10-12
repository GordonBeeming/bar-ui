import Foundation
import Testing
@testable import BarUICore

@Suite("Importing Telemetry into the Archive")
struct TelemetryImporterTests {
    @Test("Each Bar App's metrics files land in the Archive as current Limits")
    func importsBothBarApps() async throws {
        let fixture = try ImportFixture()
        try fixture.copyFixture("claudebar-metrics-2026-10-12.jsonl", to: fixture.claudeFolder)
        try fixture.copyFixture("codexbar-metrics-2026-10-12.jsonl", to: fixture.codexFolder)

        let claude = try await fixture.importer.importMetrics(of: .claudeBar, from: fixture.claudeFolder)
        let codex = try await fixture.importer.importMetrics(of: .codexBar, from: fixture.codexFolder)

        #expect(claude.samplesRead == 12)
        #expect(codex.samplesRead == 4)
        let limits = try await fixture.archive.currentLimits()
        #expect(limits.map { "\($0.app.rawValue)/\($0.limit.id)=\($0.utilization)" }.sorted() == [
            "claudeBar/session=42.0",
            "claudeBar/weekly_all=61.0",
            "claudeBar/weekly_scoped:claude-opus-4-1=82.0",
            "codexBar/codex:10080=18.5"
        ])
    }

    @Test("Limits stay in the Archive after the Bar App deletes its files")
    func survivesDeletedFiles() async throws {
        let fixture = try ImportFixture()
        let file = try fixture.copyFixture("codexbar-metrics-2026-10-12.jsonl", to: fixture.codexFolder)
        _ = try await fixture.importer.importMetrics(of: .codexBar, from: fixture.codexFolder)

        try FileManager.default.removeItem(at: file)
        _ = try await fixture.importer.importMetrics(of: .codexBar, from: fixture.codexFolder)
        let reopened = try Archive(url: fixture.archiveURL)

        let limits = try await reopened.currentLimits()
        #expect(limits.map(\.limit.id) == ["codex:10080"])
        #expect(limits.map(\.utilization) == [18.5])
    }

    @Test("Importing the same file again adds no samples")
    func reimportDoesNotDuplicate() async throws {
        let fixture = try ImportFixture()
        try fixture.copyFixture("codexbar-metrics-2026-10-12.jsonl", to: fixture.codexFolder)

        _ = try await fixture.importer.importMetrics(of: .codexBar, from: fixture.codexFolder)
        let again = try await fixture.importer.importMetrics(of: .codexBar, from: fixture.codexFolder)

        #expect(again.samplesRead == 0)
        let history = try await fixture.archive.samples(of: .codexBar, limitID: "codex:10080", metric: .utilization)
        #expect(history.map(\.value) == [17, 18.5])
    }

    @Test("A file that shrank is read again from the start without duplicating samples")
    func shrunkFileDoesNotDuplicate() async throws {
        let fixture = try ImportFixture()
        let file = try fixture.copyFixture("codexbar-metrics-2026-10-12.jsonl", to: fixture.codexFolder)
        _ = try await fixture.importer.importMetrics(of: .codexBar, from: fixture.codexFolder)

        // Shorter than the saved read position: the file was replaced, so the
        // position no longer means anything and every line gets read again.
        let original = try Data(contentsOf: file)
        try Data(original.prefix(10)).write(to: file)
        _ = try await fixture.importer.importMetrics(of: .codexBar, from: fixture.codexFolder)
        try original.write(to: file)
        let reread = try await fixture.importer.importMetrics(of: .codexBar, from: fixture.codexFolder)

        #expect(reread.samplesRead == 4)
        let history = try await fixture.archive.samples(of: .codexBar, limitID: "codex:10080", metric: .resetsAt)
        #expect(history.count == 2)
    }

    @Test("Lines a Bar App appends are picked up, and a half-written line waits until it's finished")
    func appendedAndPartialLines() async throws {
        let fixture = try ImportFixture()
        let source = try Fixtures.data(named: "codexbar-metrics-2026-10-12.jsonl")
        let firstLineEnd = try #require(source.firstIndex(of: UInt8(ascii: "\n")))
        let file = fixture.codexFolder.appendingPathComponent("codexbar-metrics-2026-10-12.jsonl")
        try source.prefix(firstLineEnd + 1 + 25).write(to: file)

        let first = try await fixture.importer.importMetrics(of: .codexBar, from: fixture.codexFolder)
        try source.write(to: file)
        let second = try await fixture.importer.importMetrics(of: .codexBar, from: fixture.codexFolder)

        #expect(first.samplesRead == 2)
        #expect(first.droppedRecords == 0)
        #expect(second.samplesRead == 2)
        #expect(second.droppedRecords == 0)
        let history = try await fixture.archive.samples(of: .codexBar, limitID: "codex:10080", metric: .utilization)
        #expect(history.map(\.value) == [17, 18.5])
    }

    @Test("Only this Bar App's metrics files are read, and a missing folder isn't an error")
    func onlyMetricsFiles() async throws {
        let fixture = try ImportFixture()
        let codexMetrics = try Fixtures.data(named: "codexbar-metrics-2026-10-12.jsonl")
        try codexMetrics.write(to: fixture.claudeFolder.appendingPathComponent("codexbar-metrics-2026-10-12.jsonl"))
        try codexMetrics.write(to: fixture.claudeFolder.appendingPathComponent("claudebar-logs-2026-10-12.jsonl"))
        try codexMetrics.write(to: fixture.claudeFolder.appendingPathComponent("claudebar-metrics-latest.jsonl"))

        let summary = try await fixture.importer.importMetrics(of: .claudeBar, from: fixture.claudeFolder)
        let missing = try await fixture.importer.importMetrics(
            of: .claudeBar,
            from: fixture.folder.url.appendingPathComponent("Nowhere", isDirectory: true)
        )

        #expect(summary.filesRead == 0)
        #expect(missing.filesRead == 0)
        #expect(try await fixture.archive.currentLimits().isEmpty)
    }

    @Test("Non-conforming records are counted per file in the Archive")
    func droppedRecordsKept() async throws {
        let fixture = try ImportFixture()
        let file = fixture.claudeFolder.appendingPathComponent("claudebar-metrics-2026-10-11.jsonl")
        var data = MetricsLine.limits(service: "claudebar", points: [
            .utilization(id: "session", name: "Session (5h)", value: 140)
        ])
        try data.write(to: file)
        _ = try await fixture.importer.importMetrics(of: .claudeBar, from: fixture.claudeFolder)
        data += Data("garbage\n".utf8)
        try data.write(to: file)

        let summary = try await fixture.importer.importMetrics(of: .claudeBar, from: fixture.claudeFolder)

        #expect(summary.droppedRecords == 1)
        let progress = try await fixture.archive.progress(of: .claudeBar, fileName: "claudebar-metrics-2026-10-11.jsonl")
        #expect(progress?.droppedRecords == 2)
    }
}

/// Two Telemetry Folders and an Archive, all under one temp folder.
struct ImportFixture {
    let folder: TemporaryFolder
    let claudeFolder: URL
    let codexFolder: URL
    let archiveURL: URL
    let archive: Archive
    let importer: TelemetryImporter

    init() throws {
        folder = try TemporaryFolder()
        claudeFolder = folder.url.appendingPathComponent("ClaudeBar Telemetry", isDirectory: true)
        codexFolder = folder.url.appendingPathComponent("CodexBar Telemetry", isDirectory: true)
        try FileManager.default.createDirectory(at: claudeFolder, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: codexFolder, withIntermediateDirectories: true)
        archiveURL = folder.url.appendingPathComponent("Archive/Archive.sqlite")
        archive = try Archive(url: archiveURL)
        importer = TelemetryImporter(archive: archive)
    }

    @discardableResult
    func copyFixture(_ name: String, to destination: URL) throws -> URL {
        let target = destination.appendingPathComponent(name)
        try FileManager.default.copyItem(at: Fixtures.url(named: name), to: target)
        return target
    }
}
