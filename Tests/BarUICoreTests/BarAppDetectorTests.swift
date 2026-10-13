import Foundation
import Testing
@testable import BarUICore

@Suite("Bar App detection")
struct BarAppDetectorTests {
    @Test("Bar Apps are identified by their bundle IDs")
    func bundleIdentifiers() {
        #expect(BarApp.claudeBar.bundleIdentifier == "com.gordonbeeming.ClaudeBar")
        #expect(BarApp.codexBar.bundleIdentifier == "com.gordonbeeming.CodexBar")
    }

    @Test("A Bar App that isn't installed is Not installed")
    func notInstalled() throws {
        let fixture = try Fixture()
        let detector = fixture.detector()

        #expect(detector.status(of: .claudeBar).state == .notInstalled)
    }

    @Test("An installed Bar App with Tracking on is Tracking")
    func tracking() throws {
        let fixture = try Fixture()
        fixture.locator.installedBundleIdentifiers = ["com.gordonbeeming.ClaudeBar"]
        fixture.preferences.domains["com.gordonbeeming.ClaudeBar"] = ["telemetryEnabled": true]

        #expect(fixture.detector().status(of: .claudeBar).state == .tracking)
    }

    @Test("An installed Bar App that never turned Tracking on is Off")
    func offWithoutSettings() throws {
        let fixture = try Fixture()
        fixture.locator.installedBundleIdentifiers = ["com.gordonbeeming.CodexBar"]

        #expect(fixture.detector().status(of: .codexBar).state == .off)
    }

    @Test("An installed Bar App with Tracking off and an empty Telemetry Folder is Off")
    func offWithEmptyFolder() throws {
        let fixture = try Fixture()
        fixture.locator.installedBundleIdentifiers = ["com.gordonbeeming.CodexBar"]
        fixture.preferences.domains["com.gordonbeeming.CodexBar"] = ["telemetryEnabled": false]
        try fixture.makeFolder(fixture.defaultFolder(of: .codexBar))

        #expect(fixture.detector().status(of: .codexBar).state == .off)
    }

    @Test("Tracking off with Telemetry files left in the default folder is Off with History")
    func offWithHistory() throws {
        let fixture = try Fixture()
        fixture.locator.installedBundleIdentifiers = ["com.gordonbeeming.ClaudeBar"]
        fixture.preferences.domains["com.gordonbeeming.ClaudeBar"] = ["telemetryEnabled": false]
        try fixture.makeFolder(fixture.defaultFolder(of: .claudeBar), files: ["claudebar-metrics-2026-10-01.jsonl"])

        #expect(fixture.detector().status(of: .claudeBar).state == .offWithHistory)
    }

    @Test("Files that aren't this Bar App's Telemetry don't count as History")
    func strayFilesAreNotHistory() throws {
        let fixture = try Fixture()
        fixture.locator.installedBundleIdentifiers = ["com.gordonbeeming.CodexBar"]
        try fixture.makeFolder(
            fixture.defaultFolder(of: .codexBar),
            files: [".DS_Store", "notes.txt", "claudebar-logs-2026-10-01.jsonl", "codexbar-metrics-latest.jsonl"]
        )

        #expect(fixture.detector().status(of: .codexBar).state == .off)
    }

    @Test("The Telemetry Folder defaults to ~/Library/Application Support/<AppName>/Telemetry")
    func defaultTelemetryFolder() throws {
        let fixture = try Fixture()
        fixture.locator.installedBundleIdentifiers = ["com.gordonbeeming.CodexBar"]

        let status = fixture.detector().status(of: .codexBar)

        #expect(status.telemetryFolder?.path == fixture.home.path + "/Library/Application Support/CodexBar/Telemetry")
    }

    @Test("A Bar App build that still writes to the old Documents default is read from there")
    func legacyDefaultWhenOnlyItExists() throws {
        let fixture = try Fixture()
        fixture.locator.installedBundleIdentifiers = ["com.gordonbeeming.ClaudeBar"]
        try fixture.makeFolder(fixture.legacyFolder(of: .claudeBar), files: ["claudebar-metrics-2026-10-01.jsonl"])

        let status = fixture.detector().status(of: .claudeBar)

        #expect(status.telemetryFolder?.path == fixture.legacyFolder(of: .claudeBar).path)
        #expect(status.state == .offWithHistory)
    }

    struct MoveFlagCase: Sendable, CustomTestStringConvertible {
        let flag: Bool?
        let readsLegacy: Bool
        var testDescription: String { "telemetryFolderMigrated = \(flag.map(String.init) ?? "absent")" }
    }

    static let moveFlagCases: [MoveFlagCase] = [
        MoveFlagCase(flag: true, readsLegacy: false),
        MoveFlagCase(flag: false, readsLegacy: true),
        MoveFlagCase(flag: nil, readsLegacy: true)
    ]

    @Test("Once the Bar App records its move, the old Documents folder is never read", arguments: moveFlagCases)
    func moveFlagKeepsBarUIOutOfDocuments(_ testCase: MoveFlagCase) throws {
        let fixture = try Fixture()
        fixture.locator.installedBundleIdentifiers = ["com.gordonbeeming.CodexBar"]
        if let flag = testCase.flag {
            fixture.preferences.domains["com.gordonbeeming.CodexBar"] = ["telemetryFolderMigrated": flag]
        }
        try fixture.makeFolder(fixture.legacyFolder(of: .codexBar), files: ["codexbar-metrics-2026-10-01.jsonl"])

        let status = fixture.detector().status(of: .codexBar)

        let expected = testCase.readsLegacy ? fixture.legacyFolder(of: .codexBar) : fixture.defaultFolder(of: .codexBar)
        #expect(status.telemetryFolder?.path == expected.path)
        #expect(status.state == (testCase.readsLegacy ? .offWithHistory : .off))
    }

    @Test("Anything at the new default's path, even a file, keeps Bar UI out of Documents")
    func fileAtNewDefaultStillWins() throws {
        let fixture = try Fixture()
        fixture.locator.installedBundleIdentifiers = ["com.gordonbeeming.ClaudeBar"]
        let current = fixture.defaultFolder(of: .claudeBar)
        try FileManager.default.createDirectory(at: current.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data().write(to: current)
        try fixture.makeFolder(fixture.legacyFolder(of: .claudeBar), files: ["claudebar-metrics-2026-10-01.jsonl"])

        let status = fixture.detector().status(of: .claudeBar)

        #expect(status.telemetryFolder?.path == current.path)
    }

    @Test("Once the new default exists, the old Documents folder isn't read")
    func newDefaultWinsOverLegacy() throws {
        let fixture = try Fixture()
        fixture.locator.installedBundleIdentifiers = ["com.gordonbeeming.ClaudeBar"]
        try fixture.makeFolder(fixture.defaultFolder(of: .claudeBar))
        try fixture.makeFolder(fixture.legacyFolder(of: .claudeBar), files: ["claudebar-metrics-2026-10-01.jsonl"])

        let status = fixture.detector().status(of: .claudeBar)

        #expect(status.telemetryFolder?.path == fixture.defaultFolder(of: .claudeBar).path)
        #expect(status.state == .off)
    }

    @Test("A custom Telemetry Folder set in the Bar App is used instead of the default")
    func customTelemetryFolder() throws {
        let fixture = try Fixture()
        let custom = fixture.home.appendingPathComponent("Elsewhere/Claude", isDirectory: true)
        fixture.locator.installedBundleIdentifiers = ["com.gordonbeeming.ClaudeBar"]
        fixture.preferences.domains["com.gordonbeeming.ClaudeBar"] = [
            "telemetryEnabled": false,
            "telemetryDirectory": custom.path
        ]
        try fixture.makeFolder(custom, files: ["claudebar-logs-2026-09-30.jsonl"])
        try fixture.makeFolder(fixture.defaultFolder(of: .claudeBar))

        let status = fixture.detector().status(of: .claudeBar)

        #expect(status.telemetryFolder?.path == custom.path)
        #expect(status.state == .offWithHistory)
    }

    @Test("History left in the default folder is ignored once a custom folder is set")
    func customFolderHidesDefaultHistory() throws {
        let fixture = try Fixture()
        let custom = fixture.home.appendingPathComponent("Elsewhere/Codex", isDirectory: true)
        fixture.locator.installedBundleIdentifiers = ["com.gordonbeeming.CodexBar"]
        fixture.preferences.domains["com.gordonbeeming.CodexBar"] = ["telemetryDirectory": custom.path]
        try fixture.makeFolder(fixture.defaultFolder(of: .codexBar), files: ["codexbar-metrics-2026-10-01.jsonl"])

        #expect(fixture.detector().status(of: .codexBar).state == .off)
    }

    @Test("A Telemetry Folder setting that isn't an absolute path falls back to the default")
    func relativeFolderFallsBack() throws {
        let fixture = try Fixture()
        fixture.locator.installedBundleIdentifiers = ["com.gordonbeeming.CodexBar"]
        fixture.preferences.domains["com.gordonbeeming.CodexBar"] = ["telemetryDirectory": "Telemetry"]

        let status = fixture.detector().status(of: .codexBar)

        #expect(status.telemetryFolder?.path == fixture.home.path + "/Library/Application Support/CodexBar/Telemetry")
    }

    @Test("A Bar App that isn't installed is Not installed, even with settings and files left behind")
    func leftoversDontMakeItInstalled() throws {
        let fixture = try Fixture()
        fixture.preferences.domains["com.gordonbeeming.ClaudeBar"] = ["telemetryEnabled": true]
        try fixture.makeFolder(fixture.defaultFolder(of: .claudeBar), files: ["claudebar-metrics-2026-10-01.jsonl"])

        let status = fixture.detector().status(of: .claudeBar)

        #expect(status.state == .notInstalled)
        #expect(status.telemetryFolder == nil)
    }

    @Test("An unrelated app named ClaudeBar with a different bundle ID is ignored")
    func unrelatedAppIgnored() throws {
        let fixture = try Fixture()
        fixture.locator.installedBundleIdentifiers = ["com.example.ClaudeBar", "ClaudeBar"]
        fixture.preferences.domains["com.example.ClaudeBar"] = ["telemetryEnabled": true]

        #expect(fixture.detector().status(of: .claudeBar).state == .notInstalled)
    }
}

/// A fake Mac: which bundle IDs are installed, what each defaults domain holds,
/// and a throwaway home folder so Telemetry Folders are real directories.
final class Fixture {
    let locator = FakeLocator()
    let preferences = FakePreferences()
    let home: URL

    init() throws {
        home = FileManager.default.temporaryDirectory
            .appendingPathComponent("BarUICoreTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: home)
    }

    func detector() -> BarAppDetector {
        BarAppDetector(locator: locator, preferences: preferences, homeDirectory: home)
    }

    @discardableResult
    func makeFolder(_ url: URL, files: [String] = []) throws -> URL {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        for name in files {
            try Data("{}\n".utf8).write(to: url.appendingPathComponent(name))
        }
        return url
    }

    func defaultFolder(of app: BarApp) -> URL {
        home.appendingPathComponent("Library/Application Support/\(app.displayName)/Telemetry", isDirectory: true)
    }

    func legacyFolder(of app: BarApp) -> URL {
        home.appendingPathComponent("Documents/\(app.displayName) Telemetry", isDirectory: true)
    }
}

final class FakeLocator: ApplicationLocating, @unchecked Sendable {
    var installedBundleIdentifiers: Set<String> = []

    func isInstalled(bundleIdentifier: String) -> Bool {
        installedBundleIdentifiers.contains(bundleIdentifier)
    }
}

final class FakePreferences: PreferencesReading, @unchecked Sendable {
    var domains: [String: [String: Any]] = [:]

    func value(forKey key: String, inDomain domain: String) -> Any? {
        domains[domain]?[key]
    }
}
