import Foundation
import Testing
@testable import BarUICore

@Suite("Overview Limits strip")
struct LimitCardTests {
    private static let now = Date(timeIntervalSince1970: 1_791_791_400)

    private static func limit(
        _ app: BarApp,
        _ id: String,
        _ name: String,
        minutes: Int?,
        used: Double,
        resetsIn: TimeInterval? = 3_600
    ) -> CurrentLimit {
        CurrentLimit(
            app: app,
            limit: LimitDescriptor(id: id, name: name, windowDurationMinutes: minutes, modelID: nil),
            utilization: used,
            sampledAt: now,
            resetsAt: resetsIn.map { now.addingTimeInterval($0) }
        )
    }

    private static let bothTracking: [BarApp: TrackingState] = [.claudeBar: .tracking, .codexBar: .tracking]

    @Test("There's a card per Limit from every Tracking Bar App, shortest Window first within each app")
    func oneCardPerLimit() {
        let limits = [
            Self.limit(.codexBar, "codex:10080", "Weekly", minutes: 10080, used: 18.5),
            Self.limit(.claudeBar, "weekly_all", "Weekly (all models)", minutes: 10080, used: 61),
            Self.limit(.claudeBar, "session", "Session (5h)", minutes: 300, used: 42),
            Self.limit(.claudeBar, "weekly_scoped:Fable", "Weekly · Fable", minutes: nil, used: 19)
        ]

        let cards = LimitCard.cards(for: limits, states: Self.bothTracking, now: Self.now)

        #expect(cards.map(\.id) == [
            "claudeBar/session",
            "claudeBar/weekly_all",
            "claudeBar/weekly_scoped:Fable",
            "codexBar/codex:10080"
        ])
        #expect(cards.map(\.appName) == ["ClaudeBar", "ClaudeBar", "ClaudeBar", "CodexBar"])
        #expect(cards.map(\.windowName) == ["Session (5h)", "Weekly (all models)", "Weekly · Fable", "Weekly"])
        #expect(cards.map(\.percentUsed) == [42, 61, 19, 19])
    }

    @Test("Bar Apps that aren't Tracking have no cards, even with Limits in the Archive")
    func onlyTrackingBarApps() {
        let limits = [
            Self.limit(.codexBar, "codex:10080", "Weekly", minutes: 10080, used: 18),
            Self.limit(.claudeBar, "session", "Session (5h)", minutes: 300, used: 42)
        ]

        let cards = LimitCard.cards(for: limits, states: [.claudeBar: .offWithHistory, .codexBar: .tracking], now: Self.now)

        #expect(cards.map(\.id) == ["codexBar/codex:10080"])
    }

    @Test("Severity follows the design: running low from 75%, near the limit from 90%")
    func severity() {
        let limits = [74.9, 75, 89.9, 90, 100].enumerated().map { index, used in
            Self.limit(.claudeBar, "l\(index)", "L\(index)", minutes: 300, used: used)
        }

        let cards = LimitCard.cards(for: limits, states: Self.bothTracking, now: Self.now)

        #expect(cards.map(\.severity) == [.normal, .runningLow, .runningLow, .nearLimit, .nearLimit])
        #expect(cards.map(\.severity.label) == [nil, "Running low", "Running low", "Near limit", "Near limit"])
    }

    // Typed up front: inferred inside the @Test macro, this list takes the
    // compiler past its type-check time limit on slower machines.
    private static let countdowns: [(TimeInterval, String)] = [
        (2 * 3_600 + 14 * 60 + 30, "Resets in 2h 14m"),
        (14 * 60 + 59, "Resets in 14m"),
        (40, "Resets in under a minute"),
        (3 * 86_400 + 4 * 3_600 + 59 * 60, "Resets in 3d 4h"),
        (2 * 86_400, "Resets in 2d"),
        (3_600, "Resets in 1h"),
        (0, "Resetting now"),
        (-120, "Resetting now")
    ]

    @Test("Time until reset reads as a countdown", arguments: countdowns)
    func resetCountdown(resetsIn: TimeInterval, expected: String) {
        let limit = Self.limit(.codexBar, "codex:10080", "Weekly", minutes: 10080, used: 1, resetsIn: resetsIn)

        let card = LimitCard.cards(for: [limit], states: Self.bothTracking, now: Self.now).first

        #expect(card?.resetText == expected)
    }

    @Test("A Limit with no reset time on record says so")
    func unknownReset() {
        let limit = Self.limit(.codexBar, "codex:primary", "Weekly", minutes: nil, used: 1, resetsIn: nil)

        let card = LimitCard.cards(for: [limit], states: Self.bothTracking, now: Self.now).first

        #expect(card?.resetText == "Reset time unknown")
    }
}
