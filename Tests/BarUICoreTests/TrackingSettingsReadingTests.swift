import Foundation
import Testing
@testable import BarUICore

@Suite("Reading a Bar App's Tracking settings")
struct TrackingSettingsReadingTests {
    @Test("Settings come from the Bar App's defaults domain")
    func readsAllSettings() throws {
        let fixture = try Fixture()
        let custom = fixture.home.appendingPathComponent("Elsewhere/Claude", isDirectory: true)
        fixture.locator.installedBundleIdentifiers = ["com.gordonbeeming.ClaudeBar"]
        fixture.preferences.domains["com.gordonbeeming.ClaudeBar"] = [
            "telemetryEnabled": true,
            "telemetryIntervalMinutes": 15,
            "telemetryRetentionDays": 90,
            "telemetryDirectory": custom.path
        ]

        let settings = fixture.detector().status(of: .claudeBar).settings

        #expect(settings == TrackingSettings(enabled: true, intervalMinutes: 15, retentionDays: 90, folder: custom))
    }

    @Test("Defaults store numbers as NSNumber, which still read as whole minutes and days")
    func readsNSNumbers() throws {
        let fixture = try Fixture()
        fixture.locator.installedBundleIdentifiers = ["com.gordonbeeming.CodexBar"]
        fixture.preferences.domains["com.gordonbeeming.CodexBar"] = [
            "telemetryIntervalMinutes": NSNumber(value: 60),
            "telemetryRetentionDays": NSNumber(value: 0)
        ]

        let settings = try #require(fixture.detector().status(of: .codexBar).settings)

        #expect(settings.intervalMinutes == 60)
        #expect(settings.retentionDays == 0)
    }

    @Test("A Bar App that never saved its settings reads as Off, with no interval or retention and the default folder")
    func unsetSettings() throws {
        let fixture = try Fixture()
        fixture.locator.installedBundleIdentifiers = ["com.gordonbeeming.CodexBar"]

        let settings = fixture.detector().status(of: .codexBar).settings

        #expect(settings == TrackingSettings(
            enabled: false,
            intervalMinutes: nil,
            retentionDays: nil,
            folder: fixture.defaultFolder(of: .codexBar)
        ))
    }

    @Test("Values outside the spec's ranges read as not set rather than being shown as real")
    func outOfRangeValues() throws {
        let fixture = try Fixture()
        fixture.locator.installedBundleIdentifiers = ["com.gordonbeeming.ClaudeBar"]
        fixture.preferences.domains["com.gordonbeeming.ClaudeBar"] = [
            "telemetryIntervalMinutes": 0,
            "telemetryRetentionDays": 3651
        ]

        let settings = try #require(fixture.detector().status(of: .claudeBar).settings)

        #expect(settings.intervalMinutes == nil)
        #expect(settings.retentionDays == nil)
    }

    @Test("A Bar App that isn't installed has no settings")
    func notInstalledHasNoSettings() throws {
        let fixture = try Fixture()
        fixture.preferences.domains["com.gordonbeeming.ClaudeBar"] = ["telemetryEnabled": true]

        #expect(fixture.detector().status(of: .claudeBar).settings == nil)
    }
}
