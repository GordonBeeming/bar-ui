import Foundation
import Testing
@testable import BarUICore

@Suite("Limit pace and reset text")
struct LimitPaceTextTests {
    /// Mon 12 Oct 2026, 07:50 UTC.
    private static let now = Date(timeIntervalSince1970: 1_791_791_400)

    private static var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        if let zone = TimeZone(identifier: "UTC") {
            calendar.timeZone = zone
        }
        calendar.locale = Locale(identifier: "en_US")
        return calendar
    }

    // Typed up front so the @Test macro doesn't have to infer the tuples.
    // (Utilization %, share of the Window gone, expected text.)
    private static let paces: [(Double, Double?, String?)] = [
        (55, 0.58, "3% headroom"),
        (20, 0.10, "10% over"),
        (30, 0.30, "0% headroom"),
        (30.2, 0.30, "<1% over"),
        (29.8, 0.30, "<1% headroom"),
        (30, nil, nil),
        (0, 0.02, nil),
        (4.9, 0.30, nil),
        (5, 0.30, "25% headroom")
    ]

    @Test("How far usage is from an even spread over the Window, as a number either way", arguments: paces)
    func pace(utilization: Double, elapsed: Double?, expected: String?) {
        #expect(LimitCard.paceText(utilization: utilization, windowElapsed: elapsed) == expected)
    }

    // (Utilization %, share of the Window gone, expected side: 1 over, -1 headroom, 0 on the line.)
    private static let sides: [(Double, Double?, Int?)] = [
        (55, 0.58, -1),
        (20, 0.10, 1),
        (30.2, 0.30, 1),
        (29.8, 0.30, -1),
        (30, 0.30, 0),
        (30, nil, nil),
        (4.9, 0.01, nil)
    ]

    @Test("The side comes from the unrounded gap, so a fraction past the tick still counts as over", arguments: sides)
    func side(utilization: Double, elapsed: Double?, expected: Int?) {
        let gap = LimitCard.paceGap(utilization: utilization, windowElapsed: elapsed)
        #expect(gap.map { $0 > 0 ? 1 : $0 < 0 ? -1 : 0 } == expected)
    }

    // (Seconds from now until the reset, expected text.)
    private static let resets: [(TimeInterval?, String)] = [
        (95 * 60, "Resets 9:25 AM · in 1h 35m"),
        (33 * 3_600 + 10 * 60, "Resets Tomorrow 5:00 PM · in 1d 9h"),
        (3 * 86_400 + 9 * 3_600 + 10 * 60, "Resets Thu 5:00 PM · in 3d 9h"),
        (10 * 86_400, "Resets Oct 22, 7:50 AM · in 10d"),
        (0, "Resetting now"),
        (nil, "Reset time unknown")
    ]

    @Test("The reset reads as a clock time and a countdown", arguments: resets)
    func resetDetail(seconds: TimeInterval?, expected: String) {
        let resetsAt = seconds.map { Self.now.addingTimeInterval($0) }

        let text = LimitCard.resetDetail(until: resetsAt, now: Self.now, calendar: Self.utc)

        // Newer ICU puts a narrow no-break space before AM/PM.
        #expect(text.replacingOccurrences(of: "\u{202F}", with: " ") == expected)
    }
}
