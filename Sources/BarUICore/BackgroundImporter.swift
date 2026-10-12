import Foundation
import os

/// Keeps the Archive filling with no window open, which is all the login item
/// does. It only imports: every line reaches the Archive through
/// TelemetryImporter and its read-position guard, so running next to an open
/// Bar UI can't count a line twice, and nothing is read back out.
@MainActor
public final class BackgroundImporter {
    private static let logger = Logger(subsystem: "com.gordonbeeming.BarUI", category: "BackgroundImporter")

    private let monitor: BarAppMonitor
    private let importer: TelemetryImporter
    private let pollInterval: Duration

    /// `pollInterval` is both the backstop for changes folder watching can't
    /// see and how often the watch is re-pointed at the current folders.
    public init(monitor: BarAppMonitor, importer: TelemetryImporter, pollInterval: Duration = .seconds(15)) {
        self.monitor = monitor
        self.importer = importer
        self.pollInterval = pollInterval
    }

    public func runOnce() async {
        monitor.refresh()
        await importAll()
    }

    /// Imports until cancelled: once per round, then again on every change
    /// in the Telemetry Folders until the round ends.
    public func run() async {
        while !Task.isCancelled {
            await runOnce()
            let folders = LimitsOverview.telemetryFolders(in: monitor.statuses).values.sorted { $0.path < $1.path }
            await waitOneRound(watching: folders)
        }
    }

    private func importAll() async {
        let folders = LimitsOverview.telemetryFolders(in: monitor.statuses)
        for app in BarApp.allCases {
            guard let folder = folders[app] else {
                continue
            }
            do {
                // The importer logs each file it can't read, and the next pass
                // tries those again from the Archive's position.
                _ = try await importer.importMetrics(of: app, from: folder)
            } catch {
                // No window to show it in; the next pass tries again.
                Self.logger.error("Can't import \(app.displayName, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    private func waitOneRound(watching folders: [URL]) async {
        guard !folders.isEmpty else {
            await sleepOneRound()
            return
        }
        let watch = Task {
            for await _ in TelemetryFolderWatcher.changes(in: folders) {
                await importAll()
            }
        }
        await sleepOneRound()
        // The watch never finishes on its own; ending it here is what lets
        // the next round point it at whatever folders exist by then.
        watch.cancel()
        await watch.value
    }

    private func sleepOneRound() async {
        do {
            try await Task.sleep(for: pollInterval)
        } catch {
            // Cancelled, which is how the owner stops the importer.
            return
        }
    }
}
