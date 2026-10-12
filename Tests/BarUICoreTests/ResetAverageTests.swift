import Foundation
import Testing
@testable import BarUICore

@Suite("Average unused at reset")
struct ResetAverageTests {
    private static let now = Date(timeIntervalSince1970: 1_791_791_400)
    private static let day: TimeInterval = 86_400

    private static func reset(daysAgo: Double, used: Double) -> ResetAverage.Reset {
        ResetAverage.Reset(date: now.addingTimeInterval(-daysAgo * day), utilizationLast: used)
    }

    // Typed up front so the @Test macro doesn't have to infer the tuples.
    // (Window minutes, expected lookback in days, expected label.)
    private static let lookbacks: [(Int?, Double, String)] = [
        (300, 7, "last 7d"),
        (1_440, 7, "last 7d"),
        (10_080, 35, "last 5 weeks"),
        (43_200, 150, "last 5 Windows"),
        (nil, 7, "last 7d")
    ]

    @Test("Short Windows average the last week; longer ones the last five Windows", arguments: lookbacks)
    func lookback(minutes: Int?, days: Double, label: String) {
        let average = ResetAverage(resets: [], windowMinutes: minutes, now: Self.now)

        #expect(average.lookback == days * Self.day)
        #expect(average.label == label)
    }

    @Test("Only resets inside the lookback count, and quiet Windows under 10% used are left out")
    func filtersOldAndQuiet() throws {
        let average = ResetAverage(resets: [
            Self.reset(daysAgo: 1, used: 40),
            Self.reset(daysAgo: 2, used: 20),
            Self.reset(daysAgo: 3, used: 5),
            Self.reset(daysAgo: 3.5, used: 10),
            Self.reset(daysAgo: 9, used: 90)
        ], windowMinutes: 300, now: Self.now)

        // 60% and 80% unused average to 70%; 5% and exactly 10% used are too quiet, and 9 days is too old.
        let value = try #require(average.unusedPercent)
        #expect(abs(value - 70) < 1e-9)
        #expect(average.count == 2)
    }

    @Test("With nothing busy enough in the lookback there's no average")
    func nothingToAverage() {
        let average = ResetAverage(resets: [Self.reset(daysAgo: 1, used: 3)], windowMinutes: 300, now: Self.now)

        #expect(average.unusedPercent == nil)
        #expect(average.count == 0)
    }
}
