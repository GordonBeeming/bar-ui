import BarUICore
import os
import SwiftUI

enum MainWindow {
    static let id = "main"
}

@main
struct BarUIApp: App {
    private static let logger = Logger(subsystem: "com.gordonbeeming.BarUI", category: "Pricing")

    /// Prices are re-checked hourly while the app stays open; the feeds only
    /// download when their cached copy is more than a day old.
    private static let pricingCheckInterval: Duration = .seconds(3_600)

    /// Opened once for the app: every window shares one connection, and the
    /// shared overview skips a refresh while another window's is running.
    @State private var archive = ArchiveOpening.open()
    @State private var monitor = BarAppMonitor(detector: BarAppDetector(
        locator: WorkspaceApplicationLocator(),
        preferences: SystemPreferences(),
        homeDirectory: ContentView.home
    ))
    @State private var pricing = PricingCatalog(cacheDirectory: Self.pricingCacheDirectory())
    @State private var backgroundImport = BackgroundImportSetting(service: LoginItemService(), store: UserDefaultsChoiceStore())

    var body: some Scene {
        // No preferredColorScheme anywhere: the window has to follow the Mac's
        // light/dark setting and switch live when the system does.
        //
        // A single Window rather than a WindowGroup, so Open Bar UI in the
        // Menu Bar Preview brings this one forward instead of making another.
        Window("Bar UI", id: MainWindow.id) {
            ContentView(monitor: monitor, archive: archive)
                .frame(minWidth: 900, minHeight: 600)
                .environment(pricing)
                .task {
                    // Registers the helper the first time the app opens, and
                    // repairs it if it was removed or the choice changed since.
                    backgroundImport.reconcile()
                }
                .task {
                    while !Task.isCancelled {
                        await pricing.refresh()
                        do {
                            try await Task.sleep(for: Self.pricingCheckInterval)
                        } catch {
                            // Cancelled with the window; stop checking for it.
                            return
                        }
                    }
                }
        }
        .defaultSize(width: 1440, height: 900)

        MenuBarExtra("Bar UI", systemImage: "chart.bar.xaxis") {
            MenuBarPreviewView(preview: archive.preview, monitor: monitor, archiveFailure: archive.failure)
                .environment(pricing)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(backgroundImport: backgroundImport)
                .environment(pricing)
        }
    }

    /// Caches rather than Application Support: both feeds can be downloaded
    /// again, unlike the Archive.
    private static func pricingCacheDirectory() -> URL? {
        do {
            return try FileManager.default.url(for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
                .appendingPathComponent("com.gordonbeeming.BarUI", isDirectory: true)
        } catch {
            logger.error("No cache folder for prices: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }
}
