import Foundation
import Testing
@testable import BarUICore

@Suite("Limit history rows")
struct LimitHistoryRowTests {
    private static let session = LimitDescriptor(id: "session", name: "Session (5h)", windowDurationMinutes: 300, modelID: nil)
    private static let unknownWindow = LimitDescriptor(id: "codex:primary", name: "Primary", windowDurationMinutes: nil, modelID: nil)

    @Test("Each reset is a marker holding what was Unused at Reset, and the row averages them")
    func unusedAtReset() {
        let history = Self.history(
            utilization: [(0, 10), (300, 60), (600, 20)],
            resets: [(450, 70), (150, 40)]
        )

        let row = LimitHistoryRow(history: history)

        #expect(row.resetMarkers.map(\.date) == [Self.date(150), Self.date(450)])
        #expect(row.resetMarkers.map(\.unusedPercent) == [60, 30])
        #expect(row.unusedAtLastReset == 30)
        #expect(row.averageUnusedAtReset == 45)
    }

    @Test("With no resets there is nothing to report as Unused at Reset")
    func noResets() {
        let row = LimitHistoryRow(history: Self.history(utilization: [(0, 10), (300, 20)], resets: []))

        #expect(row.resetMarkers.isEmpty)
        #expect(row.unusedAtLastReset == nil)
        #expect(row.averageUnusedAtReset == nil)
    }

    @Test("A stretch with no samples, far longer than the usual interval, splits the line")
    func trackingGap() {
        let history = Self.history(utilization: [
            (0, 10), (300, 12), (600, 14), (900, 16),
            (900 + 6 * 3600, 5), (900 + 6 * 3600 + 300, 7)
        ], resets: [])

        let row = LimitHistoryRow(history: history)

        #expect(row.segments.count == 2)
        #expect(row.segments.map { $0.map(\.percent) } == [[10, 12, 14, 16], [5, 7]])
    }

    @Test("With only two intervals, the long one isn't taken as the usual pace, so the gap still splits")
    func gapAmongFewSamples() {
        let history = Self.history(utilization: [
            (0, 10),
            (6 * 3600, 5), (6 * 3600 + 300, 7)
        ], resets: [])

        let row = LimitHistoryRow(history: history)

        #expect(row.segments.map { $0.map(\.percent) } == [[10], [5, 7]])
    }

    @Test("A gap with no reset in it is bridged from the last sample before to the first after")
    func bridgedGap() {
        let history = Self.history(utilization: [
            (0, 10), (300, 12), (600, 14), (900, 16),
            (900 + 6 * 3600, 16), (900 + 6 * 3600 + 300, 18)
        ], resets: [])

        let row = LimitHistoryRow(history: history)

        #expect(row.bridges.map { $0.map(\.percent) } == [[16, 16]])
        #expect(row.bridges.map { $0.map(\.date) } == [[Self.date(900), Self.date(900 + 6 * 3600)]])
    }

    @Test("A gap with a reset in it stays open, so the drop isn't drawn as a slope")
    func resetInGapIsNotBridged() {
        let history = Self.history(utilization: [
            (0, 70), (300, 75), (600, 80),
            (600 + 6 * 3600, 5), (600 + 6 * 3600 + 300, 7)
        ], resets: [(600 + 3 * 3600, 80)])

        let row = LimitHistoryRow(history: history)

        #expect(row.segments.count == 2)
        #expect(row.bridges.isEmpty)
    }

    @Test("Samples at the usual pace stay one line")
    func noGap() {
        let history = Self.history(utilization: [(0, 10), (300, 12), (600, 14), (1_000, 16)], resets: [])

        let row = LimitHistoryRow(history: history)

        #expect(row.segments.count == 1)
    }

    @Test("A Limit whose Window length is unknown still gets a row, saying so")
    func unknownWindowDuration() {
        let history = LimitHistory(
            app: .codexBar,
            limit: Self.unknownWindow,
            utilization: [ArchivedSample(timeUnixNano: Self.nano(0), value: 33)],
            latest: ArchivedSample(timeUnixNano: Self.nano(0), value: 33),
            resets: [LimitReset(app: .codexBar, limit: Self.unknownWindow, timeUnixNano: Self.nano(100), utilizationLast: 90, nextResetsAt: nil)]
        )

        let row = LimitHistoryRow(history: history)

        #expect(row.windowText == "Window length unknown")
        #expect(row.percentUsedNow == 33)
        #expect(row.resetMarkers.map(\.unusedPercent) == [10])
    }

    @Test("Known Windows are named by their length")
    func windowText() {
        func text(_ minutes: Int?) -> String {
            let limit = LimitDescriptor(id: "x", name: "x", windowDurationMinutes: minutes, modelID: nil)
            return LimitHistoryRow(history: LimitHistory(app: .claudeBar, limit: limit, utilization: [], latest: nil, resets: [])).windowText
        }

        #expect(text(300) == "5 hour window")
        #expect(text(10080) == "7 day window")
        #expect(text(90) == "90 minute window")
        #expect(text(60) == "1 hour window")
        #expect(text(nil) == "Window length unknown")
    }

    @Test("Percent used now is the newest sample, rounded, and absent with no samples")
    func percentUsedNow() {
        let withSamples = LimitHistoryRow(history: Self.history(utilization: [(0, 10), (300, 42.6)], resets: []))
        let without = LimitHistoryRow(history: Self.history(utilization: [], resets: []))

        #expect(withSamples.percentUsedNow == 43)
        #expect(withSamples.latestSampleAt == Self.date(300))
        #expect(without.percentUsedNow == nil)
    }

    @Test("Rows lead with the shortest Window and put unknown Windows last")
    func ordering() {
        func history(_ id: String, _ minutes: Int?) -> LimitHistory {
            LimitHistory(
                app: .claudeBar,
                limit: LimitDescriptor(id: id, name: id, windowDurationMinutes: minutes, modelID: nil),
                utilization: [],
                latest: nil,
                resets: []
            )
        }

        let rows = LimitHistoryRow.rows(from: [history("b", nil), history("weekly", 10080), history("session", 300), history("a", nil)])

        #expect(rows.map(\.limitID) == ["session", "weekly", "a", "b"])
    }

    private static func nano(_ seconds: Int) -> Int64 {
        1_791_000_000_000_000_000 + Int64(seconds) * 1_000_000_000
    }

    private static func date(_ seconds: Int) -> Date {
        Date(unixNano: nano(seconds))
    }

    private static func history(utilization: [(Int, Double)], resets: [(Int, Double)]) -> LimitHistory {
        let samples = utilization.map { ArchivedSample(timeUnixNano: nano($0.0), value: $0.1) }
        return LimitHistory(
            app: .claudeBar,
            limit: session,
            utilization: samples,
            latest: samples.last,
            resets: resets.sorted { $0.0 < $1.0 }.map {
                LimitReset(app: .claudeBar, limit: session, timeUnixNano: nano($0.0), utilizationLast: $0.1, nextResetsAt: nil)
            }
        )
    }
}
