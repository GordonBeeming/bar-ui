import Foundation
import Testing
@testable import BarUICore

@Suite("Resets recovered from archived samples")
struct InferredResetsTests {
    private static let second: Int64 = 1_000_000_000
    private static let weekly = LimitDescriptor(id: "codex:10080", name: "Weekly", windowDurationMinutes: 10_080, modelID: nil)
    private static let session = LimitDescriptor(id: "session", name: "Session (5h)", windowDurationMinutes: 300, modelID: nil)

    /// One poll: when it was taken (Unix seconds), the reset time it reported, and utilisation.
    private struct Poll {
        let time: Int64
        let resetsAt: Double
        let utilization: Double
    }

    private func infer(_ polls: [Poll], limit: LimitDescriptor = weekly, logged: [LimitReset] = []) -> [LimitReset] {
        InferredResets.rollovers(
            app: .codexBar,
            limit: limit,
            resetsAt: polls.map { ArchivedSample(timeUnixNano: $0.time * Self.second, value: $0.resetsAt) },
            utilization: polls.map { ArchivedSample(timeUnixNano: $0.time * Self.second, value: $0.utilization) },
            logged: logged
        )
    }

    @Test("CodexBar's three early Weekly resets, from the real archived samples, are recovered")
    func earlyWeeklyResets() {
        let polls = [
            Poll(time: 1_791_867_316, resetsAt: 1_792_310_768, utilization: 6),
            Poll(time: 1_791_867_609, resetsAt: 1_792_472_409, utilization: 0),
            Poll(time: 1_792_044_489, resetsAt: 1_792_475_653, utilization: 5),
            Poll(time: 1_792_044_791, resetsAt: 1_792_649_591, utilization: 0),
            Poll(time: 1_792_269_463, resetsAt: 1_792_652_811, utilization: 6),
            Poll(time: 1_792_269_763, resetsAt: 1_792_874_563, utilization: 0)
        ]

        let resets = infer(polls)

        #expect(resets.map { $0.timeUnixNano / Self.second } == [1_791_867_609, 1_792_044_791, 1_792_269_763])
        #expect(resets.map(\.utilizationLast) == [6, 5, 6])
        #expect(resets.first?.nextResetsAt == Date(timeIntervalSince1970: 1_792_472_409))
        #expect(resets.allSatisfy { $0.limit == Self.weekly && $0.app == .codexBar })
    }

    @Test("A rollover the Bar App already logged isn't listed twice")
    func loggedResetIsNotDoubled() {
        let polls = [
            Poll(time: 1_000_000, resetsAt: 1_000_100, utilization: 40),
            Poll(time: 1_000_300, resetsAt: 1_018_300, utilization: 0)
        ]
        let logged = LimitReset(app: .claudeBar, limit: Self.session, timeUnixNano: 1_000_300 * Self.second, utilizationLast: 40, nextResetsAt: nil)

        #expect(infer(polls, limit: Self.session, logged: [logged]).isEmpty)
    }

    @Test("Drift between reads isn't a reset")
    func driftIsNotAReset() {
        let polls = [
            Poll(time: 1_000_000, resetsAt: 1_100_000, utilization: 6),
            Poll(time: 1_000_300, resetsAt: 1_100_240, utilization: 6)
        ]

        #expect(infer(polls).isEmpty)
    }

    @Test("A Window that hasn't started, its reset time creeping forward each poll, isn't a reset")
    func notStartedWindow() {
        // Typed step by step: the inline arithmetic times out the CI compiler's type checker.
        var polls: [Poll] = []
        for step in 0..<6 {
            let time: Int64 = 1_000_000 + Int64(step) * 600
            let resetsAt: Double = Double(time) + 604_800
            polls.append(Poll(time: time, resetsAt: resetsAt, utilization: 0))
        }

        #expect(infer(polls).isEmpty)
    }

    @Test("A Window that hasn't started, seen across a two-hour poll gap, isn't a reset")
    func notStartedWindowAcrossAGap() {
        let polls = [
            Poll(time: 1_000_000, resetsAt: 1_604_800, utilization: 0),
            Poll(time: 1_007_200, resetsAt: 1_612_000, utilization: 0)
        ]

        #expect(infer(polls).isEmpty)
    }

    @Test("A Window that ended while the Mac slept is a reset at the first poll after")
    func resetAcrossSleep() {
        let polls = [
            Poll(time: 1_000_000, resetsAt: 1_003_600, utilization: 30),
            Poll(time: 1_010_000, resetsAt: 1_021_600, utilization: 2)
        ]

        let resets = infer(polls, limit: Self.session)

        #expect(resets.map { $0.timeUnixNano / Self.second } == [1_010_000])
        #expect(resets.first?.utilizationLast == 30)
    }

    @Test("A Window that runs to its end and comes back a whole Window later is a reset")
    func fullWindowRollover() {
        let polls = [
            Poll(time: 1_604_700, resetsAt: 1_604_800, utilization: 81),
            Poll(time: 1_605_000, resetsAt: 2_209_600, utilization: 0)
        ]

        #expect(infer(polls).count == 1)
    }

    @Test("An unused Window that expired isn't a reset: there was nothing to reset")
    func unusedExpiredWindow() {
        let polls = [
            Poll(time: 1_000_000, resetsAt: 1_003_600, utilization: 0),
            Poll(time: 1_010_000, resetsAt: 1_021_600, utilization: 0)
        ]

        #expect(infer(polls, limit: Self.session).isEmpty)
    }

    @Test("An unused Window that hasn't started, seen across a gap of half a Window or more, isn't a reset")
    func floatingWindowAcrossALongGap() {
        let polls = [
            Poll(time: 1_000_000, resetsAt: 1_018_000, utilization: 0),
            Poll(time: 1_010_800, resetsAt: 1_028_800, utilization: 0)
        ]

        #expect(infer(polls, limit: Self.session).isEmpty)
    }

    @Test("A short Window's full rollover counts even though its reset time moved less than an hour")
    func shortWindowRollover() {
        let hourly = LimitDescriptor(id: "hourly", name: "Hourly", windowDurationMinutes: 60, modelID: nil)
        let polls = [
            Poll(time: 1_000_000, resetsAt: 1_000_300, utilization: 80),
            Poll(time: 1_000_600, resetsAt: 1_003_900, utilization: 0)
        ]

        #expect(infer(polls, limit: hourly).count == 1)
    }

    @Test("A Limit with no Window length needs usage to go down before a jump counts")
    func unknownWindowNeedsUsageEvidence() {
        let unknown = LimitDescriptor(id: "mystery", name: "Mystery", windowDurationMinutes: nil, modelID: nil)
        let steady = [
            Poll(time: 1_000_000, resetsAt: 1_100_000, utilization: 5),
            Poll(time: 1_000_300, resetsAt: 1_200_000, utilization: 5)
        ]
        let dropped = [
            Poll(time: 1_000_000, resetsAt: 1_100_000, utilization: 50),
            Poll(time: 1_000_300, resetsAt: 1_200_000, utilization: 0)
        ]

        #expect(infer(steady, limit: unknown).isEmpty)
        #expect(infer(dropped, limit: unknown).count == 1)
    }

    @Test("First use after a long idle gap isn't a reset, though the floating deadline jumped hours")
    func firstUseAfterIdleGap() {
        // Idle overnight at 0%, so each poll's deadline floated five hours ahead; the first
        // poll after a morning's use reads 10% with a deadline from when use started.
        let polls = [
            Poll(time: 1_000_000, resetsAt: 1_018_000, utilization: 0),
            Poll(time: 1_014_400, resetsAt: 1_030_000, utilization: 10)
        ]

        #expect(infer(polls, limit: Self.session).isEmpty)
    }

    private static let hourly = LimitDescriptor(id: "hourly", name: "Hourly", windowDurationMinutes: 60, modelID: nil)

    @Test("A short Window reset early, its deadline moving only ten minutes, counts when usage falls to zero")
    func shortWindowEarlyReset() {
        let polls = [
            Poll(time: 1_000_000, resetsAt: 1_003_000, utilization: 80),
            Poll(time: 1_000_600, resetsAt: 1_003_600, utilization: 0)
        ]

        #expect(infer(polls, limit: Self.hourly).count == 1)
    }

    @Test("A deadline already past at the earlier poll isn't a reset at the later one")
    func staleDeadlineCorrectedLater() {
        // The tool kept reporting the old deadline for one poll after it passed, then corrected
        // it; the reset happened before the first of these polls, not between them.
        let polls = [
            Poll(time: 1_010_000, resetsAt: 1_003_600, utilization: 2),
            Poll(time: 1_010_300, resetsAt: 1_021_600, utilization: 3)
        ]

        #expect(infer(polls, limit: Self.session).isEmpty)
    }

    @Test("Without a Window length, usage jitter alongside a corrected reset time isn't a reset")
    func unknownWindowJitter() {
        let unknown = LimitDescriptor(id: "mystery", name: "Mystery", windowDurationMinutes: nil, modelID: nil)
        let polls = [
            Poll(time: 1_000_000, resetsAt: 1_100_000, utilization: 50),
            Poll(time: 1_000_300, resetsAt: 1_200_000, utilization: 49)
        ]

        #expect(infer(polls, limit: unknown).isEmpty)
    }

    @Test("An hourly rollover an hour after a logged one is its own reset, not that one again")
    func consecutiveHourlyResets() {
        let polls = [
            Poll(time: 1_003_500, resetsAt: 1_003_600, utilization: 70),
            Poll(time: 1_003_700, resetsAt: 1_007_300, utilization: 0)
        ]
        let logged = LimitReset(app: .codexBar, limit: Self.hourly, timeUnixNano: 1_000_100 * Self.second, utilizationLast: 60, nextResetsAt: nil)

        #expect(infer(polls, limit: Self.hourly, logged: [logged]).count == 1)
    }

    @Test("Samples without a matching reset time or utilisation are skipped, not guessed")
    func unmatchedSamples() {
        let resets = InferredResets.rollovers(
            app: .codexBar,
            limit: Self.weekly,
            resetsAt: [ArchivedSample(timeUnixNano: 1 * Self.second, value: 100), ArchivedSample(timeUnixNano: 2 * Self.second, value: 900_000)],
            utilization: [ArchivedSample(timeUnixNano: 1 * Self.second, value: 50)],
            logged: []
        )

        #expect(resets.isEmpty)
    }
}
