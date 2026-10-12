import Foundation

/// A setting the Dashboard can ask a Bar App to change, named as the URL
/// scheme names it.
public enum TrackingSetting: String, Sendable, Hashable {
    case enabled
    case interval
    case retention
    case folder
}

public enum TrackingChangeError: Error, Equatable, LocalizedError {
    case noChanges
    case intervalOutOfRange(Int)
    case retentionOutOfRange(Int)
    case folderNotAbsolute(String)
    case cannotClear(TrackingSetting)
    case unrepresentableURL

    public var errorDescription: String? {
        switch self {
        case .noChanges:
            "Nothing has changed."
        case .intervalOutOfRange(let minutes):
            "An interval of \(minutes) minutes isn't allowed. Pick 1 to 1440 minutes."
        case .retentionOutOfRange(let days):
            "Keeping data for \(days) days isn't allowed. Pick 1 to 3650 days, or keep it forever."
        case .folderNotAbsolute(let path):
            "\(path) isn't a full folder path."
        case .cannotClear(let setting):
            "The \(setting.rawValue) setting can be changed, but not cleared."
        case .unrepresentableURL:
            "The request couldn't be turned into a URL."
        }
    }
}

/// Builds the URLs a Bar App's scheme accepts. The Bar App is the only writer
/// of its settings, so every change goes out as one of these requests and the
/// Bar App confirms it before applying anything.
public enum BarAppCommand {
    /// Only changed settings are sent: the Bar App lists each parameter in its
    /// confirmation, and an unchanged one would read as a change to approve.
    public static func changeTracking(
        of app: BarApp,
        from current: TrackingSettings,
        to edited: TrackingSettings
    ) throws -> URL {
        var items: [(TrackingSetting, String)] = []

        if edited.enabled != current.enabled {
            items.append((.enabled, edited.enabled ? "1" : "0"))
        }
        if let value = try changedValue(
            .interval, from: current.intervalMinutes, to: edited.intervalMinutes,
            range: TrackingSettings.intervalRange, error: TrackingChangeError.intervalOutOfRange
        ) {
            items.append((.interval, String(value)))
        }
        if let value = try changedValue(
            .retention, from: current.retentionDays, to: edited.retentionDays,
            range: TrackingSettings.retentionRange, error: TrackingChangeError.retentionOutOfRange
        ) {
            items.append((.retention, String(value)))
        }
        let editedPath = edited.folder.standardizedFileURL.path
        if editedPath != current.folder.standardizedFileURL.path {
            guard edited.folder.isFileURL, editedPath.hasPrefix("/") else {
                throw TrackingChangeError.folderNotAbsolute(edited.folder.absoluteString)
            }
            items.append((.folder, editedPath))
        }

        guard !items.isEmpty else {
            throw TrackingChangeError.noChanges
        }

        var components = URLComponents()
        components.scheme = app.urlScheme
        components.host = "telemetry"
        // Built by hand because URLComponents leaves `&`, `=` and `+` alone in
        // query values, and a folder name holding one of those would otherwise
        // split into a different request on the Bar App's side.
        components.percentEncodedQuery = try items
            .map { "\($0.0.rawValue)=\(try percentEncode($0.1))" }
            .joined(separator: "&")
        guard let url = components.url else {
            throw TrackingChangeError.unrepresentableURL
        }
        return url
    }

    public static func openSettings(of app: BarApp) throws -> URL {
        var components = URLComponents()
        components.scheme = app.urlScheme
        components.host = "settings"
        guard let url = components.url else {
            throw TrackingChangeError.unrepresentableURL
        }
        return url
    }

    private static func changedValue(
        _ setting: TrackingSetting,
        from current: Int?,
        to edited: Int?,
        range: ClosedRange<Int>,
        error: (Int) -> TrackingChangeError
    ) throws -> Int? {
        guard edited != current else {
            return nil
        }
        // The scheme has no way to say "unset", so dropping a value the Bar
        // App has would silently send nothing for it.
        guard let edited else {
            throw TrackingChangeError.cannotClear(setting)
        }
        guard range.contains(edited) else {
            throw error(edited)
        }
        return edited
    }

    /// Everything but RFC 3986 unreserved characters is encoded, so the value
    /// can't be mistaken for query syntax by any decoder.
    private static let unreserved = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")

    private static func percentEncode(_ value: String) throws -> String {
        // Sending the raw value instead would let it break the query apart.
        guard let encoded = value.addingPercentEncoding(withAllowedCharacters: unreserved) else {
            throw TrackingChangeError.unrepresentableURL
        }
        return encoded
    }
}

extension BarApp {
    /// The URL scheme each Bar App registers, as the Telemetry Spec lists them.
    public var urlScheme: String {
        switch self {
        case .claudeBar: "claudebar"
        case .codexBar: "codexbar"
        }
    }
}
