import Foundation
import Testing
@testable import BarUICore

@Suite("Overview events timeline")
struct OverviewEventsTests {
    private static let second: Int64 = 1_000_000_000
    private static let t0: Int64 = 1_791_791_100 * second
    private static let minute = 60 * second
    private static let utc = TimeZone(identifier: "UTC") ?? .gmt
    private static let locale = Locale(identifier: "en_US")

    private let session = LimitDescriptor(id: "session", name: "Session (5h)", windowDurationMinutes: 300, modelID: nil)

    private func timeline(
        histories: [LimitHistory] = [],
        limitEvents: [LimitLifecycleEvent] = [],
        trackingStarts: [TrackingStartedEvent] = [],
        perkAvailable: [PerkAvailableEvent] = [],
        gonePerks: [GonePerk] = []
    ) -> [OverviewEvent] {
        OverviewEvent.timeline(
            histories: histories,
            limitEvents: limitEvents,
            trackingStarts: trackingStarts,
            perkAvailable: perkAvailable,
            gonePerks: gonePerks,
            locale: Self.locale,
            timeZone: Self.utc
        )
    }

    private func history(of app: BarApp = .claudeBar, utilization: [Double] = [], resets: [LimitReset] = []) -> LimitHistory {
        LimitHistory(
            app: app,
            limit: session,
            utilization: utilization.enumerated().map { ArchivedSample(timeUnixNano: Self.t0 + Int64($0.offset) * Self.minute, value: $0.element) },
            latest: nil,
            resets: resets
        )
    }

    @Test("A reset says how much of the Limit went unused")
    func resetDetail() {
        let reset = LimitReset(app: .claudeBar, limit: session, timeUnixNano: Self.t0, utilizationLast: 71.5, nextResetsAt: nil)

        let events = timeline(histories: [history(resets: [reset])])

        #expect(events.count == 1)
        #expect(events.first?.kind == .limitReset)
        #expect(events.first?.app == .claudeBar)
        #expect(events.first?.title == "Session (5h) reset")
        #expect(events.first?.detail == "29% unused at reset")
        #expect(events.first?.date == Date(unixNano: Self.t0))
    }

    @Test("Limits appearing and disappearing, and Tracking starting, each have a title and a detail line")
    func lifecycleDetails() {
        let events = timeline(
            limitEvents: [
                LimitLifecycleEvent(app: .codexBar, limit: session, kind: .appeared, timeUnixNano: Self.t0 + 3 * Self.minute),
                LimitLifecycleEvent(app: .codexBar, limit: session, kind: .disappeared, timeUnixNano: Self.t0 + 2 * Self.minute)
            ],
            trackingStarts: [
                TrackingStartedEvent(app: .claudeBar, intervalMinutes: 5, timeUnixNano: Self.t0 + Self.minute),
                TrackingStartedEvent(app: .claudeBar, intervalMinutes: 1, timeUnixNano: Self.t0)
            ]
        )

        #expect(events.map(\.title) == ["Session (5h) appeared", "Session (5h) disappeared", "Tracking started", "Tracking started"])
        #expect(events.map(\.detail) == ["5 hour window", "The Bar App stopped reporting it", "Sampling every 5 minutes", "Sampling every minute"])
        #expect(events.map(\.kind) == [.limitAppeared, .limitDisappeared, .trackingStarted, .trackingStarted])
    }

    @Test("Perks that became available show what and when they expire; Perks that went show the reason")
    func perkDetails() {
        let expiry: Int64 = 1_792_000_000
        let events = timeline(
            perkAvailable: [
                PerkAvailableEvent(app: .claudeBar, kind: .guestPass, currency: nil, quantity: 2, perkID: nil, expiresAt: expiry, timeUnixNano: Self.t0),
                PerkAvailableEvent(app: .claudeBar, kind: .creditGrant, currency: "USD", quantity: 12.5, perkID: nil, expiresAt: nil, timeUnixNano: Self.t0 + Self.minute)
            ],
            gonePerks: [
                GonePerk(
                    app: .codexBar, kind: .resetCredit, currency: nil, quantity: 1, perkID: "rc-1",
                    expiresAt: nil, goneAt: Date(unixNano: Self.t0 + 2 * Self.minute), reason: .used
                )
            ]
        )

        #expect(events.map(\.title) == ["Reset Credit gone", "Credit Grant available", "Guest Pass available"])
        #expect(events.map(\.detail) == ["1 Reset Credit · Used", "$12.50 Credit Grant", "2 Guest Passes · expires Oct 14"])
        #expect(events.map(\.kind) == [.perkGone, .perkAvailable, .perkAvailable])
    }

    @Test("Events from both Bar Apps are merged newest first")
    func mergesInTimeOrder() {
        let claudeReset = LimitReset(app: .claudeBar, limit: session, timeUnixNano: Self.t0, utilizationLast: 50, nextResetsAt: nil)
        let codexReset = LimitReset(app: .codexBar, limit: session, timeUnixNano: Self.t0 + 5 * Self.minute, utilizationLast: 10, nextResetsAt: nil)

        let events = timeline(
            histories: [history(of: .claudeBar, resets: [claudeReset]), history(of: .codexBar, resets: [codexReset])],
            trackingStarts: [TrackingStartedEvent(app: .claudeBar, intervalMinutes: 5, timeUnixNano: Self.t0 + 2 * Self.minute)]
        )

        #expect(events.map(\.app) == [.codexBar, .claudeBar, .claudeBar])
        #expect(events.map(\.date) == [5, 2, 0].map { Date(unixNano: Self.t0 + $0 * Self.minute) })
        #expect(Set(events.map(\.id)).count == 3)
    }

    @Test("A Limit hovering on a threshold is running low once, not every time it dips back under")
    func flappingIsOneEvent() {
        let events = timeline(histories: [history(utilization: [74.9, 75.1, 74.8, 75.2])])

        #expect(events.map(\.kind) == [.runningLow])
        #expect(events.map(\.date) == [Date(unixNano: Self.t0 + Self.minute)])
    }

    @Test("After a reset the new Window starts from normal, so climbing again is a new event")
    func resetStartsANewWindow() {
        let resetAt = Self.t0 + Self.minute + Self.minute / 2
        let reset = LimitReset(app: .claudeBar, limit: session, timeUnixNano: resetAt, utilizationLast: 85, nextResetsAt: nil)

        let events = timeline(histories: [history(utilization: [70, 85, 80], resets: [reset])])

        #expect(events.map(\.kind) == [.runningLow, .limitReset, .runningLow])
        #expect(events.map(\.date) == [Self.t0 + 2 * Self.minute, resetAt, Self.t0 + Self.minute].map { Date(unixNano: $0) })
    }

    @Test("A range that opens on a reset starts that Window from normal, so its first high sample is a crossing")
    func rangeOpeningOnAReset() {
        let reset = LimitReset(app: .claudeBar, limit: session, timeUnixNano: Self.t0 - Self.minute, utilizationLast: 60, nextResetsAt: nil)

        let events = timeline(histories: [history(utilization: [80], resets: [reset])])

        #expect(events.map(\.kind) == [.runningLow, .limitReset])
        #expect(events.first?.date == Date(unixNano: Self.t0))
    }

    @Test("Within one Window a Limit is near limit at most once, even after falling back")
    func onceEachPerWindow() {
        let events = timeline(histories: [history(utilization: [40, 76, 80, 91, 95, 20, 91])])

        #expect(events.map(\.kind) == [.nearLimit, .runningLow])
        #expect(events.map(\.title) == ["Session (5h) near limit", "Session (5h) running low"])
        #expect(events.map(\.detail) == ["Reached 91% used", "Reached 76% used"])
        #expect(events.map(\.date) == [3, 1].map { Date(unixNano: Self.t0 + $0 * Self.minute) })
    }

    @Test("A Limit whose first sample is already high has no crossing to report")
    func firstSampleIsNotACrossing() {
        #expect(timeline(histories: [history(utilization: [80, 85])]).isEmpty)
    }

    @Test("An event type nobody has recorded yet leaves an empty timeline")
    func empty() {
        #expect(timeline().isEmpty)
    }
}
