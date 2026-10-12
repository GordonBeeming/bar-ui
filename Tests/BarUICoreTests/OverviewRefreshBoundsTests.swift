import Foundation
import Testing
@testable import BarUICore

/// The Archive keeps everything forever, so a refresh must read only as far
/// back as the views on screen need.
@Suite("Overview refresh reads only the range on screen")
@MainActor
struct OverviewRefreshBoundsTests {
    private static let now = Date(timeIntervalSince1970: 1_791_791_400)
    private static let day: Int64 = 24 * 3_600 * 1_000_000_000
    private static let hour: Int64 = 3_600 * 1_000_000_000
    private static let nowNano: Int64 = 1_791_791_400 * 1_000_000_000
    private static let session = LimitDescriptor(id: "session", name: "Session (5h)", windowDurationMinutes: 300, modelID: nil)

    private static func tokens(_ count: Int64, daysAgo: Int64) -> TokenSample {
        TokenSample(app: .claudeBar, model: "claude-opus-4-1", tokenType: .input, startTimeUnixNano: nowNano - 60 * day, timeUnixNano: nowNano - daysAgo * day, count: count)
    }

    private static func utilization(_ value: Double, at time: Int64) -> LimitSample {
        LimitSample(app: .claudeBar, limit: session, metric: .utilization, timeUnixNano: time, value: value)
    }

    private static func record(_ records: TelemetryRecords, in fixture: ImportFixture) async throws {
        try await fixture.archive.record(records, progress: ImportProgress(app: .claudeBar, fileName: "seed.jsonl", byteOffset: 1, droppedRecords: 0))
    }

    @Test("A 7 day refresh holds no token sample older than the one each counter needs as its baseline, and its totals still add up")
    func tokensStopAtTheBaseline() async throws {
        let fixture = try ImportFixture()
        try await Self.record(TelemetryRecords(tokenSamples: [
            Self.tokens(10, daysAgo: 30), Self.tokens(20, daysAgo: 20), Self.tokens(30, daysAgo: 10),
            Self.tokens(45, daysAgo: 3), Self.tokens(60, daysAgo: 1)
        ]), in: fixture)
        let overview = LimitsOverview(archive: fixture.archive, now: { Self.now })

        await overview.show(.week, by: UUID())

        #expect(overview.tokenSamples.map(\.timeUnixNano) == [10, 3, 1].map { Self.nowNano - $0 * Self.day })
        #expect(overview.tokenUsage(range: .week, now: Self.now).total == 30)
    }

    @Test("Showing All time reads everything, and the totals match")
    func allTimeReadsEverything() async throws {
        let fixture = try ImportFixture()
        try await Self.record(TelemetryRecords(tokenSamples: [Self.tokens(10, daysAgo: 30), Self.tokens(60, daysAgo: 1)]), in: fixture)
        let overview = LimitsOverview(archive: fixture.archive, now: { Self.now })

        await overview.show(.all, by: UUID())

        #expect(overview.tokenSamples.count == 2)
        #expect(overview.tokenUsage(range: .all, now: Self.now).total == 60)
    }

    @Test("A Limit's history for 7 days holds only samples inside it, plus how far its open Window had got before")
    func historyStopsAtTheRange() async throws {
        let fixture = try ImportFixture()
        let floor = Self.nowNano - 7 * Self.day
        try await Self.record(TelemetryRecords(
            limitSamples: [
                Self.utilization(95, at: floor - 30 * Self.day),
                Self.utilization(80, at: floor - 2 * Self.hour),
                Self.utilization(60, at: floor - Self.hour),
                Self.utilization(78, at: floor + Self.hour)
            ]
        ), in: fixture)

        let histories = try await fixture.archive.limitHistories(of: .claudeBar, since: Date(unixNano: floor))

        #expect(histories.first?.utilization.map(\.value) == [78])
        #expect(histories.first?.peakBeforeRange == 80)
    }

    @Test("A Window that was already running low before the range doesn't say so again inside it")
    func crossingBeforeTheRangeIsNotRepeated() async throws {
        let fixture = try ImportFixture()
        let floor = Self.nowNano - 7 * Self.day
        try await Self.record(TelemetryRecords(
            limitSamples: [
                Self.utilization(10, at: floor - 3 * Self.hour),
                Self.utilization(80, at: floor - 2 * Self.hour),
                Self.utilization(60, at: floor - Self.hour),
                Self.utilization(78, at: floor + Self.hour),
                Self.utilization(92, at: floor + 2 * Self.hour)
            ]
        ), in: fixture)
        let overview = LimitsOverview(archive: fixture.archive, now: { Self.now })

        await overview.show(.week, by: UUID())

        #expect(overview.events(range: .week, now: Self.now).map(\.kind) == [.nearLimit])
    }

    @Test("A reset just before the range starts the Window over, so the first climb inside it is an event")
    func resetBeforeTheRange() async throws {
        let fixture = try ImportFixture()
        let floor = Self.nowNano - 7 * Self.day
        try await Self.record(TelemetryRecords(
            limitSamples: [Self.utilization(85, at: floor - 2 * Self.hour), Self.utilization(80, at: floor + Self.hour)],
            resets: [LimitReset(app: .claudeBar, limit: Self.session, timeUnixNano: floor - Self.hour, utilizationLast: 85, nextResetsAt: nil)]
        ), in: fixture)

        let histories = try await fixture.archive.limitHistories(of: .claudeBar, since: Date(unixNano: floor))
        let overview = LimitsOverview(archive: fixture.archive, now: { Self.now })
        await overview.show(.week, by: UUID())

        #expect(histories.first?.peakBeforeRange == 0)
        #expect(overview.events(range: .week, now: Self.now).map(\.kind) == [.runningLow])
    }
}
