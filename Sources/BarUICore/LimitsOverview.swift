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
    private var allEvents: [OverviewEvent] = []
    public private(set) var states: [BarApp: TrackingState] = [:]
    /// Why the last refresh couldn't read everything, for the Overview to show.
    public private(set) var problem: String?

    /// Per Bar App, what was dropped for not following the Telemetry Spec.
    /// A Bar App with nothing dropped has no entry.
    public private(set) var skippedRecords: [BarApp: SkippedRecordsNotice] = [:]

    /// When an import pass last finished reading at least one Telemetry
    /// Folder. Nil until one has, including when no Bar App has a folder.
    public private(set) var lastImportedAt: Date?

    private let archive: Archive
    private let importer: TelemetryImporter
    private let now: @MainActor () -> Date
    private var latestStatuses: [BarApp: BarAppStatus] = [:]
    private var requestedPasses = 0
    private var finishedPasses = 0
    private var runningPass: Task<Void, Never>?

    public init(archive: Archive, now: @escaping @MainActor () -> Date = { Date() }) {
        self.archive = archive
        self.importer = TelemetryImporter(archive: archive)
        self.now = now
    }

    /// The folders an import pass reads, and so the ones worth watching.
    public nonisolated static func telemetryFolders(in statuses: [BarApp: BarAppStatus]) -> [BarApp: URL] {
        statuses.compactMapValues { status in
            // History counts too: a Bar App with Tracking off still deletes
            // old files on retention, so it is imported before it's lost.
            status.state == .notInstalled ? nil : status.telemetryFolder
        }
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

    /// The Events list for a range, newest first, from every Bar App.
    public func events(range: TokenRange, now: Date) -> [OverviewEvent] {
        OverviewEvent.within(allEvents, range: range, now: now)
    }

    /// Imports what's new and reloads the Overview. Returns once a pass that
    /// started after this call has finished, so the caller sees anything
    /// written before it asked. Calls that arrive during a pass share the one
    /// pass that follows it rather than queuing one each.
    public func refresh(statuses: [BarApp: BarAppStatus]) async {
        states = statuses.mapValues(\.state)
        latestStatuses = statuses
        requestedPasses += 1
        let request = requestedPasses
        while finishedPasses < request {
            if let runningPass {
                // That pass may have listed its files before this call's
                // change landed, so wait for it and then go round again.
                await runningPass.value
                continue
            }
            let covers = requestedPasses
            let statuses = latestStatuses
            let pass = Task {
                await importPass(statuses: statuses)
                // Set inside the pass so every waiter sees it as soon as the
                // pass's value is ready, before any of them loops again.
                finishedPasses = max(finishedPasses, covers)
                runningPass = nil
            }
            runningPass = pass
            await pass.value
        }
    }

    private func importPass(statuses: [BarApp: BarAppStatus]) async {
        var problems: [String] = []
        var imported = false
        let folders = Self.telemetryFolders(in: statuses)
        for app in BarApp.allCases {
            guard let folder = folders[app] else {
                continue
            }
            do {
                let summary = try await importer.importMetrics(of: app, from: folder)
                imported = true
                for (file, reason) in summary.failures.sorted(by: { $0.key < $1.key }) {
                    problems.append("\(app.displayName) \(file): \(reason)")
                }
            } catch {
                problems.append("\(app.displayName): \(error.localizedDescription)")
            }
        }
        if imported {
            lastImportedAt = now()
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

        do {
            var histories: [LimitHistory] = []
            for app in BarApp.allCases {
                histories += try await archive.limitHistories(of: app, since: nil)
            }
            allEvents = OverviewEvent.timeline(
                histories: histories,
                limitEvents: try await archive.limitLifecycleEvents(),
                trackingStarts: try await archive.trackingStarts(),
                perkAvailable: try await archive.perkAvailableEvents(),
                gonePerks: goneEver
            )
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
