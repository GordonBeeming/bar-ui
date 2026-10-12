import Foundation

/// Where this Mac's user keeps the Archive. The window and the background
/// helper both open it from here, so they share one file.
public enum ArchiveLocation {
    /// Application Support rather than Caches: the Archive is the only copy
    /// of history once the Bar Apps' retention deletes their files.
    public static func url() throws -> URL {
        let support = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return try url(inApplicationSupport: support)
    }

    public static func url(inApplicationSupport support: URL) throws -> URL {
        let folder = support.appendingPathComponent("com.gordonbeeming.BarUI", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appendingPathComponent("Archive.sqlite", isDirectory: false)
    }
}
