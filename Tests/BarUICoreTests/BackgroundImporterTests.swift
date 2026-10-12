import Foundation
import Testing
@testable import BarUICore

@Suite("Background importer")
@MainActor
struct BackgroundImporterTests {
    private static let fileName = "codexbar-metrics-2026-10-12.jsonl"
    private static let limitID = "codex:10080"

    /// A Mac where CodexBar is tracking into its default folder, and an
    /// Archive on disk that several importers can open separately.
    @MainActor private struct Machine {
        let mac: Fixture
        let storage: ImportFixture
        let folder: URL

        init() throws {
            mac = try Fixture()
            storage = try ImportFixture()
            mac.locator.installedBundleIdentifiers = ["com.gordonbeeming.CodexBar"]
            mac.preferences.domains["com.gordonbeeming.CodexBar"] = ["telemetryEnabled": true]
            folder = try mac.makeFolder(mac.defaultFolder(of: .codexBar))
        }

        func importer(pollInterval: Duration = .seconds(60)) throws -> BackgroundImporter {
            let archive = try Archive(url: storage.archiveURL)
            return BackgroundImporter(
                monitor: BarAppMonitor(detector: mac.detector()),
                importer: TelemetryImporter(archive: archive),
                pollInterval: pollInterval
            )
        }
    }

    @Test("One pass lands a Bar App's Telemetry in the Archive with no window involved")
    func onePassImports() async throws {
        let machine = try Machine()
        try FileManager.default.copyItem(at: Fixtures.url(named: Self.fileName), to: machine.folder.appendingPathComponent(Self.fileName))

        try await machine.importer().runOnce()

        let samples = try await machine.storage.archive.samples(of: .codexBar, limitID: Self.limitID, metric: .utilization)
        #expect(!samples.isEmpty)
    }

    @Test("A background importer and the app's own importer, both running over the same file, import each line once")
    func noDoubleCountAcrossProcesses() async throws {
        let machine = try Machine()
        try FileManager.default.copyItem(at: Fixtures.url(named: Self.fileName), to: machine.folder.appendingPathComponent(Self.fileName))
        let background = try machine.importer()
        let app = try machine.importer()

        async let first: Void = background.runOnce()
        async let second: Void = app.runOnce()
        await first
        await second

        let lone = try ImportFixture()
        let loneFolder = lone.codexFolder
        try FileManager.default.copyItem(at: Fixtures.url(named: Self.fileName), to: loneFolder.appendingPathComponent(Self.fileName))
        _ = try await lone.importer.importMetrics(of: .codexBar, from: loneFolder)
        let expected = try await lone.archive.samples(of: .codexBar, limitID: Self.limitID, metric: .utilization)
        let actual = try await machine.storage.archive.samples(of: .codexBar, limitID: Self.limitID, metric: .utilization)
        #expect(actual.count == expected.count)
        #expect(!actual.isEmpty)
    }

    @Test("Running keeps importing Telemetry that arrives later, until it is cancelled")
    func runPicksUpLaterTelemetry() async throws {
        let machine = try Machine()
        let importer = try machine.importer(pollInterval: .milliseconds(50))
        let running = Task { await importer.run() }

        try FileManager.default.copyItem(at: Fixtures.url(named: Self.fileName), to: machine.folder.appendingPathComponent(Self.fileName))
        var count = 0
        for _ in 0..<100 where count == 0 {
            try await Task.sleep(for: .milliseconds(50))
            count = try await machine.storage.archive.samples(of: .codexBar, limitID: Self.limitID, metric: .utilization).count
        }
        running.cancel()
        await running.value

        #expect(count > 0)
    }
}
