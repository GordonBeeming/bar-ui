import Foundation
import Testing
@testable import BarUICore

@Suite("Recovered resets read back from the Archive")
struct InferredResetArchiveTests {
    /// One CodexBar metrics line: the Weekly Limit's utilisation and reset time at `time`.
    private static func metricsLine(time: Int64, utilization: Double, resetsAt: Int64) -> String {
        let limit = #"[{"key":"limit.id","value":{"stringValue":"codex:10080"}},{"key":"limit.name","value":{"stringValue":"Weekly"}},{"key":"limit.window.duration_minutes","value":{"intValue":"10080"}}]"#
        let nano = "\(time)000000000"
        return #"{"resourceMetrics":[{"resource":{"attributes":[{"key":"service.name","value":{"stringValue":"codexbar"}},{"key":"service.version","value":{"stringValue":"0.9"}},{"key":"host.name","value":{"stringValue":"test-mac.local"}},{"key":"os.type","value":{"stringValue":"darwin"}},{"key":"bar.spec.version","value":{"stringValue":"1"}}]},"scopeMetrics":[{"scope":{"name":"com.gordonbeeming.CodexBar.telemetry","version":"0.9"},"metrics":["#
            + #"{"name":"bar.limit.utilization","unit":"%","gauge":{"dataPoints":[{"asDouble":\#(utilization),"attributes":\#(limit),"timeUnixNano":"\#(nano)"}]}},"#
            + #"{"name":"bar.limit.resets_at","unit":"s","gauge":{"dataPoints":[{"asInt":"\#(resetsAt)","attributes":\#(limit),"timeUnixNano":"\#(nano)"}]}}"#
            + "]}]}]}"
    }

    @Test("An early reset CodexBar never logged comes back from both the history and the all-time list")
    func earlyResetIsRecovered() async throws {
        let fixture = try ImportFixture()
        let lines = [
            Self.metricsLine(time: 1_791_867_316, utilization: 6, resetsAt: 1_792_310_768),
            Self.metricsLine(time: 1_791_867_609, utilization: 0, resetsAt: 1_792_472_409)
        ]
        try Data((lines.joined(separator: "\n") + "\n").utf8)
            .write(to: fixture.codexFolder.appendingPathComponent("codexbar-metrics-2026-10-13.jsonl"))
        let summary = try await fixture.importer.importMetrics(of: .codexBar, from: fixture.codexFolder)
        #expect(summary.samplesRead == 4)
        #expect(summary.droppedRecords == 0)

        let history = try #require(try await fixture.archive.limitHistories(of: .codexBar, since: nil).first)
        let all = try await fixture.archive.limitResets(of: .codexBar)

        #expect(history.resets.map(\.timeUnixNano) == [1_791_867_609_000_000_000])
        #expect(history.resets.first?.utilizationLast == 6)
        #expect(all["codex:10080"]?.map(\.timeUnixNano) == [1_791_867_609_000_000_000])
    }

    @Test("A ClaudeBar reset that was logged isn't added again from its samples")
    func loggedResetsStayUnchanged() async throws {
        let fixture = try ImportFixture()
        try fixture.copyFixture("claudebar-metrics-2026-10-12.jsonl", to: fixture.claudeFolder)
        try fixture.copyFixture("claudebar-logs-2026-10-12.jsonl", to: fixture.claudeFolder)
        _ = try await fixture.importer.importMetrics(of: .claudeBar, from: fixture.claudeFolder)

        let histories = try await fixture.archive.limitHistories(of: .claudeBar, since: nil)

        #expect(histories.first { $0.limit.id == "session" }?.resets.map(\.utilizationLast) == [30, 71.5])
        #expect(histories.first { $0.limit.id == "weekly_all" }?.resets.map(\.utilizationLast) == [88])
    }
}
