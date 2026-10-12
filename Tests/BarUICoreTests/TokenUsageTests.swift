import Foundation
import Testing
@testable import BarUICore

@Suite("Token usage per period")
struct TokenUsageTests {
    private static let second: Int64 = 1_000_000_000
    private static let hour: Int64 = 3_600 * second
    private static let day: Int64 = 24 * hour
    /// Midday UTC, so hourly and daily buckets never straddle `now` oddly.
    private static let now = Date(timeIntervalSince1970: 1_799_971_200 + 12 * 3_600)
    private static var nowNano: Int64 { Int64(now.timeIntervalSince1970) * second }

    private static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        return calendar
    }

    private static func sample(
        _ type: TokenType,
        app: BarApp = .claudeBar,
        model: String = "m",
        start: Int64 = 1,
        agoHours: Int64,
        count: Int64
    ) -> TokenSample {
        TokenSample(app: app, model: model, tokenType: type, startTimeUnixNano: start, timeUnixNano: nowNano - agoHours * hour, count: count)
    }

    private static func usage(_ samples: [TokenSample], _ range: TimeRange) -> TokenUsage {
        TokenUsage(samples: samples, range: range, now: now, calendar: calendar)
    }

    @Test("Usage is the growth of a cumulative counter, and only the part inside the range counts")
    func growthWithinRange() {
        let samples = [
            Self.sample(.output, agoHours: 30, count: 100),
            Self.sample(.output, agoHours: 10, count: 160),
            Self.sample(.output, agoHours: 2, count: 200)
        ]

        #expect(Self.usage(samples, .day).output == 100)
        #expect(Self.usage(samples, .week).output == 200)
        #expect(Self.usage(samples, .all).output == 200)
    }

    @Test("A counter restart adds the new count in full and never goes negative or double counts")
    func counterRestart() {
        let samples = [
            Self.sample(.input, start: 1, agoHours: 8, count: 500),
            Self.sample(.input, start: 1, agoHours: 6, count: 800),
            Self.sample(.input, start: 2, agoHours: 4, count: 50),
            Self.sample(.input, start: 2, agoHours: 2, count: 70)
        ]

        let usage = Self.usage(samples, .day)

        #expect(usage.input == 870)
        #expect(usage.total == 870)
        #expect(usage.buckets.allSatisfy { $0.tokensByApp.values.allSatisfy { $0 >= 0 } })
    }

    @Test("A restart whose count lands above the old one is still a restart")
    func restartAboveOldCount() {
        let samples = [
            Self.sample(.output, start: 1, agoHours: 6, count: 100),
            Self.sample(.output, start: 2, agoHours: 3, count: 400)
        ]

        #expect(Self.usage(samples, .day).output == 500)
    }

    @Test("A count that falls under the same start is not usage")
    func fallWithoutRestart() {
        let samples = [
            Self.sample(.output, agoHours: 6, count: 100),
            Self.sample(.output, agoHours: 4, count: 40),
            Self.sample(.output, agoHours: 2, count: 55)
        ]

        #expect(Self.usage(samples, .day).output == 115)
    }

    @Test("Reasoning is part of output: it is shown as a share and never added to the total")
    func reasoningNotDoubleCounted() {
        let samples = [
            Self.sample(.input, agoHours: 2, count: 600),
            Self.sample(.output, agoHours: 2, count: 400),
            Self.sample(.reasoning, agoHours: 2, count: 100)
        ]

        let usage = Self.usage(samples, .day)

        #expect(usage.total == 1_000)
        #expect(usage.output == 400)
        #expect(usage.reasoning == 100)
        #expect(usage.reasoningShareOfOutput == 0.25)
        #expect(usage.buckets.map { $0.tokensByApp.values.reduce(0, +) }.reduce(0, +) == 1_000)
    }

    @Test("Cache read is a share of all input, whichever way the input arrived")
    func cacheReadShare() {
        let samples = [
            Self.sample(.input, agoHours: 2, count: 100),
            Self.sample(.cacheRead, agoHours: 2, count: 600),
            Self.sample(.cacheWrite5m, agoHours: 2, count: 100),
            Self.sample(.cacheWrite1h, agoHours: 2, count: 100),
            Self.sample(.cacheWrite, agoHours: 2, count: 100)
        ]

        let usage = Self.usage(samples, .day)

        #expect(usage.cacheRead == 600)
        #expect(usage.cacheReadShareOfInput == 0.6)
        #expect(usage.total == 1_000)
    }

    @Test("Shares are nil when there is nothing to take a share of")
    func emptyShares() {
        let usage = Self.usage([], .week)

        #expect(usage.total == 0)
        #expect(usage.buckets.count == 8)
        #expect(usage.buckets.allSatisfy { $0.tokensByApp.isEmpty })
        #expect(Self.usage([], .all).buckets.isEmpty)
        #expect(usage.reasoningShareOfOutput == nil)
        #expect(usage.cacheReadShareOfInput == nil)
    }

    @Test("Totals split by Bar App and add across models")
    func splitByApp() {
        let samples = [
            Self.sample(.output, app: .claudeBar, model: "a", agoHours: 2, count: 30),
            Self.sample(.output, app: .claudeBar, model: "b", agoHours: 2, count: 20),
            Self.sample(.input, app: .codexBar, model: "c", agoHours: 2, count: 70)
        ]

        let usage = Self.usage(samples, .day)

        #expect(usage.totalByApp == [.claudeBar: 50, .codexBar: 70])
        #expect(usage.total == 120)
    }

    @Test("24h is charted by the hour, filling quiet hours with zero")
    func hourlyBuckets() {
        let samples = [
            Self.sample(.output, agoHours: 5, count: 10),
            Self.sample(.output, agoHours: 2, count: 25)
        ]

        let buckets = Self.usage(samples, .day).buckets

        #expect(buckets.count == 25)
        #expect(buckets.last?.start == Self.calendar.dateInterval(of: .hour, for: Self.now)?.start)
        let tokens = buckets.map { $0.tokensByApp[.claudeBar, default: 0] }
        #expect(tokens.reduce(0, +) == 25)
        #expect(tokens[tokens.count - 1 - 5] == 10)
        #expect(tokens[tokens.count - 1 - 2] == 15)
        #expect(tokens[tokens.count - 1 - 3] == 0)
    }

    @Test("7d, 30d and All time are charted by the day, and All starts at the oldest data")
    func dailyBuckets() {
        let samples = [
            Self.sample(.output, agoHours: 24 * 40, count: 10),
            Self.sample(.output, agoHours: 24 * 3, count: 30)
        ]

        #expect(Self.usage(samples, .week).buckets.count == 8)
        #expect(Self.usage(samples, .month).buckets.count == 31)
        #expect(Self.usage(samples, .month).output == 20)
        let all = Self.usage(samples, .all)
        #expect(all.buckets.count == 41)
        #expect(all.output == 30)
        #expect(all.buckets.first?.tokensByApp[.claudeBar] == 10)
    }

    @Test("Usage in the Archive from the fixture files matches the sums in them for every range")
    func fixtureFiles() async throws {
        let fixture = try ImportFixture()
        try fixture.copyFixture("claudebar-metrics-2026-10-12.jsonl", to: fixture.claudeFolder)
        try fixture.copyFixture("codexbar-metrics-2026-10-12.jsonl", to: fixture.codexFolder)
        _ = try await fixture.importer.importMetrics(of: .claudeBar, from: fixture.claudeFolder)
        _ = try await fixture.importer.importMetrics(of: .codexBar, from: fixture.codexFolder)
        let samples = try await fixture.archive.tokenSamples()
        let fixtureNow = Date(timeIntervalSince1970: 1_791_791_400 + 60)

        for range in TimeRange.allCases {
            let usage = TokenUsage(samples: samples, range: range, now: fixtureNow, calendar: Self.calendar)

            #expect(usage.totalByApp == [.claudeBar: 575_292, .codexBar: 59_896])
            #expect(usage.input == 70_376)
            #expect(usage.output == 564_812)
        }
    }

    struct DomainCase: Sendable, CustomTestStringConvertible {
        let range: TimeRange
        /// When the only usage happened, in hours before `now`.
        let burstAgoHours: Int64
        /// The domain's ends, in seconds from `now`.
        let start: TimeInterval
        let end: TimeInterval

        var testDescription: String { "\(range)" }
    }

    // `now` is midday, so a 24 hour range starts on an hour and runs to the end
    // of the current one, and a week starts at midnight seven days back and
    // runs to the end of today.
    static let domainCases: [DomainCase] = [
        DomainCase(range: .day, burstAgoHours: 10, start: -24 * 3_600, end: 3_600),
        DomainCase(range: .week, burstAgoHours: 50, start: -(7 * 24 + 12) * 3_600, end: 12 * 3_600)
    ]

    @Test("The chart's time domain spans the whole selected range, quiet buckets at either end included", arguments: domainCases)
    func timeDomainCoversRange(_ domainCase: DomainCase) throws {
        let samples = [
            Self.sample(.output, start: 1, agoHours: domainCase.burstAgoHours + 1, count: 0),
            Self.sample(.output, start: 1, agoHours: domainCase.burstAgoHours, count: 500)
        ]
        let usage = Self.usage(samples, domainCase.range)

        let domain = try #require(usage.timeDomain(component: domainCase.range.bucketComponent, calendar: Self.calendar))

        #expect(domain.lowerBound == Self.now.addingTimeInterval(domainCase.start))
        #expect(domain.upperBound == Self.now.addingTimeInterval(domainCase.end))
    }

    @Test("No buckets, no time domain")
    func noTimeDomainWithoutBuckets() {
        #expect(Self.usage([], .all).timeDomain(component: .day, calendar: Self.calendar) == nil)
    }
}
