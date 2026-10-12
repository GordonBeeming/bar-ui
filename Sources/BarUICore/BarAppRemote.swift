import Foundation

/// Hands a URL to whatever app claims its scheme. The app target backs this
/// with NSWorkspace; tests record instead of launching a real Bar App.
public protocol URLOpening: Sendable {
    func open(_ url: URL) async throws
}

/// Asks a Bar App to do something through its URL scheme. It never applies
/// anything itself: the Bar App confirms and writes its own settings, and
/// Bar UI sees the result through `BarAppMonitor`.
public struct BarAppRemote: Sendable {
    private let opener: any URLOpening

    public init(opener: any URLOpening) {
        self.opener = opener
    }

    public func requestTrackingChange(
        of app: BarApp,
        from current: TrackingSettings,
        to edited: TrackingSettings
    ) async throws {
        let url = try BarAppCommand.changeTracking(of: app, from: current, to: edited)
        try await opener.open(url)
    }

    public func openSettings(of app: BarApp) async throws {
        try await opener.open(BarAppCommand.openSettings(of: app))
    }
}
