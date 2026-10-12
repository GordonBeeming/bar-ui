import Foundation
import Testing
@testable import BarUICore

@Suite("Asking a Bar App to change")
struct BarAppRemoteTests {
    private let current = TrackingSettings(
        enabled: false,
        intervalMinutes: 5,
        retentionDays: 30,
        folder: URL(fileURLWithPath: "/Users/me/Documents/CodexBar Telemetry", isDirectory: true)
    )

    @Test("Sending a change opens the Bar App's telemetry URL with the changed settings")
    func sendsChange() async throws {
        let opener = FakeURLOpener()
        let remote = BarAppRemote(opener: opener)
        var edited = current
        edited.enabled = true
        edited.intervalMinutes = 10

        try await remote.requestTrackingChange(of: .codexBar, from: current, to: edited)

        #expect(opener.opened.map(\.absoluteString) == ["codexbar://telemetry?enabled=1&interval=10"])
    }

    @Test("A change that can't be sent opens nothing")
    func invalidChangeOpensNothing() async {
        let opener = FakeURLOpener()
        let remote = BarAppRemote(opener: opener)
        var edited = current
        edited.intervalMinutes = 0

        await #expect(throws: TrackingChangeError.intervalOutOfRange(0)) {
            try await remote.requestTrackingChange(of: .codexBar, from: current, to: edited)
        }
        #expect(opener.opened.isEmpty)
    }

    @Test("When macOS can't open the URL, the failure reaches the caller")
    func openFailure() async {
        let opener = FakeURLOpener()
        opener.failure = FakeURLOpener.Failure.noHandler
        let remote = BarAppRemote(opener: opener)
        var edited = current
        edited.enabled = true

        await #expect(throws: FakeURLOpener.Failure.noHandler) {
            try await remote.requestTrackingChange(of: .codexBar, from: current, to: edited)
        }
    }

    @Test("Bar App settings… opens the Bar App's own settings window")
    func opensSettings() async throws {
        let opener = FakeURLOpener()
        let remote = BarAppRemote(opener: opener)

        try await remote.openSettings(of: .claudeBar)

        #expect(opener.opened.map(\.absoluteString) == ["claudebar://settings"])
    }
}

/// Records URLs instead of handing them to macOS, so tests never launch or
/// prompt a real Bar App.
final class FakeURLOpener: URLOpening, @unchecked Sendable {
    enum Failure: Error {
        case noHandler
    }

    var opened: [URL] = []
    var failure: Failure?

    func open(_ url: URL) async throws {
        if let failure {
            throw failure
        }
        opened.append(url)
    }
}
