import Foundation
import Testing
@testable import BarUICore

@Suite("Telemetry Spec v1 metrics parsing")
struct MetricsParserTests {
    @Test("ClaudeBar's spec v1 file yields each Limit's utilisation and reset time")
    func claudeBarFixture() throws {
        let data = try Fixtures.data(named: "claudebar-metrics-2026-10-12.jsonl")

        let result = MetricsParser.parse(data, from: .claudeBar)

        #expect(result.droppedRecords == 0)
        #expect(result.consumedByteCount == data.count)
        let latest = result.samples.filter { $0.timeUnixNano == 1_791_791_400_000_000_000 }
        #expect(latest.count == 6)

        let opus = try #require(latest.first { $0.limit.id == "weekly_scoped:claude-opus-4-1" && $0.metric == .utilization })
        #expect(opus.app == .claudeBar)
        #expect(opus.limit.name == "Weekly · Opus")
        #expect(opus.limit.windowDurationMinutes == 10080)
        #expect(opus.limit.modelID == "claude-opus-4-1")
        #expect(opus.value == 82)

        let sessionReset = try #require(latest.first { $0.limit.id == "session" && $0.metric == .resetsAt })
        #expect(sessionReset.value == 1_791_796_200)
        #expect(sessionReset.limit.windowDurationMinutes == 300)
        #expect(sessionReset.limit.modelID == nil)
    }

    @Test("CodexBar's spec v1 file yields its weekly Limit")
    func codexBarFixture() throws {
        let data = try Fixtures.data(named: "codexbar-metrics-2026-10-12.jsonl")

        let result = MetricsParser.parse(data, from: .codexBar)

        #expect(result.droppedRecords == 0)
        #expect(result.samples.count == 4)
        let utilisations = result.samples.filter { $0.metric == .utilization }.map(\.value)
        #expect(utilisations == [17, 18.5])
        #expect(result.samples.allSatisfy { $0.limit.id == "codex:10080" && $0.limit.name == "Weekly" && $0.app == .codexBar })
        let reset = try #require(result.samples.first { $0.metric == .resetsAt })
        #expect(reset.value == 1_792_310_768)
    }

    @Test("A last line without its newline is left unread until it's finished")
    func partialLine() throws {
        let data = try Fixtures.data(named: "codexbar-metrics-2026-10-12.jsonl")
        let firstLineEnd = try #require(data.firstIndex(of: UInt8(ascii: "\n")))
        let cutMidway = data.prefix(firstLineEnd + 1 + 40)

        let result = MetricsParser.parse(cutMidway, from: .codexBar)

        #expect(result.consumedByteCount == firstLineEnd + 1)
        #expect(result.samples.count == 2)
        #expect(result.droppedRecords == 0)
    }

    @Test("A Limit whose Window length isn't known is still read, and the fallback IDs are kept as given")
    func unknownWindow() {
        let line = MetricsLine.limits(service: "codexbar", points: [
            .utilization(id: "codex:primary", name: "Weekly", value: 12)
        ])

        let result = MetricsParser.parse(line, from: .codexBar)

        #expect(result.droppedRecords == 0)
        let sample = result.samples.first
        #expect(sample?.limit.id == "codex:primary")
        #expect(sample?.limit.windowDurationMinutes == nil)
    }

    @Test("Records that break the spec are dropped and counted; the valid ones on the same line still count")
    func nonConforming() {
        let line = MetricsLine.limits(service: "claudebar", points: [
            .utilization(id: "session", name: "Session (5h)", value: 40, minutes: 300),
            .utilization(id: "session", name: "Session (5h)", value: 140, minutes: 300),
            .utilization(id: "weekly_all", name: "Weekly", value: 10, minutes: 0),
            .utilization(id: "", name: "Weekly", value: 10),
            .utilization(id: "weekly_all", name: "", value: 10)
        ])

        let result = MetricsParser.parse(line, from: .claudeBar)

        #expect(result.samples.map(\.value) == [40])
        #expect(result.droppedRecords == 4)
    }

    @Test("A record without spec version 1, or from the other Bar App, is dropped whole")
    func wrongResource() {
        let points: [MetricsLine.Point] = [.utilization(id: "session", name: "Session", value: 1)]
        var data = MetricsLine.limits(service: "claudebar", specVersion: "2", points: points)
        data += MetricsLine.limits(service: "claudebar", specVersion: nil, points: points)
        data += MetricsLine.limits(service: "codexbar", points: points)
        data += Data("not json\n".utf8)

        let result = MetricsParser.parse(data, from: .claudeBar)

        #expect(result.samples.isEmpty)
        #expect(result.droppedRecords == 4)
    }

    @Test("Metrics the spec doesn't ask Bar UI to read are skipped without counting as non-conforming")
    func unknownMetricsIgnored() throws {
        let line = Data((#"{"resourceMetrics":[{"resource":{"attributes":[{"key":"service.name","value":{"stringValue":"codexbar"}},{"key":"bar.spec.version","value":{"stringValue":"1"}}]},"scopeMetrics":[{"metrics":[{"name":"codex.usage.used_percent","sum":{"dataPoints":[{"asDouble":3}]}}]}]}]}"# + "\n").utf8)

        let result = MetricsParser.parse(line, from: .codexBar)

        #expect(result.samples.isEmpty)
        #expect(result.droppedRecords == 0)
    }
}

/// Builds single OTLP/JSON metrics lines for the cases the fixture files
/// deliberately don't contain.
enum MetricsLine {
    struct Point {
        let metric: String
        let id: String
        let name: String
        let minutes: Int?
        let value: Double
        let time: Int64

        static func utilization(id: String, name: String, value: Double, minutes: Int? = nil, time: Int64 = 1_791_791_100_000_000_000) -> Point {
            Point(metric: "bar.limit.utilization", id: id, name: name, minutes: minutes, value: value, time: time)
        }

        static func resetsAt(id: String, name: String, unixSeconds: Int64, minutes: Int? = nil, time: Int64 = 1_791_791_100_000_000_000) -> Point {
            Point(metric: "bar.limit.resets_at", id: id, name: name, minutes: minutes, value: Double(unixSeconds), time: time)
        }
    }

    static func limits(service: String, specVersion: String? = "1", points: [Point]) -> Data {
        var resource: [[String: Any]] = [["key": "service.name", "value": ["stringValue": service]]]
        if let specVersion {
            resource.append(["key": "bar.spec.version", "value": ["stringValue": specVersion]])
        }
        let metrics: [[String: Any]] = Dictionary(grouping: points, by: \.metric).sorted { $0.key > $1.key }.map { name, points in
            ["name": name, "gauge": ["dataPoints": points.map(dataPoint)]]
        }
        let request: [String: Any] = ["resourceMetrics": [["resource": ["attributes": resource], "scopeMetrics": [["metrics": metrics]]]]]
        do {
            return try JSONSerialization.data(withJSONObject: request) + Data("\n".utf8)
        } catch {
            Issue.record("Couldn't build a metrics line: \(error)")
            return Data()
        }
    }

    private static func dataPoint(_ point: Point) -> [String: Any] {
        var attributes: [[String: Any]] = [
            ["key": "limit.id", "value": ["stringValue": point.id]],
            ["key": "limit.name", "value": ["stringValue": point.name]]
        ]
        if let minutes = point.minutes {
            attributes.append(["key": "limit.window.duration_minutes", "value": ["intValue": String(minutes)]])
        }
        return ["attributes": attributes, "timeUnixNano": String(point.time), "asDouble": point.value]
    }
}

enum Fixtures {
    static func url(named name: String) throws -> URL {
        try #require(Bundle.module.url(forResource: name, withExtension: nil, subdirectory: "Fixtures"))
    }

    static func data(named name: String) throws -> Data {
        try Data(contentsOf: url(named: name))
    }
}
