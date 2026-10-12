import Foundation
import Observation

/// How far back a Bar App's Limit history reaches.
public enum HistoryRange: String, CaseIterable, Sendable, Hashable, Identifiable {
    case day
    case week
    case month
    case all

    public var id: String {
        rawValue
    }

    public var title: String {
        switch self {
        case .day: "24 hours"
        case .week: "7 days"
        case .month: "30 days"
        case .all: "All time"
        }
    }

    func start(from now: Date) -> Date? {
        switch self {
        case .day: now.addingTimeInterval(-24 * 3600)
        case .week: now.addingTimeInterval(-7 * 24 * 3600)
        case .month: now.addingTimeInterval(-30 * 24 * 3600)
        case .all: nil
        }
    }
}

/// Reads a Bar App's Limit history out of the Archive for its page.
@MainActor
@Observable
public final class LimitHistoryModel {
    public private(set) var rows: [LimitHistoryRow] = []
    public private(set) var problem: String?

    private let archive: Archive
    private var loadedApp: BarApp?

    public init(archive: Archive) {
        self.archive = archive
    }

    public func load(app: BarApp, range: HistoryRange, now: Date) async {
        if loadedApp != app {
            // Another Bar App's Limits mustn't sit on this page while its own
            // are being read.
            rows = []
            loadedApp = app
        }
        do {
            let histories = try await archive.limitHistories(of: app, since: range.start(from: now))
            guard loadedApp == app, !Task.isCancelled else {
                return
            }
            rows = LimitHistoryRow.rows(from: histories)
            problem = nil
        } catch {
            // Keep the rows already on screen: a failed read says nothing
            // about them, and the next poll may succeed.
            problem = error.localizedDescription
        }
    }
}
