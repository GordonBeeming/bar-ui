import Foundation
import Testing
@testable import BarUICore

/// Runs against the real preferences system, with `/usr/bin/defaults` standing
/// in for a Bar App writing its own domain from another process.
@Suite("System preferences", .serialized)
struct SystemPreferencesTests {
    /// Fixed rather than unique per run: `defaults delete` leaves an empty
    /// plist behind, and one reused file is easier to clean than one per run.
    private let domain = "com.gordonbeeming.BarUITests.SystemPreferences"

    @Test("A setting another process changes is read without restarting")
    func readsChangesFromAnotherProcess() throws {
        // Clears anything an interrupted earlier run left; it fails when the
        // domain is already gone, which is the state we want.
        try? runDefaults(["delete", domain])
        defer { removeDomain() }
        let preferences = SystemPreferences()

        try runDefaults(["write", domain, "telemetryEnabled", "-bool", "true"])
        #expect(preferences.value(forKey: "telemetryEnabled", inDomain: domain) as? Bool == true)

        try runDefaults(["write", domain, "telemetryEnabled", "-bool", "false"])
        #expect(preferences.value(forKey: "telemetryEnabled", inDomain: domain) as? Bool == false)

        try runDefaults(["write", domain, "telemetryDirectory", "/tmp/Somewhere Else"])
        #expect(preferences.value(forKey: "telemetryDirectory", inDomain: domain) as? String == "/tmp/Somewhere Else")
    }

    @Test("A key that was never set reads as nil")
    func missingKey() {
        let unusedDomain = "com.gordonbeeming.BarUITests.\(UUID().uuidString)"

        #expect(SystemPreferences().value(forKey: "telemetryEnabled", inDomain: unusedDomain) == nil)
    }

    private func removeDomain() {
        do {
            try runDefaults(["delete", domain])
            let file = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Preferences/\(domain).plist")
            try FileManager.default.removeItem(at: file)
        } catch {
            Issue.record(error, "Couldn't clean up test defaults domain \(domain)")
        }
    }

    private func runDefaults(_ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
        process.arguments = arguments
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw DefaultsCommandFailed(arguments: arguments, status: process.terminationStatus)
        }
    }
}

private struct DefaultsCommandFailed: Error {
    let arguments: [String]
    let status: Int32
}
