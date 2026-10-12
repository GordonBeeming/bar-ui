import Foundation
import Testing
@testable import BarUICore

@Suite("Watching Telemetry Folders")
struct TelemetryFolderWatcherTests {
    /// Counts what a watch reports. FSEvents can deliver a burst for writes
    /// made just before the watch began, so each test lets the watch settle
    /// and then only looks at what arrives after that.
    private actor Reports {
        private(set) var count = 0
        private var consumer: Task<Void, Never>?

        func start(_ changes: AsyncStream<Void>) {
            consumer = Task {
                for await _ in changes {
                    record()
                }
            }
        }

        func stop() {
            consumer?.cancel()
        }

        private func record() {
            count += 1
        }

        /// Waits until nothing has arrived for `quiet`, then returns the count.
        func settled(quiet: Duration = .seconds(1)) async throws -> Int {
            var seen = count
            while true {
                try await Task.sleep(for: quiet)
                guard count != seen else {
                    return seen
                }
                seen = count
            }
        }

        /// True once the count passes `baseline`, false if it doesn't in time.
        func grows(beyond baseline: Int, within limit: Duration) async throws -> Bool {
            let deadline = ContinuousClock.now + limit
            while ContinuousClock.now < deadline {
                if count > baseline {
                    return true
                }
                try await Task.sleep(for: .milliseconds(50))
            }
            return count > baseline
        }
    }

    @Test("Appending to a file in a watched folder is reported within a few seconds")
    func appendIsReported() async throws {
        let folder = try TemporaryFolder()
        let file = folder.url.appendingPathComponent("codexbar-metrics-2026-10-12.jsonl")
        try Data("{}\n".utf8).write(to: file)
        let reports = Reports()
        await reports.start(TelemetryFolderWatcher.changes(in: [folder.url]))
        let baseline = try await reports.settled()

        let handle = try FileHandle(forWritingTo: file)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data("{}\n".utf8))
        try handle.close()

        #expect(try await reports.grows(beyond: baseline, within: .seconds(5)))
        await reports.stop()
    }

    @Test("A folder nobody writes to stops reporting, so an idle Dashboard doesn't keep importing")
    func quietFolderIsQuiet() async throws {
        let folder = try TemporaryFolder()
        try Data("{}\n".utf8).write(to: folder.url.appendingPathComponent("codexbar-metrics-2026-10-12.jsonl"))
        let reports = Reports()
        await reports.start(TelemetryFolderWatcher.changes(in: [folder.url]))
        let baseline = try await reports.settled()

        #expect(try await !reports.grows(beyond: baseline, within: .milliseconds(1500)))
        await reports.stop()
    }

    @Test("A file appearing in a watched folder is reported")
    func newFileIsReported() async throws {
        let folder = try TemporaryFolder()
        let reports = Reports()
        await reports.start(TelemetryFolderWatcher.changes(in: [folder.url]))
        let baseline = try await reports.settled()

        try Data("{}\n".utf8).write(to: folder.url.appendingPathComponent("claudebar-metrics-2026-10-13.jsonl"))

        #expect(try await reports.grows(beyond: baseline, within: .seconds(5)))
        await reports.stop()
    }
}
