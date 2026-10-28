import Foundation
import Testing
@testable import BarUICore

@Suite("Limit history hover")
struct LimitHoverTests {
    struct Case: Sendable, CustomTestStringConvertible {
        let name: String
        let hoverAt: Int
        let expectedPercent: Double?

        var testDescription: String { name }
    }

    // Runs: samples at 0, 300, 600, 900 (10, 12, 14, 16), then after a six hour
    // gap at 21_300 and 21_600 (5, 7).
    static let cases: [Case] = [
        Case(name: "exactly on a sample", hoverAt: 300, expectedPercent: 12),
        Case(name: "nearer the earlier sample", hoverAt: 400, expectedPercent: 12),
        Case(name: "nearer the later sample", hoverAt: 500, expectedPercent: 14),
        Case(name: "halfway picks the earlier sample", hoverAt: 450, expectedPercent: 12),
        Case(name: "just inside the gap's first edge", hoverAt: 901, expectedPercent: nil),
        Case(name: "middle of the gap", hoverAt: 10_000, expectedPercent: nil),
        Case(name: "just inside the gap's far edge", hoverAt: 21_299, expectedPercent: nil),
        Case(name: "first sample after the gap", hoverAt: 21_300, expectedPercent: 5),
        Case(name: "before the first sample", hoverAt: -100, expectedPercent: 10),
        Case(name: "after the last sample", hoverAt: 30_000, expectedPercent: 7)
    ]

    @Test("The nearest sample within the hovered run; nothing over a gap", arguments: cases)
    func nearestSample(_ testCase: Case) {
        let row = Self.row(resets: [])

        let hover = row.hover(at: Self.date(testCase.hoverAt))

        #expect(hover?.point.percent == testCase.expectedPercent)
    }

    @Test("Hovering a lone sample run finds it only when the pointer is on it")
    func loneRun() {
        let row = Self.row(utilization: [(0, 10), (6 * 3600, 5), (6 * 3600 + 300, 7)], resets: [])

        #expect(row.hover(at: Self.date(0))?.point.percent == 10)
        #expect(row.hover(at: Self.date(3_000)) == nil)
    }

    @Test("A row with no samples has nothing to hover")
    func noSamples() {
        #expect(Self.row(utilization: [], resets: []).hover(at: Self.date(0)) == nil)
    }

    @Test("A reset belongs to the sample nearest it, and that sample's readout carries its Unused at Reset")
    func resetOnReadout() {
        let row = Self.row(resets: [(280, 40)])

        #expect(row.hover(at: Self.date(300))?.reset?.unusedPercent == 60)
        #expect(row.hover(at: Self.date(0))?.reset == nil)
        #expect(row.hover(at: Self.date(600))?.reset == nil)
    }

    @Test("A reset in a gap is not shown on the sample across the gap")
    func resetInGap() {
        let row = Self.row(resets: [(10_000, 40)])

        #expect(row.hover(at: Self.date(900))?.reset == nil)
        #expect(row.hover(at: Self.date(21_300))?.reset == nil)
    }

    @Test("Hovering near a reset in a gap still finds it, so its figure is never out of reach")
    func resetInGapIsReachable() {
        let row = Self.row(resets: [(10_000, 40)])

        #expect(row.resetMarker(near: Self.date(10_300), within: 600)?.unusedPercent == 60)
        #expect(row.resetMarker(near: Self.date(12_000), within: 600) == nil)
    }

    private static func nano(_ seconds: Int) -> Int64 {
        1_791_000_000_000_000_000 + Int64(seconds) * 1_000_000_000
    }

    private static func date(_ seconds: Int) -> Date {
        Date(unixNano: nano(seconds))
    }

    private static let defaultUtilization: [(Int, Double)] = [
        (0, 10), (300, 12), (600, 14), (900, 16), (21_300, 5), (21_600, 7)
    ]

    private static func row(utilization: [(Int, Double)] = defaultUtilization, resets: [(Int, Double)] = []) -> LimitHistoryRow {
        let limit = LimitDescriptor(id: "session", name: "Session (5h)", windowDurationMinutes: 300, modelID: nil)
        let samples = utilization.map { ArchivedSample(timeUnixNano: nano($0.0), value: $0.1) }
        return LimitHistoryRow(history: LimitHistory(
            app: .claudeBar,
            limit: limit,
            utilization: samples,
            latest: samples.last,
            resets: resets.map {
                LimitReset(app: .claudeBar, limit: limit, timeUnixNano: nano($0.0), utilizationLast: $0.1, nextResetsAt: nil)
            }
        ))
    }
}
