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
    let preview: MenuBarPreview?
    let failure: String?

    static func open() -> ArchiveOpening {
        do {
            let archive = try Archive(url: ArchiveLocation.url())
            let overview = LimitsOverview(archive: archive)
            return ArchiveOpening(
                overview: overview,
                history: LimitHistoryModel(archive: archive),
                preview: MenuBarPreview(archive: archive, overview: overview),
                failure: nil
            )
        } catch {
            logger.error("Can't open the Archive: \(error.localizedDescription, privacy: .public)")
            return ArchiveOpening(overview: nil, history: nil, preview: nil, failure: error.localizedDescription)
        }
    }
}
