import Foundation

/// Keeps the Archive filling with no window open, which is all the login item
/// does. It goes through the same LimitsOverview refresh as the window, so
/// every line still reaches the Archive through TelemetryImporter and its
/// read-position guard; running next to an open Bar UI can't count a line twice.
@MainActor
public final class BackgroundImporter {
    private let monitor: BarAppMonitor
    private let overview: LimitsOverview
    private let pollInterval: Duration

    /// `pollInterval` is both the backstop for changes folder watching can't
    /// see and how often the watch is re-pointed at the current folders.
    public init(monitor: BarAppMonitor, overview: LimitsOverview, pollInterval: Duration = .seconds(15)) {
        self.monitor = monitor
        self.overview = overview
        self.pollInterval = pollInterval
    }

    public func runOnce() async {
        monitor.refresh()
        await overview.refresh(statuses: monitor.statuses)
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

    private func waitOneRound(watching folders: [URL]) async {
        guard !folders.isEmpty else {
            await sleepOneRound()
            return
        }
        let watch = Task {
            for await _ in TelemetryFolderWatcher.changes(in: folders) {
                await overview.refresh(statuses: monitor.statuses)
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
