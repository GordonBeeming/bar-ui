import Foundation
import Testing
@testable import BarUICore

@Suite("Incremental import")
struct IncrementalImportTests {
    private static let fileName = "codexbar-metrics-2026-10-12.jsonl"

    /// One line per minute, each with a distinct utilisation sample, plus a
    /// non-conforming line every fifth line so the dropped count is checkable.
    private static func lines(_ range: Range<Int>) -> Data {
        var data = Data()
        for index in range {
            if index % 5 == 4 {
                data += Data("not a metrics line \(index)\n".utf8)
            } else {
                data += MetricsLine.limits(service: "codexbar", points: [
                    .utilization(id: "codex:10080", name: "Weekly", value: Double(index % 100), time: 1_791_791_100_000_000_000 + Int64(index) * 60_000_000_000)
                ])
            }
        }
        return data
    }

    @Test("Importers racing a Bar App that is still appending, through separate Archive connections, import each line once")
    func concurrentImportersCountEachLineOnce() async throws {
        let fixture = try ImportFixture()
        let file = fixture.codexFolder.appendingPathComponent(Self.fileName)
        try Data().write(to: file)
        let first = fixture.importer
        let second = TelemetryImporter(archive: try Archive(url: fixture.archiveURL))
        let folder = fixture.codexFolder
        let writer = try FileHandle(forWritingTo: file)
        defer {
            do {
                try writer.close()
            } catch {
                Issue.record(error, "Couldn't close the test writer")
            }
        }

        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                for index in 0..<200 {
                    try writer.write(contentsOf: Self.lines(index..<index + 1))
                    await Task.yield()
                }
            }
            for importer in [first, second, first, second] {
                group.addTask {
                    for _ in 0..<60 {
                        _ = try await importer.importMetrics(of: .codexBar, from: folder)
                    }
                }
            }
            try await group.waitForAll()
        }
        _ = try await first.importMetrics(of: .codexBar, from: folder)

        let progress = try await fixture.archive.progress(of: .codexBar, fileName: Self.fileName)
        #expect(progress?.droppedRecords == 40)
        #expect(progress?.byteOffset == Int64(try Data(contentsOf: file).count))
        let history = try await fixture.archive.samples(of: .codexBar, limitID: "codex:10080", metric: .utilization)
        #expect(history.count == 160)
    }

    @Test("A file that is listed but gone by the time it's read is skipped quietly, and the rest still import")
    func fileGoneBeforeReading() async throws {
        let fixture = try ImportFixture()
        try fixture.copyFixture(Self.fileName, to: fixture.codexFolder)
        // A link to nothing lists like a file but can't be opened, the same
        // as a file retention deleted between the listing and the read.
        try FileManager.default.createSymbolicLink(
            at: fixture.codexFolder.appendingPathComponent("codexbar-metrics-2026-10-11.jsonl"),
            withDestinationURL: fixture.folder.url.appendingPathComponent("deleted.jsonl")
        )

        let summary = try await fixture.importer.importMetrics(of: .codexBar, from: fixture.codexFolder)

        #expect(summary.failures.isEmpty)
        #expect(summary.filesRead == 1)
        #expect(try await fixture.archive.currentLimits().map(\.utilization) == [18.5])
    }

    @Test("An import read from a position another import already moved past is turned away, so nothing is counted twice")
    func staleImportIsRejected() async throws {
        let folder = try TemporaryFolder()
        let archive = try Archive(url: folder.url.appendingPathComponent("Archive.sqlite"))
        let weekly = LimitDescriptor(id: "codex:10080", name: "Weekly", windowDurationMinutes: nil, modelID: nil)
        let sample = LimitSample(app: .codexBar, limit: weekly, metric: .utilization, timeUnixNano: 1, value: 3)
        try await archive.useImportFolder(folder.url, for: .codexBar)
        let start = ImportProgress(app: .codexBar, fileName: Self.fileName, byteOffset: 100, droppedRecords: 1)
        try await archive.record(TelemetryRecords(), progress: start)
        let advanced = ImportProgress(app: .codexBar, fileName: Self.fileName, byteOffset: 200, droppedRecords: 2)

        let winner = try await archive.record(TelemetryRecords(limitSamples: [sample]), progress: advanced, readFrom: start, in: folder.url)
        let loser = try await archive.record(TelemetryRecords(limitSamples: [sample]), progress: advanced, readFrom: start, in: folder.url)
        let fresh = try await archive.record(TelemetryRecords(), progress: start, readFrom: nil, in: folder.url)

        #expect(winner)
        #expect(!loser)
        #expect(!fresh)
        let stored = try await archive.progress(of: .codexBar, fileName: Self.fileName)
        #expect(stored == advanced)
    }

    @Test("A stale import is turned away whole: no tokens, resets or Perks from it reach the Archive")
    func staleImportWritesNothingOfAnyKind() async throws {
        let folder = try TemporaryFolder()
        let archive = try Archive(url: folder.url.appendingPathComponent("Archive.sqlite"))
        let weekly = LimitDescriptor(id: "codex:10080", name: "Weekly", windowDurationMinutes: nil, modelID: nil)
        let start = ImportProgress(app: .codexBar, fileName: Self.fileName, byteOffset: 100, droppedRecords: 0)
        try await archive.useImportFolder(folder.url, for: .codexBar)
        try await archive.record(TelemetryRecords(), progress: ImportProgress(app: .codexBar, fileName: Self.fileName, byteOffset: 200, droppedRecords: 0))

        let recorded = try await archive.record(
            TelemetryRecords(
                limitSamples: [LimitSample(app: .codexBar, limit: weekly, metric: .utilization, timeUnixNano: 1, value: 3)],
                tokenSamples: [TokenSample(app: .codexBar, model: "gpt-5", tokenType: .input, startTimeUnixNano: 0, timeUnixNano: 1, count: 10)],
                perkSamples: [PerkSample(app: .codexBar, kind: .resetCredit, currency: nil, timeUnixNano: 1, value: 2, expiresAt: nil)],
                resets: [LimitReset(app: .codexBar, limit: weekly, timeUnixNano: 1, utilizationLast: 40, nextResetsAt: nil)],
                perkGoneEvents: [PerkGoneEvent(app: .codexBar, kind: .resetCredit, currency: nil, quantity: 1, perkID: nil, expiresAt: nil, reportedReason: .used, timeUnixNano: 1)]
            ),
            progress: ImportProgress(app: .codexBar, fileName: Self.fileName, byteOffset: 300, droppedRecords: 0),
            readFrom: start,
            in: folder.url
        )

        #expect(!recorded)
        #expect(try await archive.currentLimits().isEmpty)
        #expect(try await archive.tokenSamples().isEmpty)
        #expect(try await archive.limitHistories(of: .codexBar, since: nil).isEmpty)
        #expect(try await archive.availablePerks().isEmpty)
        #expect(try await archive.gonePerks().isEmpty)
        #expect(try await archive.progress(of: .codexBar, fileName: Self.fileName)?.byteOffset == 200)
    }

    @Test("Importers racing a Bar App appending to its logs file import each event once and count each bad one once")
    func concurrentImportersOverLogs() async throws {
        let fixture = try ImportFixture()
        let name = "claudebar-logs-2026-10-12.jsonl"
        let file = fixture.claudeFolder.appendingPathComponent(name)
        try Data().write(to: file)
        let first = fixture.importer
        let second = TelemetryImporter(archive: try Archive(url: fixture.archiveURL))
        let folder = fixture.claudeFolder
        let writer = try FileHandle(forWritingTo: file)
        defer {
            do {
                try writer.close()
            } catch {
                Issue.record(error, "Couldn't close the test writer")
            }
        }

        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                for index in 0..<100 {
                    // Every fourth event is a Perk kind the spec doesn't define.
                    let kind = index % 4 == 3 ? "coupon" : "guest_pass"
                    let time = 1_791_791_100_000_000_000 + Int64(index) * 60_000_000_000
                    try writer.write(contentsOf: PerkEventLine.logs(service: "claudebar", events: [
                        .init(name: "bar.perk.gone", kind: kind, time: time)
                    ]))
                    await Task.yield()
                }
            }
            for importer in [first, second, first, second] {
                group.addTask {
                    for _ in 0..<40 {
                        _ = try await importer.importMetrics(of: .claudeBar, from: folder)
                    }
                }
            }
            try await group.waitForAll()
        }
        _ = try await first.importMetrics(of: .claudeBar, from: folder)

        #expect(try await fixture.archive.gonePerks().count == 75)
        let progress = try await fixture.archive.progress(of: .claudeBar, fileName: name)
        #expect(progress?.droppedRecords == 25)
        #expect(progress?.byteOffset == Int64(try Data(contentsOf: file).count))
    }

    @Test("The first import of a file is accepted only while the Archive has no position for it")
    func firstImportIsRecorded() async throws {
        let folder = try TemporaryFolder()
        let archive = try Archive(url: folder.url.appendingPathComponent("Archive.sqlite"))
        let first = ImportProgress(app: .codexBar, fileName: Self.fileName, byteOffset: 50, droppedRecords: 0)
        try await archive.useImportFolder(folder.url, for: .codexBar)

        let accepted = try await archive.record(TelemetryRecords(), progress: first, readFrom: nil, in: folder.url)

        #expect(accepted)
        #expect(try await archive.progress(of: .codexBar, fileName: Self.fileName) == first)
    }

    struct FolderChangeCase: Sendable, CustomTestStringConvertible {
        let testDescription: String
        /// Lines already in the new folder's file before the old file's lines are appended to it.
        let alreadyThere: Range<Int>
        /// Lines the Bar App appended to the old file's lines after the move.
        let appendedAfter: Range<Int>
        let samples: Int
        let dropped: Int
    }

    static let folderChangeCases: [FolderChangeCase] = [
        FolderChangeCase(testDescription: "old lines appended to a file already in the new folder", alreadyThere: 10..<20, appendedAfter: 0..<0, samples: 16, dropped: 4),
        FolderChangeCase(testDescription: "file moved whole, then appended to", alreadyThere: 0..<0, appendedAfter: 10..<15, samples: 12, dropped: 3)
    ]

    @Test("When a Bar App's files come from a different folder, they are read again from the start, counting each record and skipped line once", arguments: folderChangeCases)
    func folderChangeReadsFromTheStart(_ testCase: FolderChangeCase) async throws {
        let fixture = try ImportFixture()
        let newFolder = fixture.folder.url.appendingPathComponent("Application Support/CodexBar/Telemetry", isDirectory: true)
        try FileManager.default.createDirectory(at: newFolder, withIntermediateDirectories: true)
        try Self.lines(0..<10).write(to: fixture.codexFolder.appendingPathComponent(Self.fileName))
        _ = try await fixture.importer.importMetrics(of: .codexBar, from: fixture.codexFolder)
        let moved = Self.lines(testCase.alreadyThere) + Self.lines(0..<10) + Self.lines(testCase.appendedAfter)
        try moved.write(to: newFolder.appendingPathComponent(Self.fileName))

        _ = try await fixture.importer.importMetrics(of: .codexBar, from: newFolder)
        let again = try await fixture.importer.importMetrics(of: .codexBar, from: newFolder)

        #expect(again.filesRead == 0)
        let progress = try await fixture.archive.progress(of: .codexBar, fileName: Self.fileName)
        #expect(progress?.byteOffset == Int64(moved.count))
        #expect(progress?.droppedRecords == testCase.dropped)
        #expect(try await fixture.archive.samples(of: .codexBar, limitID: "codex:10080", metric: .utilization).count == testCase.samples)
    }

    @Test("Skipped records from a file that didn't come along to the new folder stay reported")
    func folderChangeKeepsSkippedRecordsOfGoneFiles() async throws {
        let fixture = try ImportFixture()
        let newFolder = fixture.folder.url.appendingPathComponent("Application Support/CodexBar/Telemetry", isDirectory: true)
        try FileManager.default.createDirectory(at: newFolder, withIntermediateDirectories: true)
        try Self.lines(0..<10).write(to: fixture.codexFolder.appendingPathComponent("codexbar-metrics-2026-10-11.jsonl"))
        try Self.lines(0..<5).write(to: fixture.codexFolder.appendingPathComponent(Self.fileName))
        _ = try await fixture.importer.importMetrics(of: .codexBar, from: fixture.codexFolder)
        try Self.lines(0..<5).write(to: newFolder.appendingPathComponent(Self.fileName))

        _ = try await fixture.importer.importMetrics(of: .codexBar, from: newFolder)

        #expect(try await fixture.archive.skippedRecords(of: .codexBar) == [
            SkippedRecords(day: TelemetryDay(year: 2026, month: 10, day: 11), count: 2),
            SkippedRecords(day: TelemetryDay(year: 2026, month: 10, day: 12), count: 1)
        ])
    }

    @Test("An import read from the old folder is turned away once another importer has moved to a new one")
    func importFromSupersededFolderIsRejected() async throws {
        let folder = try TemporaryFolder()
        let archive = try Archive(url: folder.url.appendingPathComponent("Archive.sqlite"))
        let old = folder.url.appendingPathComponent("Old", isDirectory: true)
        let new = folder.url.appendingPathComponent("New", isDirectory: true)
        try await archive.useImportFolder(old, for: .codexBar)
        try await archive.useImportFolder(new, for: .codexBar)
        let progress = ImportProgress(app: .codexBar, fileName: Self.fileName, byteOffset: 50, droppedRecords: 0)

        let stale = try await archive.record(TelemetryRecords(), progress: progress, readFrom: nil, in: old)
        let current = try await archive.record(TelemetryRecords(), progress: progress, readFrom: nil, in: new)

        #expect(!stale)
        #expect(current)
    }

    @Test("After a restart, only the lines appended since the last import are read")
    func restartCarriesOn() async throws {
        let fixture = try ImportFixture()
        let file = fixture.codexFolder.appendingPathComponent(Self.fileName)
        try Self.lines(0..<10).write(to: file)
        _ = try await fixture.importer.importMetrics(of: .codexBar, from: fixture.codexFolder)
        try (Self.lines(0..<10) + Self.lines(10..<15)).write(to: file)

        let restarted = try Archive(url: fixture.archiveURL)
        let summary = try await TelemetryImporter(archive: restarted).importMetrics(of: .codexBar, from: fixture.codexFolder)

        #expect(summary.samplesRead == 4)
        #expect(summary.droppedRecords == 1)
        #expect(try await restarted.progress(of: .codexBar, fileName: Self.fileName)?.droppedRecords == 3)
        #expect(try await restarted.samples(of: .codexBar, limitID: "codex:10080", metric: .utilization).count == 12)
    }
}

@Suite("Live import on the Overview")
@MainActor
struct LiveImportTests {
    private static func status(folder: URL) -> BarAppStatus {
        BarAppStatus(state: .tracking, settings: TrackingSettings(enabled: true, intervalMinutes: 5, retentionDays: 90, folder: folder))
    }

    @Test("A refresh asked for while another is importing still runs, with the Bar Apps it was given")
    func overlappingRefreshIsNotDropped() async throws {
        let fixture = try ImportFixture()
        try fixture.copyFixture("claudebar-metrics-2026-10-12.jsonl", to: fixture.claudeFolder)
        try fixture.copyFixture("codexbar-metrics-2026-10-12.jsonl", to: fixture.codexFolder)
        let overview = LimitsOverview(archive: fixture.archive)

        let claude = [BarApp.claudeBar: Self.status(folder: fixture.claudeFolder)]
        let codex = [BarApp.codexBar: Self.status(folder: fixture.codexFolder)]

        let first = Task { await overview.refresh(statuses: claude) }
        let second = Task { await overview.refresh(statuses: codex) }
        await first.value
        await second.value

        #expect(Set(overview.limits.map(\.app)) == [.claudeBar, .codexBar])
    }

    @Test("The folders to watch are the Telemetry Folders of every installed Bar App, Tracking or not")
    func foldersToWatch() {
        let claude = URL(fileURLWithPath: "/tmp/ClaudeBar Telemetry", isDirectory: true)
        let codex = URL(fileURLWithPath: "/tmp/CodexBar Telemetry", isDirectory: true)

        let folders = LimitsOverview.telemetryFolders(in: [
            .claudeBar: BarAppStatus(state: .off, settings: TrackingSettings(enabled: false, intervalMinutes: 5, retentionDays: 90, folder: claude)),
            .codexBar: Self.status(folder: codex)
        ])
        let none = LimitsOverview.telemetryFolders(in: [.claudeBar: .notInstalled])

        #expect(folders == [.claudeBar: claude, .codexBar: codex])
        #expect(none.isEmpty)
    }

    @Test("The time of the last import is kept for the sidebar, and only once an import has run")
    func lastImportTime() async throws {
        let fixture = try ImportFixture()
        try fixture.copyFixture("codexbar-metrics-2026-10-12.jsonl", to: fixture.codexFolder)
        let importedAt = Date(timeIntervalSince1970: 1_791_791_400)
        let overview = LimitsOverview(archive: fixture.archive, now: { importedAt })

        await overview.refresh(statuses: [:])
        let beforeAnyBarApp = overview.lastImportedAt
        await overview.refresh(statuses: [.codexBar: Self.status(folder: fixture.codexFolder)])

        #expect(beforeAnyBarApp == nil)
        #expect(overview.lastImportedAt == importedAt)
    }
}
