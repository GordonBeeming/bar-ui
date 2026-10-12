import BarUICore
import Foundation
import os

// The login item behind the "Keep importing when Bar UI is closed" switch. It
// has no window; it only runs the same import the app runs, against the same
// Archive file.
let logger = Logger(subsystem: "com.gordonbeeming.BarUI.Helper", category: "Import")

do {
    let archive = try Archive(url: ArchiveLocation.url())
    let monitor = BarAppMonitor(detector: BarAppDetector(
        locator: WorkspaceApplicationLocator(),
        preferences: SystemPreferences(),
        homeDirectory: FileManager.default.homeDirectoryForCurrentUser
    ))
    let importer = BackgroundImporter(monitor: monitor, overview: LimitsOverview(archive: archive))
    Task {
        await importer.run()
    }
    dispatchMain()
} catch {
    // Without the Archive there is nothing to import into; exiting tells
    // launchd the helper failed rather than leaving an idle process behind.
    logger.error("Can't open the Archive: \(error.localizedDescription, privacy: .public)")
    exit(EXIT_FAILURE)
}
