import Foundation

/// Where this Mac's user keeps the Archive. The window and the background
/// helper both open it from here, so they share one file.
public enum ArchiveLocation {
    /// Application Support rather than Caches: the Archive is the only copy
    /// of history once the Bar Apps' retention deletes their files.
    public static func url() throws -> URL {
        if let override = overrideFolder() {
            try FileManager.default.createDirectory(at: override, withIntermediateDirectories: true)
            return override.appendingPathComponent("Archive.sqlite", isDirectory: false)
        }
        let support = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return try url(inApplicationSupport: support)
    }

    /// Names the folder to keep the Archive in instead, so a build under test
    /// can be pointed at a copy and never touch the real history. Only an
    /// absolute path counts; anything else is ignored rather than resolved
    /// against wherever the process happens to run.
    static let overrideVariable = "BARUI_ARCHIVE_FOLDER"

    private static func overrideFolder() -> URL? {
        guard let path = ProcessInfo.processInfo.environment[overrideVariable], path.hasPrefix("/") else {
            return nil
        }
        return URL(fileURLWithPath: path, isDirectory: true)
    }

    public static func url(inApplicationSupport support: URL) throws -> URL {
        let folder = support.appendingPathComponent("com.gordonbeeming.BarUI", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appendingPathComponent("Archive.sqlite", isDirectory: false)
    }
}
