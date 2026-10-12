import BarUICore
import Foundation
import os

/// The Archive for this Mac's user, or why it couldn't be opened. The window
/// still opens without it so the Bar App pages and settings keep working.
@MainActor
struct ArchiveOpening {
    private static let logger = Logger(subsystem: "com.gordonbeeming.BarUI", category: "Archive")

    let overview: LimitsOverview?
    let history: LimitHistoryModel?
    let failure: String?

    static func open() -> ArchiveOpening {
        do {
            // Application Support rather than Caches: the Archive is the only
            // copy of history once the Bar Apps' retention deletes their files.
            let folder = try FileManager.default.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            ).appendingPathComponent("com.gordonbeeming.BarUI", isDirectory: true)
            let archive = try Archive(url: folder.appendingPathComponent("Archive.sqlite", isDirectory: false))
            return ArchiveOpening(overview: LimitsOverview(archive: archive), history: LimitHistoryModel(archive: archive), failure: nil)
        } catch {
            logger.error("Can't open the Archive: \(error.localizedDescription, privacy: .public)")
            return ArchiveOpening(overview: nil, history: nil, failure: error.localizedDescription)
        }
    }
}
