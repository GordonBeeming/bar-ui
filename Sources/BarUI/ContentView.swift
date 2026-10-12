import BarUICore
import SwiftUI

struct ContentView: View {
    /// Bar Apps don't announce settings changes to other processes, so the
    /// sidebar polls. Reads are a few preference lookups and, only for apps
    /// with Tracking off, one folder listing, so a short interval is cheap.
    private static let refreshInterval: Duration = .seconds(2)

    /// Bar Apps sample every few minutes at most, so importing more often
    /// than this would mostly find nothing new.
    private static let importInterval: Duration = .seconds(15)

    private static let home = FileManager.default.homeDirectoryForCurrentUser

    @State private var selection: SidebarItem? = .initial
    @State private var monitor = BarAppMonitor(detector: BarAppDetector(
        locator: WorkspaceApplicationLocator(),
        preferences: SystemPreferences(),
        homeDirectory: Self.home
    ))
    let archive: ArchiveOpening
    private let remote = BarAppRemote(opener: WorkspaceURLOpener())

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                ForEach(SidebarSection.all, id: \.self) { section in
                    if let title = section.title {
                        Section(title) {
                            rows(for: section)
                        }
                    } else {
                        rows(for: section)
                    }
                }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 200, ideal: 232, max: 300)
        } detail: {
            detail(for: selection ?? .initial)
        }
        .task {
            await pollBarApps()
        }
        .task {
            await importTelemetry()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            // Coming back from a Bar App's settings is the moment a change is
            // most likely, so don't make the person wait for the next poll.
            monitor.refresh()
            Task {
                await archive.overview?.refresh(statuses: monitor.statuses)
            }
        }
    }

    private func importTelemetry() async {
        guard let overview = archive.overview else {
            return
        }
        while !Task.isCancelled {
            await overview.refresh(statuses: monitor.statuses)
            do {
                try await Task.sleep(for: Self.importInterval)
            } catch {
                // Cancelled with the window; stop importing for it.
                return
            }
        }
    }

    private func pollBarApps() async {
        while !Task.isCancelled {
            do {
                try await Task.sleep(for: Self.refreshInterval)
            } catch {
                // Sleep only throws on cancellation, which means the window
                // went away and polling should stop.
                return
            }
            monitor.refresh()
        }
    }

    private func rows(for section: SidebarSection) -> some View {
        ForEach(section.items) { item in
            SidebarRow(item: item, barAppState: barAppState(for: item))
                .tag(item)
        }
    }

    private func barAppState(for item: SidebarItem) -> TrackingState? {
        guard case .barApp(let app) = item else {
            return nil
        }
        return monitor.status(of: app).state
    }

    @ViewBuilder
    private func detail(for item: SidebarItem) -> some View {
        switch item {
        case .overview:
            OverviewView(overview: archive.overview, archiveFailure: archive.failure)
        case .barApp(let app):
            BarAppPageView(app: app, status: monitor.status(of: app), home: Self.home, remote: remote, skipped: archive.overview?.skippedRecords[app])
        case .archive:
            PlaceholderPageView(item: item)
        }
    }
}
