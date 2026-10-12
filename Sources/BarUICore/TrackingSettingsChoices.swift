import Foundation

/// What the Tracking settings sheet offers and how settings read on a Bar App
/// page. Presets are a convenience only: a Bar App accepts any in-range value,
/// so a value it saved outside them is always offered too, or the sheet would
/// show a different value from the one the Bar App is using.
public enum TrackingSettingsChoices {
    public static let intervalPresets = [1, 5, 15, 60]
    /// Forever (`0`) is listed last because it is the longest.
    public static let retentionPresets = [30, 90, 0]

    public static func intervals(current: Int?) -> [Int] {
        guard let current, !intervalPresets.contains(current) else {
            return intervalPresets
        }
        return (intervalPresets + [current]).sorted()
    }

    public static func retentions(current: Int?) -> [Int] {
        guard let current, !retentionPresets.contains(current) else {
            return retentionPresets
        }
        let days = (retentionPresets.filter { $0 != 0 } + [current]).sorted()
        return days + [0]
    }

    public static func intervalTitle(_ minutes: Int) -> String {
        if minutes == 1 {
            return "Every 1 minute"
        }
        if minutes == 60 {
            return "Every hour"
        }
        if minutes > 60, minutes.isMultiple(of: 60) {
            return "Every \(minutes / 60) hours"
        }
        return "Every \(minutes) minutes"
    }

    public static func retentionTitle(_ days: Int) -> String {
        switch days {
        case 0: "Forever"
        case 1: "1 day"
        default: "\(days) days"
        }
    }

    public static func summary(of settings: TrackingSettings, home: URL) -> String {
        var parts = [settings.enabled ? "Tracking" : "Tracking off"]
        if let minutes = settings.intervalMinutes {
            parts.append("every \(minutes) min")
        }
        if let days = settings.retentionDays {
            parts.append(days == 0 ? "keeps files forever" : "keeps files \(retentionTitle(days))")
        }
        parts.append(displayPath(of: settings.folder, home: home))
        return parts.joined(separator: " · ")
    }

    /// Reverses `displayPath` for a folder typed into the sheet. Only the
    /// current user's `~` is expanded; anything else relative is refused,
    /// because the Bar App would resolve it against a directory Bar UI can't see.
    public static func folder(fromDisplayPath text: String, home: URL) throws -> URL {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let absolute: String
        if trimmed == "~" {
            absolute = home.path
        } else if trimmed.hasPrefix("~/") {
            absolute = home.path + "/" + trimmed.dropFirst(2)
        } else if trimmed.hasPrefix("/") {
            absolute = trimmed
        } else {
            throw TrackingChangeError.folderNotAbsolute(trimmed)
        }
        return URL(fileURLWithPath: absolute, isDirectory: true).standardizedFileURL
    }

    /// Compared by path components, so `/Users/meg` isn't mistaken for being
    /// inside `/Users/me`.
    public static func displayPath(of folder: URL, home: URL) -> String {
        let folderComponents = folder.standardizedFileURL.pathComponents
        let homeComponents = home.standardizedFileURL.pathComponents
        guard folderComponents.count >= homeComponents.count,
              Array(folderComponents.prefix(homeComponents.count)) == homeComponents else {
            return folder.standardizedFileURL.path
        }
        let rest = folderComponents.dropFirst(homeComponents.count)
        return rest.isEmpty ? "~" : "~/" + rest.joined(separator: "/")
    }
}
