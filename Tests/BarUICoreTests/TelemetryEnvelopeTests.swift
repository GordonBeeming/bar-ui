import Foundation
import Testing
@testable import BarUICore

/// Spec §3's resource attributes and instrumentation scope, and §4's units,
/// as they apply to the `bar.*` records Bar UI reads.
@Suite("Telemetry Spec v1 resource, scope and units")
struct TelemetryEnvelopeTests {
    struct Breakage: Sendable, CustomTestStringConvertible {
        let testDescription: String
        let removedResourceKey: String?
        let osType: String
        let scope: [String: String]?
        let unit: String

        init(
            _ description: String,
            removedResourceKey: String? = nil,
            osType: String = "darwin",
            scope: [String: String]? = ["name": "com.gordonbeeming.ClaudeBar.telemetry", "version": "1.0"],
            unit: String = "%"
        ) {
            testDescription = description
            self.removedResourceKey = removedResourceKey
            self.osType = osType
            self.scope = scope
            self.unit = unit
        }
    }

    static let breakages: [Breakage] = [
        Breakage("no service.version", removedResourceKey: "service.version"),
        Breakage("no host.name", removedResourceKey: "host.name"),
        Breakage("no os.type", removedResourceKey: "os.type"),
        Breakage("os.type isn't darwin", osType: "linux"),
        Breakage("no scope", scope: nil),
        Breakage("another Bar App's scope name", scope: ["name": "com.gordonbeeming.CodexBar.telemetry", "version": "1.0"]),
        Breakage("no scope version", scope: ["name": "com.gordonbeeming.ClaudeBar.telemetry"]),
        Breakage("utilisation not in %", unit: "1")
    ]

    @Test("A bar.* metric outside a conforming resource and scope, or in the wrong unit, is dropped and counted", arguments: breakages)
    func metricsEnvelope(breakage: Breakage) {
        let data = Self.metricsLine(breakage, metric: "bar.limit.utilization")

        let result = MetricsParser.parse(data, from: .claudeBar)

        #expect(result.limitSamples.isEmpty)
        #expect(result.droppedRecords == 1)
    }

    static let wrongUnits: [(metric: String, unit: String)] = [
        (metric: "bar.limit.resets_at", unit: "%"),
        (metric: "bar.tokens", unit: "1")
    ]

    @Test("bar.limit.resets_at and bar.tokens in the wrong unit are dropped and counted", arguments: wrongUnits)
    func otherUnits(metric: String, unit: String) {
        let data = Self.metricsLine(Breakage("wrong unit", unit: unit), metric: metric)

        let result = MetricsParser.parse(data, from: .claudeBar)

        #expect(result.limitSamples.isEmpty)
        #expect(result.tokenSamples.isEmpty)
        #expect(result.droppedRecords == 1)
    }

    @Test("Each bar.* metric in the spec's own unit is read")
    func rightUnits() {
        let utilization = Self.metricsLine(Breakage("conforming"), metric: "bar.limit.utilization")
        let resetsAt = Self.metricsLine(Breakage("conforming", unit: "s"), metric: "bar.limit.resets_at")
        let tokens = Self.metricsLine(Breakage("conforming", unit: "{token}"), metric: "bar.tokens")

        let result = MetricsParser.parse(utilization + resetsAt + tokens, from: .claudeBar)

        #expect(result.droppedRecords == 0)
        #expect(result.limitSamples.count == 2)
        #expect(result.tokenSamples.count == 1)
    }

    static let appMetricBreakages: [Breakage] = [
        Breakage("no host.name", removedResourceKey: "host.name"),
        Breakage("no scope", scope: nil)
    ]

    @Test("App-prefixed metrics in a resource or scope that breaks §3 are ignored, not counted", arguments: appMetricBreakages)
    func appMetricsNotCounted(breakage: Breakage) {
        let data = Self.metricsLine(breakage, metric: "claude.usage.used_percent")

        #expect(MetricsParser.parse(data, from: .claudeBar).droppedRecords == 0)
    }

    static let logBreakages: [Breakage] = [
        Breakage("no service.version", removedResourceKey: "service.version"),
        Breakage("no host.name", removedResourceKey: "host.name"),
        Breakage("os.type isn't darwin", osType: "linux"),
        Breakage("no scope", scope: nil),
        Breakage("another Bar App's scope name", scope: ["name": "com.gordonbeeming.CodexBar.telemetry", "version": "1.0"]),
        Breakage("no scope version", scope: ["name": "com.gordonbeeming.ClaudeBar.telemetry"])
    ]

    @Test("A bar.* event outside a conforming resource and scope is dropped and counted", arguments: logBreakages)
    func logsEnvelope(breakage: Breakage) {
        let data = Self.logsLine(breakage, eventName: "bar.tracking.started")

        let result = LogEventParser.parse(data, from: .claudeBar)

        #expect(result.trackingStarts.isEmpty)
        #expect(result.droppedRecords == 1)
    }

    @Test("App-prefixed events in a resource or scope that breaks §3 are ignored, not counted", arguments: appMetricBreakages)
    func appEventsNotCounted(breakage: Breakage) {
        let data = Self.logsLine(breakage, eventName: "claude.usage.details")

        #expect(LogEventParser.parse(data, from: .claudeBar).droppedRecords == 0)
    }

    @Test("A conforming bar.* event is read")
    func conformingEvent() {
        let result = LogEventParser.parse(Self.logsLine(Breakage("conforming"), eventName: "bar.tracking.started"), from: .claudeBar)

        #expect(result.droppedRecords == 0)
        #expect(result.trackingStarts.count == 1)
    }

    private static func resource(_ breakage: Breakage) -> [[String: Any]] {
        ConformingEnvelope.resourceAttributes(service: "claudebar")
            .filter { $0["key"] as? String != breakage.removedResourceKey }
            .map { attribute in
                guard attribute["key"] as? String == "os.type" else {
                    return attribute
                }
                return ["key": "os.type", "value": ["stringValue": breakage.osType]]
            }
    }

    private static func scoped(_ breakage: Breakage, _ body: [String: Any]) -> [String: Any] {
        var scoped = body
        if let scope = breakage.scope {
            scoped["scope"] = scope
        }
        return scoped
    }

    private static func metricsLine(_ breakage: Breakage, metric: String) -> Data {
        let time = "1791791100000000000"
        var point: [String: Any] = ["timeUnixNano": time, "asInt": "40"]
        var body: [String: Any] = [:]
        if metric == "bar.tokens" {
            point["startTimeUnixNano"] = "1791700000000000000"
            point["attributes"] = [
                ["key": "model", "value": ["stringValue": "claude-opus-4-1"]],
                ["key": "token.type", "value": ["stringValue": "input"]]
            ]
            body["sum"] = ["aggregationTemporality": 2, "isMonotonic": true, "dataPoints": [point]]
        } else {
            point["attributes"] = [
                ["key": "limit.id", "value": ["stringValue": "session"]],
                ["key": "limit.name", "value": ["stringValue": "Session (5h)"]]
            ]
            body["gauge"] = ["dataPoints": [point]]
        }
        body["name"] = metric
        body["unit"] = breakage.unit
        let scopeMetrics = scoped(breakage, ["metrics": [body]])
        return PerkLine.line(["resourceMetrics": [["resource": ["attributes": resource(breakage)], "scopeMetrics": [scopeMetrics]]]])
    }

    private static func logsLine(_ breakage: Breakage, eventName: String) -> Data {
        let record: [String: Any] = [
            "eventName": eventName,
            "severityNumber": 9,
            "timeUnixNano": "1791791100000000000",
            "observedTimeUnixNano": "1791791100000000000",
            "attributes": [["key": "tracking.interval_minutes", "value": ["intValue": "5"]]]
        ]
        let scopeLogs = scoped(breakage, ["logRecords": [record]])
        return PerkLine.line(["resourceLogs": [["resource": ["attributes": resource(breakage)], "scopeLogs": [scopeLogs]]]])
    }
}
