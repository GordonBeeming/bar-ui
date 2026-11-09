import Foundation
import Observation

/// Reads a Bar App's Limit history out of the Archive for its page.
@MainActor
@Observable
public final class LimitHistoryModel {
    public private(set) var rows: [LimitHistoryRow] = []
    public private(set) var problem: String?

    private let archive: Archive
    private var loaded: BarAppAccount?

    public init(archive: Archive) {
        self.archive = archive
    }

    public func load(app: BarApp, account accountID: String = BarAppAccount.defaultID, range: TimeRange, now: Date) async {
        let account = BarAppAccount(app: app, accountID: accountID)
        if loaded != account {
            // Another Bar App's or Account's Limits mustn't sit on this page while its own
            // are being read.
            rows = []
            loaded = account
        }
        do {
            let histories = try await archive.limitHistories(of: app, account: accountID, since: range.start(now: now))
            // The averages look back over their own span, not the chart's range.
            let resets = try await archive.limitResets(of: app, account: accountID)
            // A restart inside a silence is what marks Tracking as having been off.
            let starts = try await archive.trackingStarts(since: range.start(now: now))
                .filter { $0.app == app }
                .map { Date(unixNano: $0.timeUnixNano) }
            guard loaded == account, !Task.isCancelled else {
                return
            }
            rows = LimitHistoryRow.rows(from: histories, resets: resets, trackingStarts: starts, now: now)
            problem = nil
        } catch {
            // Keep the rows already on screen: a failed read says nothing
            // about them, and the next poll may succeed.
            problem = error.localizedDescription
        }
    }
}
