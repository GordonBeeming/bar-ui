import Foundation
import Observation

/// Keeps the Overview's Limits in step with the Archive: each refresh imports
/// whatever the Bar Apps have appended since the last one, then reads the
/// current Limits back out of the Archive, never straight from the files.
@MainActor
@Observable
public final class LimitsOverview {
    public private(set) var limits: [CurrentLimit] = []
    public private(set) var tokenSamples: [TokenSample] = []
    private var availableNow: [AvailablePerk] = []
    private var goneEver: [GonePerk] = []
    public private(set) var states: [BarApp: TrackingState] = [:]
    /// Why the last refresh couldn't read everything, for the Overview to show.
    public private(set) var problem: String?

    /// Per Bar App, what was dropped for not following the Telemetry Spec.
    /// A Bar App with nothing dropped has no entry.
    public private(set) var skippedRecords: [BarApp: SkippedRecordsNotice] = [:]

    private let archive: Archive
    private let importer: TelemetryImporter
    private var isRefreshing = false

    public init(archive: Archive) {
        self.archive = archive
        self.importer = TelemetryImporter(archive: archive)
    }

    public func cards(now: Date) -> [LimitCard] {
        LimitCard.cards(for: limits, states: states, now: now)
    }

    public func tokenUsage(range: TokenRange, now: Date, calendar: Calendar = .current) -> TokenUsage {
        TokenUsage(samples: tokenSamples, range: range, now: now, calendar: calendar)
    }

    public func availablePerks(of app: BarApp) -> [AvailablePerk] {
        availableNow.filter { $0.app == app }
    }

    public func gonePerks(of app: BarApp) -> [GonePerk] {
        goneEver.filter { $0.app == app }
    }

    public func refresh(statuses: [BarApp: BarAppStatus]) async {
        states = statuses.mapValues(\.state)
        // A poll and an app activation can both ask while an import is still
        // reading; a second pass over the same files would only find nothing.
        guard !isRefreshing else {
            return
        }
        isRefreshing = true
        defer { isRefreshing = false }

        var problems: [String] = []
        for app in BarApp.allCases {
            // History counts too: a Bar App with Tracking off still deletes
            // old files on retention, so it is imported before it's lost.
            guard let status = statuses[app], status.state != .notInstalled, let folder = status.telemetryFolder else {
                continue
            }
            do {
                let summary = try await importer.importMetrics(of: app, from: folder)
                for (file, reason) in summary.failures.sorted(by: { $0.key < $1.key }) {
                    problems.append("\(app.displayName) \(file): \(reason)")
                }
            } catch {
                problems.append("\(app.displayName): \(error.localizedDescription)")
            }
        }

        do {
            limits = try await archive.currentLimits()
            availableNow = try await archive.availablePerks()
            goneEver = try await archive.gonePerks()
        } catch {
            problems.append(error.localizedDescription)
        }
        do {
            tokenSamples = try await archive.tokenSamples()
        } catch {
            problems.append(error.localizedDescription)
        }

        var notices: [BarApp: SkippedRecordsNotice] = [:]
        for app in BarApp.allCases {
            do {
                notices[app] = SkippedRecordsNotice(days: try await archive.skippedRecords(of: app))
            } catch {
                problems.append(error.localizedDescription)
            }
        }
        skippedRecords = notices
        problem = problems.isEmpty ? nil : problems.joined(separator: "\n")
    }
}
