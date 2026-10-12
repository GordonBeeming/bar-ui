import Foundation
import Testing
@testable import BarUICore

@Suite("Burn Rate")
struct BurnRateTests {
    private static let base: Int64 = 1_791_000_000_000_000_000
    private static let now = date(0)

    private static func date(_ minutes: Int) -> Date {
        Date(unixNano: base + Int64(minutes) * 60 * 1_000_000_000)
    }

    private static func samples(_ points: [(minutes: Int, percent: Double)]) -> [ArchivedSample] {
        points.map { ArchivedSample(timeUnixNano: base + Int64($0.minutes) * 60 * 1_000_000_000, value: $0.percent) }
    }

    @Test("The rate is percentage points gained per hour across the last hour's samples")
    func risesOverTheLastHour() throws {
        let rate = try #require(BurnRate(
            samples: Self.samples([(-60, 10), (-30, 20), (0, 30)]),
            resetTimes: [],
            now: Self.now
        ))

        #expect(rate.percentPerHour == 20)
    }

    @Test("Samples older than an hour don't count")
    func ignoresOlderSamples() throws {
        let rate = try #require(BurnRate(
            samples: Self.samples([(-300, 0), (-90, 50), (-40, 50), (0, 60)]),
            resetTimes: [],
            now: Self.now
        ))

        // 10 points over the 40 minutes the in-window samples span.
        #expect(rate.percentPerHour == 15)
    }

    @Test("One sample is not enough to say how fast anything is rising")
    func needsTwoSamples() {
        #expect(BurnRate(samples: Self.samples([(0, 30)]), resetTimes: [], now: Self.now) == nil)
        #expect(BurnRate(samples: [], resetTimes: [], now: Self.now) == nil)
    }

    @Test("Samples from before a reset are left out, so the fall isn't read as a negative rate")
    func rightAfterAReset() {
        let samples = Self.samples([(-50, 80), (-30, 90), (-10, 3)])

        // The reset event is known: only one sample follows it.
        #expect(BurnRate(samples: samples, resetTimes: [Self.date(-12)], now: Self.now) == nil)
        // No reset event yet, but utilisation fell, which is the same thing.
        #expect(BurnRate(samples: samples, resetTimes: [], now: Self.now) == nil)
    }

    @Test("After a reset the rate comes from the samples that follow it")
    func afterAResetWithSamples() throws {
        let rate = try #require(BurnRate(
            samples: Self.samples([(-50, 80), (-30, 90), (-20, 2), (-5, 5), (0, 6)]),
            resetTimes: [Self.date(-25)],
            now: Self.now
        ))

        // 4 points in 20 minutes.
        #expect(rate.percentPerHour == 12)
    }

    @Test("A reset that left utilisation unchanged still starts the count afresh")
    func resetWithoutAFall() throws {
        let rate = try #require(BurnRate(
            samples: Self.samples([(-40, 0), (-20, 0), (-10, 0), (0, 5)]),
            resetTimes: [Self.date(-15)],
            now: Self.now
        ))

        #expect(rate.percentPerHour == 30)
    }

    @Test("A newest sample more than an hour old gives no rate")
    func staleData() {
        #expect(BurnRate(samples: Self.samples([(-200, 10), (-190, 20)]), resetTimes: [], now: Self.now) == nil)
    }

    @Test("It would hit 100% when the remaining headroom is used up at this rate")
    func timeToFull() throws {
        let rate = try #require(BurnRate(samples: Self.samples([(-30, 40), (0, 50)]), resetTimes: [], now: Self.now))

        #expect(rate.percentPerHour == 20)
        #expect(rate.timeUntilFull(from: 50) == 2.5 * 3600)
    }

    @Test("A flat or falling rate, or a Limit already full, never reaches 100%")
    func neverFull() throws {
        let flat = try #require(BurnRate(samples: Self.samples([(-30, 40), (0, 40)]), resetTimes: [], now: Self.now))
        let rising = try #require(BurnRate(samples: Self.samples([(-30, 90), (0, 100)]), resetTimes: [], now: Self.now))

        #expect(flat.timeUntilFull(from: 40) == nil)
        #expect(rising.timeUntilFull(from: 100) == nil)
    }

    @Test("The projection only matters when 100% comes before the Window resets")
    func hitsBeforeReset() throws {
        let rate = try #require(BurnRate(samples: Self.samples([(-30, 40), (0, 50)]), resetTimes: [], now: Self.now))
        // 2h30m to full: after a reset in 2h, before one in 3h.
        #expect(rate.timeUntilFullBeforeReset(from: 50, resetsAt: Self.date(180), now: Self.now) == 2.5 * 3600)
        #expect(rate.timeUntilFullBeforeReset(from: 50, resetsAt: Self.date(120), now: Self.now) == nil)
        #expect(rate.timeUntilFullBeforeReset(from: 50, resetsAt: Self.date(-5), now: Self.now) == nil)
        #expect(rate.timeUntilFullBeforeReset(from: 50, resetsAt: nil, now: Self.now) == nil)
    }
}
