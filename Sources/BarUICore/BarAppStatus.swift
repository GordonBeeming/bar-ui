import Foundation

/// The four states a Bar App can be in, as the glossary defines them.
public enum TrackingState: Sendable, Hashable, CaseIterable {
    case tracking
    case off
    case offWithHistory
    case notInstalled

    public var title: String {
        switch self {
        case .tracking: "Tracking"
        case .off: "Off"
        case .offWithHistory: "Off with History"
        case .notInstalled: "Not installed"
        }
    }
}

public struct BarAppStatus: Sendable, Hashable {
    public let state: TrackingState
    /// Nil when the Bar App isn't installed: without the app there is no
    /// setting to read, so any value shown would be a guess.
    public let settings: TrackingSettings?

    public init(state: TrackingState, settings: TrackingSettings?) {
        self.state = state
        self.settings = settings
    }

    public var telemetryFolder: URL? {
        settings?.folder
    }

    public static let notInstalled = BarAppStatus(state: .notInstalled, settings: nil)
}
