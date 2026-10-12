import Foundation
import Testing
@testable import BarUICore

@Suite("Bar App URL scheme")
struct BarAppCommandTests {
    private let current = TrackingSettings(
        enabled: false,
        intervalMinutes: 5,
        retentionDays: 30,
        folder: URL(fileURLWithPath: "/Users/me/Documents/ClaudeBar Telemetry", isDirectory: true)
    )

    @Test("Turning Tracking on sends only enabled=1, on the Bar App's own scheme")
    func turnOnOnly() throws {
        var edited = current
        edited.enabled = true

        let url = try BarAppCommand.changeTracking(of: .claudeBar, from: current, to: edited)

        #expect(url.absoluteString == "claudebar://telemetry?enabled=1")
    }

    @Test("CodexBar gets its own scheme")
    func codexScheme() throws {
        var edited = current
        edited.retentionDays = 0

        let url = try BarAppCommand.changeTracking(of: .codexBar, from: current, to: edited)

        #expect(url.absoluteString == "codexbar://telemetry?retention=0")
    }

    @Test("Every changed setting is sent, and only those")
    func severalChanges() throws {
        var edited = current
        edited.enabled = true
        edited.intervalMinutes = 15
        edited.folder = URL(fileURLWithPath: "/Volumes/Data/Claude & Co/Telemetry+1", isDirectory: true)

        let url = try BarAppCommand.changeTracking(of: .claudeBar, from: current, to: edited)

        #expect(url.absoluteString
            == "claudebar://telemetry?enabled=1&interval=15&folder=%2FVolumes%2FData%2FClaude%20%26%20Co%2FTelemetry%2B1")
    }

    @Test("A folder path survives the round trip through the URL exactly")
    func folderRoundTrip() throws {
        var edited = current
        edited.folder = URL(fileURLWithPath: "/Volumes/Data/Claude & Co/Telemetry+1=ü?#", isDirectory: true)

        let url = try BarAppCommand.changeTracking(of: .claudeBar, from: current, to: edited)
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))

        #expect(components.queryItems == [URLQueryItem(name: "folder", value: "/Volumes/Data/Claude & Co/Telemetry+1=ü?#")])
    }

    @Test("Turning Tracking off sends enabled=0")
    func turnOff() throws {
        var tracking = current
        tracking.enabled = true
        var edited = tracking
        edited.enabled = false

        let url = try BarAppCommand.changeTracking(of: .claudeBar, from: tracking, to: edited)

        #expect(url.absoluteString == "claudebar://telemetry?enabled=0")
    }

    @Test("The same folder written differently isn't a change")
    func equivalentFolderIsNotAChange() throws {
        var edited = current
        edited.enabled = true
        edited.folder = URL(fileURLWithPath: "/Users/me/Documents/../Documents/ClaudeBar Telemetry/", isDirectory: true)

        let url = try BarAppCommand.changeTracking(of: .claudeBar, from: current, to: edited)

        #expect(url.absoluteString == "claudebar://telemetry?enabled=1")
    }

    @Test("Nothing changed is refused, so the Bar App never shows an empty confirmation")
    func noChanges() {
        #expect(throws: TrackingChangeError.noChanges) {
            try BarAppCommand.changeTracking(of: .claudeBar, from: current, to: current)
        }
    }

    @Test("An interval outside 1 to 1440 minutes is refused before it is sent")
    func invalidInterval() {
        var edited = current
        edited.intervalMinutes = 1441

        #expect(throws: TrackingChangeError.intervalOutOfRange(1441)) {
            try BarAppCommand.changeTracking(of: .claudeBar, from: current, to: edited)
        }
    }

    @Test("A retention outside 0 to 3650 days is refused before it is sent")
    func invalidRetention() {
        var edited = current
        edited.retentionDays = -1

        #expect(throws: TrackingChangeError.retentionOutOfRange(-1)) {
            try BarAppCommand.changeTracking(of: .claudeBar, from: current, to: edited)
        }
    }

    @Test("Clearing a setting that was set can't be expressed in the URL, so it is refused")
    func clearingIsRefused() {
        var edited = current
        edited.intervalMinutes = nil

        #expect(throws: TrackingChangeError.cannotClear(.interval)) {
            try BarAppCommand.changeTracking(of: .claudeBar, from: current, to: edited)
        }
    }

    @Test("A Bar App's settings window has its own URL")
    func settingsURL() throws {
        #expect(try BarAppCommand.openSettings(of: .claudeBar).absoluteString == "claudebar://settings")
        #expect(try BarAppCommand.openSettings(of: .codexBar).absoluteString == "codexbar://settings")
    }
}
