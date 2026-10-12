import Foundation
import Testing
@testable import BarUICore

@Suite("Reporting non-conforming records")
struct SkippedRecordsTests {
    private static let valid: [MetricsLine.Point] = [.utilization(id: "session", name: "Session (5h)", value: 40, minutes: 300)]

    @Test("Skipped records are counted per Bar App and per day of the file they came from")
    func countedPerAppAndDay() async throws {
        let fixture = try ImportFixture()
        var eleventh = MetricsLine.limits(service: "claudebar", specVersion: "2", points: Self.valid)
        eleventh += Data("garbage\n".utf8)
        try eleventh.write(to: fixture.claudeFolder.appendingPathComponent("claudebar-metrics-2026-10-11.jsonl"))
        try MetricsLine.limits(service: "claudebar", specVersion: nil, points: Self.valid)
            .write(to: fixture.claudeFolder.appendingPathComponent("claudebar-metrics-2026-10-12.jsonl"))
        try MetricsLine.limits(service: "codexbar", specVersion: nil, points: Self.valid)
            .write(to: fixture.codexFolder.appendingPathComponent("codexbar-metrics-2026-10-12.jsonl"))

        _ = try await fixture.importer.importMetrics(of: .claudeBar, from: fixture.claudeFolder)
        _ = try await fixture.importer.importMetrics(of: .codexBar, from: fixture.codexFolder)

        let claude = try await fixture.archive.skippedRecords(of: .claudeBar)
        #expect(claude == [
            SkippedRecords(day: TelemetryDay(year: 2026, month: 10, day: 11), count: 2),
            SkippedRecords(day: TelemetryDay(year: 2026, month: 10, day: 12), count: 1)
        ])
        let codex = try await fixture.archive.skippedRecords(of: .codexBar)
        #expect(codex == [SkippedRecords(day: TelemetryDay(year: 2026, month: 10, day: 12), count: 1)])
    }

    @Test("Non-conforming records never reach the Archive")
    func neverArchived() async throws {
        let fixture = try ImportFixture()
        var data = MetricsLine.limits(service: "claudebar", specVersion: nil, points: Self.valid)
        data += MetricsLine.limits(service: "claudebar", specVersion: "2", points: Self.valid)
        data += MetricsLine.limits(service: "claudebar", points: [
            .utilization(id: "session", name: "Session (5h)", value: 101),
            .utilization(id: "", name: "Session (5h)", value: 40)
        ])
        try data.write(to: fixture.claudeFolder.appendingPathComponent("claudebar-metrics-2026-10-12.jsonl"))

        let summary = try await fixture.importer.importMetrics(of: .claudeBar, from: fixture.claudeFolder)

        #expect(summary.samplesRead == 0)
        #expect(summary.droppedRecords == 4)
        #expect(try await fixture.archive.currentLimits().isEmpty)
        #expect(try await fixture.archive.samples(of: .claudeBar, limitID: "session", metric: .utilization).isEmpty)
    }

    @Test("Conforming files, and app-prefixed or unknown metrics, leave nothing to report")
    func conformingFilesReportNothing() async throws {
        let fixture = try ImportFixture()
        try fixture.copyFixture("claudebar-metrics-2026-10-12.jsonl", to: fixture.claudeFolder)
        let ignorable = #"{"resourceMetrics":[{"resource":{"attributes":[{"key":"service.name","value":{"stringValue":"claudebar"}},{"key":"bar.spec.version","value":{"stringValue":"1"}}]},"scopeMetrics":[{"metrics":[{"name":"claude.usage.used_percent","sum":{"dataPoints":[{"asDouble":3}]}},{"name":"something.else","gauge":{"dataPoints":[{"asDouble":3}]}}]}]}]}"# + "\n"
        try Data(ignorable.utf8).write(to: fixture.claudeFolder.appendingPathComponent("claudebar-metrics-2026-10-11.jsonl"))

        _ = try await fixture.importer.importMetrics(of: .claudeBar, from: fixture.claudeFolder)

        let skipped = try await fixture.archive.skippedRecords(of: .claudeBar)
        #expect(skipped.isEmpty)
        #expect(SkippedRecordsNotice(days: skipped) == nil)
    }

    @Test("The notice names the count and the days, and singular reads as singular")
    func noticeWording() throws {
        func notice(_ days: [(year: Int, month: Int, day: Int, count: Int)]) throws -> SkippedRecordsNotice {
            try #require(SkippedRecordsNotice(days: days.map {
                SkippedRecords(day: TelemetryDay(year: $0.year, month: $0.month, day: $0.day), count: $0.count)
            }))
        }
        let now = Date(timeIntervalSince1970: 1_791_791_400)

        #expect(try notice([(2026, 10, 11, 20), (2026, 10, 12, 18)]).message(now: now)
            == "38 records from 11–12 Oct were skipped because they don't match")
        #expect(try notice([(2026, 10, 12, 1)]).message(now: now)
            == "1 record from 12 Oct was skipped because it doesn't match")
        #expect(try notice([(2026, 10, 12, 5), (2026, 10, 12, 2)]).message(now: now)
            == "7 records from 12 Oct were skipped because they don't match")
        #expect(try notice([(2026, 9, 30, 2), (2026, 10, 2, 3)]).message(now: now)
            == "5 records from 30 Sep – 2 Oct were skipped because they don't match")
        #expect(try notice([(2025, 12, 31, 2), (2026, 1, 1, 3)]).message(now: now)
            == "5 records from 31 Dec 2025 – 1 Jan 2026 were skipped because they don't match")
        #expect(try notice([(2025, 3, 4, 2)]).message(now: now)
            == "2 records from 4 Mar 2025 were skipped because they don't match")
    }

    @Test("The notice links to the Telemetry Spec")
    func specLink() {
        #expect(SkippedRecordsNotice.specName == "Telemetry Spec v1")
        #expect(SkippedRecordsNotice.specURL.absoluteString == "https://github.com/GordonBeeming/bar-ui/blob/main/docs/telemetry-spec.md")
    }

    @Test("Refreshing the Overview keeps each Bar App's notice")
    @MainActor
    func overviewKeepsNotices() async throws {
        let fixture = try ImportFixture()
        try Data("garbage\n".utf8).write(to: fixture.claudeFolder.appendingPathComponent("claudebar-metrics-2026-10-12.jsonl"))
        let overview = LimitsOverview(archive: fixture.archive)
        let settings = TrackingSettings(enabled: true, intervalMinutes: 5, retentionDays: 90, folder: fixture.claudeFolder)

        await overview.refresh(statuses: [.claudeBar: BarAppStatus(state: .tracking, settings: settings)])

        #expect(overview.skippedRecords[.claudeBar]?.count == 1)
        #expect(overview.skippedRecords[.codexBar] == nil)
    }

    @Test("Each way a bar.limit.* point can break the spec is dropped")
    func eachNonConformingCase() {
        let attributes = #""attributes":[{"key":"limit.id","value":{"stringValue":"session"}},{"key":"limit.name","value":{"stringValue":"Session"}}]"#
        let time = #""timeUnixNano":"1791791100000000000""#

        func dropped(_ point: String, metric: String = "bar.limit.utilization", type: String = "gauge") -> Int {
            let line = #"{"resourceMetrics":[{"resource":{"attributes":[{"key":"service.name","value":{"stringValue":"claudebar"}},{"key":"bar.spec.version","value":{"stringValue":"1"}}]},"scopeMetrics":[{"metrics":[{"name":"\#(metric)","\#(type)":{"dataPoints":[{\#(point)}]}}]}]}]}"# + "\n"
            return MetricsParser.parse(Data(line.utf8), from: .claudeBar).droppedRecords
        }

        #expect(dropped("\(attributes),\(time),\"asDouble\":40") == 0)
        #expect(dropped("\(attributes),\"asDouble\":40") == 1)
        #expect(dropped("\(attributes),\"timeUnixNano\":\"0\",\"asDouble\":40") == 1)
        #expect(dropped("\(attributes),\(time)") == 1)
        #expect(dropped("\(attributes),\(time),\"asDouble\":-1") == 1)
        #expect(dropped("\(attributes),\(time),\"asDouble\":0", metric: "bar.limit.resets_at") == 1)
        #expect(dropped("\(attributes),\(time),\"asDouble\":40", type: "sum") == 1)
        #expect(dropped("\"attributes\":[],\(time),\"asDouble\":40") == 1)
    }
}
