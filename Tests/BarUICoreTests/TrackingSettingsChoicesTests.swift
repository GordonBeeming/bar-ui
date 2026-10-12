import Foundation
import Testing
@testable import BarUICore

@Suite("Tracking settings choices and labels")
struct TrackingSettingsChoicesTests {
    @Test("The interval picker offers the presets")
    func intervalPresets() {
        #expect(TrackingSettingsChoices.intervals(current: 5) == [1, 5, 15, 60])
    }

    @Test("An interval the Bar App saved outside the presets is still offered, in order, so the sheet can show it")
    func customIntervalOffered() {
        #expect(TrackingSettingsChoices.intervals(current: 30) == [1, 5, 15, 30, 60])
        #expect(TrackingSettingsChoices.intervals(current: nil) == [1, 5, 15, 60])
    }

    @Test("The retention picker offers the presets, forever last, plus any saved custom value")
    func retentionChoices() {
        #expect(TrackingSettingsChoices.retentions(current: 0) == [30, 90, 0])
        #expect(TrackingSettingsChoices.retentions(current: 7) == [7, 30, 90, 0])
    }

    @Test("Intervals read the way the design writes them")
    func intervalTitles() {
        #expect(TrackingSettingsChoices.intervalTitle(1) == "Every 1 minute")
        #expect(TrackingSettingsChoices.intervalTitle(5) == "Every 5 minutes")
        #expect(TrackingSettingsChoices.intervalTitle(60) == "Every hour")
        #expect(TrackingSettingsChoices.intervalTitle(120) == "Every 2 hours")
        #expect(TrackingSettingsChoices.intervalTitle(90) == "Every 90 minutes")
    }

    @Test("Retention reads as days, with 0 as Forever")
    func retentionTitles() {
        #expect(TrackingSettingsChoices.retentionTitle(0) == "Forever")
        #expect(TrackingSettingsChoices.retentionTitle(1) == "1 day")
        #expect(TrackingSettingsChoices.retentionTitle(90) == "90 days")
    }

    @Test("The page summary names the state, interval, retention and folder, with home shortened to ~")
    func summaryTracking() {
        let home = URL(fileURLWithPath: "/Users/me", isDirectory: true)
        let settings = TrackingSettings(
            enabled: true,
            intervalMinutes: 5,
            retentionDays: 0,
            folder: URL(fileURLWithPath: "/Users/me/Documents/ClaudeBar Telemetry", isDirectory: true)
        )

        #expect(TrackingSettingsChoices.summary(of: settings, home: home)
            == "Tracking · every 5 min · keeps files forever · ~/Documents/ClaudeBar Telemetry")
    }

    @Test("A folder typed with ~ or as a full path becomes that folder")
    func parsesTypedFolder() throws {
        let home = URL(fileURLWithPath: "/Users/me", isDirectory: true)

        #expect(try TrackingSettingsChoices.folder(fromDisplayPath: "~/Documents/My Telemetry", home: home).path
            == "/Users/me/Documents/My Telemetry")
        #expect(try TrackingSettingsChoices.folder(fromDisplayPath: "  /Volumes/Data/T/  ", home: home).path
            == "/Volumes/Data/T")
    }

    @Test("A typed folder that isn't a full path is refused rather than guessed at")
    func refusesRelativeFolder() {
        let home = URL(fileURLWithPath: "/Users/me", isDirectory: true)

        #expect(throws: TrackingChangeError.folderNotAbsolute("Documents/T")) {
            try TrackingSettingsChoices.folder(fromDisplayPath: "Documents/T", home: home)
        }
        #expect(throws: TrackingChangeError.folderNotAbsolute("~other/T")) {
            try TrackingSettingsChoices.folder(fromDisplayPath: "~other/T", home: home)
        }
    }

    @Test("The summary leaves out what the Bar App hasn't set, and doesn't shorten a folder outside home")
    func summaryOff() {
        let home = URL(fileURLWithPath: "/Users/me", isDirectory: true)
        let settings = TrackingSettings(
            enabled: false,
            intervalMinutes: nil,
            retentionDays: 30,
            folder: URL(fileURLWithPath: "/Users/meg/Telemetry", isDirectory: true)
        )

        #expect(TrackingSettingsChoices.summary(of: settings, home: home)
            == "Tracking off · keeps files 30 days · /Users/meg/Telemetry")
    }
}
