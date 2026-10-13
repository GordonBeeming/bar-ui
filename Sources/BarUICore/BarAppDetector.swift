import Foundation
import os

/// Answers whether an app with a given bundle ID is installed. Lookups are by
/// bundle ID only, so a same-named app from someone else never matches.
public protocol ApplicationLocating: Sendable {
    func isInstalled(bundleIdentifier: String) -> Bool
}

/// Read-only access to another app's defaults domain. The Dashboard never
/// writes a Bar App's settings; it asks the Bar App to change them.
public protocol PreferencesReading: Sendable {
    func value(forKey key: String, inDomain domain: String) -> Any?
}

/// Works out each Bar App's state from what the Mac currently says. Every call
/// reads fresh, so repeated calls pick up a Bar App changing its own settings.
public struct BarAppDetector: Sendable {
    private enum Key {
        static let telemetryEnabled = "telemetryEnabled"
        static let telemetryDirectory = "telemetryDirectory"
        static let telemetryIntervalMinutes = "telemetryIntervalMinutes"
        static let telemetryRetentionDays = "telemetryRetentionDays"
    }

    private static let logger = Logger(subsystem: "com.gordonbeeming.BarUI", category: "BarAppDetector")

    private let locator: any ApplicationLocating
    private let preferences: any PreferencesReading
    private let homeDirectory: URL

    public init(locator: any ApplicationLocating, preferences: any PreferencesReading, homeDirectory: URL) {
        self.locator = locator
        self.preferences = preferences
        self.homeDirectory = homeDirectory
    }

    public func status(of app: BarApp) -> BarAppStatus {
        let domain = app.bundleIdentifier
        guard locator.isInstalled(bundleIdentifier: domain) else {
            return .notInstalled
        }

        let settings = TrackingSettings(
            enabled: preferences.value(forKey: Key.telemetryEnabled, inDomain: domain) as? Bool ?? false,
            intervalMinutes: integer(forKey: Key.telemetryIntervalMinutes, inDomain: domain, within: TrackingSettings.intervalRange),
            retentionDays: integer(forKey: Key.telemetryRetentionDays, inDomain: domain, within: TrackingSettings.retentionRange),
            folder: telemetryFolder(of: app)
        )
        if settings.enabled {
            return BarAppStatus(state: .tracking, settings: settings)
        }
        let state: TrackingState = hasTelemetryFiles(of: app, in: settings.folder) ? .offWithHistory : .off
        return BarAppStatus(state: state, settings: settings)
    }

    private func integer(forKey key: String, inDomain domain: String, within range: ClosedRange<Int>) -> Int? {
        guard let value = preferences.value(forKey: key, inDomain: domain) as? Int, range.contains(value) else {
            return nil
        }
        return value
    }

    private func telemetryFolder(of app: BarApp) -> URL {
        // The spec requires an absolute path; anything else can't be resolved
        // the way the Bar App resolves it, so the Bar App's default is the
        // safer reading than a path relative to wherever Bar UI runs.
        if let custom = preferences.value(forKey: Key.telemetryDirectory, inDomain: app.bundleIdentifier) as? String,
           custom.hasPrefix("/") {
            return URL(fileURLWithPath: custom, isDirectory: true).standardizedFileURL
        }
        let current = homeDirectory
            .appendingPathComponent("Library/Application Support", isDirectory: true)
            .appendingPathComponent(app.displayName, isDirectory: true)
            .appendingPathComponent("Telemetry", isDirectory: true)
        // The default used to be in Documents. A Bar App build from before the
        // move still writes there, so that folder is read only while the new
        // one doesn't exist; checking it is what makes macOS ask for access to
        // Documents, so it is never touched once the Bar App has moved.
        let legacy = homeDirectory
            .appendingPathComponent("Documents", isDirectory: true)
            .appendingPathComponent("\(app.displayName) Telemetry", isDirectory: true)
        if !isDirectory(current), isDirectory(legacy) {
            return legacy
        }
        return current
    }

    private func isDirectory(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
    }

    private func hasTelemetryFiles(of app: BarApp, in folder: URL) -> Bool {
        let names: [String]
        do {
            names = try FileManager.default.contentsOfDirectory(atPath: folder.path)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            return false
        } catch {
            // A folder Bar UI can't read (permissions, a detached volume) can't
            // prove there is History, so the app shows as Off; the log keeps
            // the reason findable instead of silently hiding it.
            Self.logger.error("Can't list Telemetry Folder \(folder.path, privacy: .private) for \(app.displayName, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return false
        }
        return names.contains { app.isTelemetryFileName($0) }
    }
}

extension BarApp {
    /// The lowercase `service.name` the Telemetry Spec gives this Bar App.
    var serviceName: String {
        rawValue.lowercased()
    }

    /// Only the spec's two file name patterns count, so a stray `.DS_Store` or
    /// another app's files in a shared folder never look like History.
    func isTelemetryFileName(_ name: String) -> Bool {
        let pattern = /^(?<service>[a-z]+)-(?:metrics|logs)-\d{4}-\d{2}-\d{2}\.jsonl$/
        guard let match = name.wholeMatch(of: pattern) else {
            return false
        }
        return match.output.service == serviceName
    }
}
