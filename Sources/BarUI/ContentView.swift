import BarUICore
import SwiftUI

struct ContentView: View {
    /// Bar Apps don't announce settings changes to other processes, so the
    /// sidebar polls. Reads are a few preference lookups and, only for apps
    /// with Tracking off, one folder listing, so a short interval is cheap.
    private static let refreshInterval: Duration = .seconds(2)

    /// Folder watching brings new Telemetry in within a second or so; this
    /// poll is the backstop for changes it can't see, such as on a network
    /// volume, or a folder that was created after the watch began.
    private static let importInterval: Duration = .seconds(15)

    static let home = FileManager.default.homeDirectoryForCurrentUser

    @State private var selection: SidebarItem? = .initial
    /// Owned by the app so the Menu Bar Preview reads the same statuses.
    let monitor: BarAppMonitor
    let archive: ArchiveOpening
    private let remote = BarAppRemote(opener: WorkspaceURLOpener())

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                ForEach(SidebarSection.sections(accounts: archive.overview?.accounts ?? []), id: \.self) { section in
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
            .safeAreaInset(edge: .bottom) {
                ImportStatusFooter(lastImportedAt: archive.overview?.lastImportedAt, archiveFailure: archive.failure)
            }
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
        .task(id: watchedFolders) {
            await importOnChange(in: watchedFolders)
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

    /// Sorted so the watch only restarts when the set of folders changes,
    /// not when the dictionary happens to iterate in another order.
    private var watchedFolders: [URL] {
        LimitsOverview.telemetryFolders(in: monitor.statuses).values.sorted { $0.path < $1.path }
    }

    private func importOnChange(in folders: [URL]) async {
        guard let overview = archive.overview else {
            return
        }
        // Ends when the task is cancelled, which happens when the folders
        // change (a new watch takes over) or the window closes.
        for await _ in TelemetryFolderWatcher.changes(in: folders) {
            await overview.refresh(statuses: monitor.statuses)
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
        ForEach(Array(section.items.enumerated()), id: \.element) { index, item in
            // A Bar App with several Accounts is listed as one row per
            // Account under a heading row, which only names the app and its
            // Tracking state.
            let isFirstOfApp = index == 0 || section.items[index - 1].app != item.app
            let isLastOfApp = index == section.items.count - 1 || section.items[index + 1].app != item.app
            if case .account(let account) = item, isFirstOfApp, isLastOfApp {
                // The app's only Account reads as the app itself.
                SidebarRow(item: .barApp(account.app), barAppState: monitor.status(of: account.app).state)
                    .tag(item)
            } else {
                if case .account(let account) = item, isFirstOfApp {
                    SidebarRow(item: .barApp(account.app), barAppState: monitor.status(of: account.app).state)
                }
                SidebarRow(
                    item: item,
                    barAppState: barAppState(for: item),
                    accountTitle: accountTitle(for: item),
                    accountStep: accountStep(for: item)
                )
                .tag(item)
            }
        }
    }

    private func accountTitle(for item: SidebarItem) -> String? {
        guard case .account(let account) = item else {
            return nil
        }
        return archive.overview?.label(of: account)
    }

    private func accountStep(for item: SidebarItem) -> Int {
        guard case .account(let account) = item else {
            return 0
        }
        return archive.overview?.colorStep(of: account) ?? 0
    }

    private func barAppState(for item: SidebarItem) -> TrackingState? {
        guard case .barApp(let app) = item else {
            return nil
        }
        return monitor.status(of: app).state
    }

    private func barAppPage(for account: BarAppAccount, title: String) -> some View {
        BarAppPageView(
            account: account,
            title: title,
            status: monitor.status(of: account.app),
            home: Self.home,
            remote: remote,
            skipped: archive.overview?.skippedRecords[account.app],
            history: archive.history,
            overview: archive.overview
        )
    }

    @ViewBuilder
    private func detail(for item: SidebarItem) -> some View {
        switch item {
        case .overview:
            OverviewView(overview: archive.overview, archiveFailure: archive.failure)
        case .barApp(let app):
            barAppPage(for: BarAppAccount(app: app), title: app.displayName)
        case .account(let account):
            barAppPage(for: account, title: archive.overview?.seriesLabel(of: account) ?? account.app.displayName)
        case .archive(.events):
            ResetsAndPerksPageView(overview: archive.overview, archiveFailure: archive.failure)
        case .archive(.imports):
            PlaceholderPageView(item: item)
        }
    }
}
