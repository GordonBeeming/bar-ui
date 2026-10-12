import Foundation
import Observation

/// Holds the latest status of every Bar App for the UI. Bar Apps don't
/// announce changes to their settings, so the owner calls `refresh()` on a
/// cadence (and on app activation) to pick up Tracking being switched.
@MainActor
@Observable
public final class BarAppMonitor {
    public private(set) var statuses: [BarApp: BarAppStatus]

    private let detector: BarAppDetector

    public init(detector: BarAppDetector) {
        self.detector = detector
        self.statuses = Self.detect(with: detector)
    }

    public func status(of app: BarApp) -> BarAppStatus {
        statuses[app] ?? .notInstalled
    }

    public func refresh() {
        let latest = Self.detect(with: detector)
        // Assigning an equal value still notifies observers, which would
        // redraw the sidebar on every poll for no change.
        if latest != statuses {
            statuses = latest
        }
    }

    private static func detect(with detector: BarAppDetector) -> [BarApp: BarAppStatus] {
        Dictionary(uniqueKeysWithValues: BarApp.allCases.map { ($0, detector.status(of: $0)) })
    }
}
