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
    /// setting to read, so any folder named here would be a guess.
    public let telemetryFolder: URL?

    public init(state: TrackingState, telemetryFolder: URL?) {
        self.state = state
        self.telemetryFolder = telemetryFolder
    }

    public static let notInstalled = BarAppStatus(state: .notInstalled, telemetryFolder: nil)
}
