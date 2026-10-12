import BarUICore
import os
import SwiftUI

@main
struct BarUIApp: App {
    private static let logger = Logger(subsystem: "com.gordonbeeming.BarUI", category: "Pricing")

    /// Prices are re-checked hourly while the app stays open; the feeds only
    /// download when their cached copy is more than a day old.
    private static let pricingCheckInterval: Duration = .seconds(3_600)

    /// Opened once for the app: every window shares one connection, and the
    /// shared overview skips a refresh while another window's is running.
    @State private var archive = ArchiveOpening.open()
    @State private var pricing = PricingCatalog(cacheDirectory: Self.pricingCacheDirectory())

    var body: some Scene {
        // No preferredColorScheme anywhere: the window has to follow the Mac's
        // light/dark setting and switch live when the system does.
        WindowGroup("Bar UI") {
            ContentView(archive: archive)
                .frame(minWidth: 900, minHeight: 600)
                .environment(pricing)
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

        Settings {
            SettingsView()
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
