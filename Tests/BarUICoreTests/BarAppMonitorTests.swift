import Foundation
import Testing
@testable import BarUICore

@Suite("Bar App monitor")
@MainActor
struct BarAppMonitorTests {
    @Test("Every Bar App has a status as soon as the monitor exists")
    func initialStatuses() throws {
        let fixture = try Fixture()
        fixture.locator.installedBundleIdentifiers = ["com.gordonbeeming.ClaudeBar"]
        fixture.preferences.domains["com.gordonbeeming.ClaudeBar"] = ["telemetryEnabled": true]

        let monitor = BarAppMonitor(detector: fixture.detector())

        #expect(monitor.status(of: .claudeBar).state == .tracking)
        #expect(monitor.status(of: .codexBar).state == .notInstalled)
    }

    @Test("Turning Tracking off in a Bar App shows up on the next refresh")
    func trackingTurnedOff() throws {
        let fixture = try Fixture()
        fixture.locator.installedBundleIdentifiers = ["com.gordonbeeming.CodexBar"]
        fixture.preferences.domains["com.gordonbeeming.CodexBar"] = ["telemetryEnabled": true]
        let monitor = BarAppMonitor(detector: fixture.detector())
        try fixture.makeFolder(fixture.defaultFolder(of: .codexBar), files: ["codexbar-logs-2026-10-12.jsonl"])

        fixture.preferences.domains["com.gordonbeeming.CodexBar"] = ["telemetryEnabled": false]
        monitor.refresh()

        #expect(monitor.status(of: .codexBar).state == .offWithHistory)
    }

    @Test("Turning Tracking on in a Bar App shows up on the next refresh")
    func trackingTurnedOn() throws {
        let fixture = try Fixture()
        fixture.locator.installedBundleIdentifiers = ["com.gordonbeeming.ClaudeBar"]
        let monitor = BarAppMonitor(detector: fixture.detector())
        #expect(monitor.status(of: .claudeBar).state == .off)

        fixture.preferences.domains["com.gordonbeeming.ClaudeBar"] = ["telemetryEnabled": true]
        monitor.refresh()

        #expect(monitor.status(of: .claudeBar).state == .tracking)
    }

    @Test("Settings a Bar App applies show up on the next refresh, without a relaunch")
    func appliedSettingsShowUp() throws {
        let fixture = try Fixture()
        let custom = fixture.home.appendingPathComponent("Moved", isDirectory: true)
        fixture.locator.installedBundleIdentifiers = ["com.gordonbeeming.CodexBar"]
        fixture.preferences.domains["com.gordonbeeming.CodexBar"] = [
            "telemetryEnabled": true,
            "telemetryIntervalMinutes": 5,
            "telemetryRetentionDays": 30
        ]
        let monitor = BarAppMonitor(detector: fixture.detector())

        fixture.preferences.domains["com.gordonbeeming.CodexBar"] = [
            "telemetryEnabled": true,
            "telemetryIntervalMinutes": 30,
            "telemetryRetentionDays": 0,
            "telemetryDirectory": custom.path
        ]
        monitor.refresh()

        #expect(monitor.status(of: .codexBar).settings == TrackingSettings(
            enabled: true,
            intervalMinutes: 30,
            retentionDays: 0,
            folder: custom
        ))
    }

    @Test("States carry the sidebar's labels")
    func stateTitles() {
        #expect(TrackingState.allCases.map(\.title) == ["Tracking", "Off", "Off with History", "Not installed"])
    }
}
