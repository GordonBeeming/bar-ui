import Foundation
import Testing
@testable import BarUICore

@Suite("Telemetry Spec v1 token parsing")
struct TokenParsingTests {
    @Test("bar.tokens points are read with their model, type and counter start")
    func fixture() throws {
        let data = try Fixtures.data(named: "claudebar-metrics-2026-10-12.jsonl")

        let result = MetricsParser.parse(data, from: .claudeBar)

        #expect(result.droppedRecords == 0)
        #expect(result.tokenSamples.count == 4)
        let output = try #require(result.tokenSamples.last { $0.tokenType == .output })
        #expect(output == TokenSample(
            app: .claudeBar,
            model: "claude-opus-4-1",
            tokenType: .output,
            startTimeUnixNano: 1_791_700_000_000_000_000,
            timeUnixNano: 1_791_791_400_000_000_000,
            count: 564_812
        ))
    }

    @Test("Every spec Token Type is recognised")
    func tokenTypes() {
        let types = ["input", "cache_read", "cache_write_5m", "cache_write_1h", "cache_write", "output", "reasoning"]
        let points = types.map { Self.point(type: $0) }

        let result = MetricsParser.parse(Self.line(points: points), from: .claudeBar)

        #expect(result.tokenSamples.map(\.tokenType.rawValue) == types)
        #expect(result.droppedRecords == 0)
    }

    @Test("A token point that breaks the spec is dropped and counted, its neighbours kept")
    func brokenPoints() {
        let points = [
            Self.point(type: "input", value: "7"),
            Self.point(type: "bogus"),
            Self.point(type: "input", model: nil),
            Self.point(type: "input", start: nil),
            Self.point(type: "input", value: "-3"),
            Self.point(type: "input", value: "1.5")
        ]

        let result = MetricsParser.parse(Self.line(points: points), from: .claudeBar)

        #expect(result.tokenSamples.map(\.count) == [7])
        #expect(result.droppedRecords == 5)
    }

    @Test("bar.tokens that isn't a cumulative monotonic Sum is dropped")
    func wrongTemporality() {
        let delta = Self.line(points: [Self.point(type: "input")], temporality: 1)
        let notMonotonic = Self.line(points: [Self.point(type: "input")], monotonic: false)

        #expect(MetricsParser.parse(delta, from: .claudeBar).tokenSamples.isEmpty)
        #expect(MetricsParser.parse(delta, from: .claudeBar).droppedRecords == 1)
        #expect(MetricsParser.parse(notMonotonic, from: .claudeBar).tokenSamples.isEmpty)
        #expect(MetricsParser.parse(notMonotonic, from: .claudeBar).droppedRecords == 1)
    }

    static func point(type: String, model: String? = "m", start: String? = "1", value: String = "7") -> String {
        var attributes = [#"{"key":"token.type","value":{"stringValue":"\#(type)"}}"#]
        if let model {
            attributes.append(#"{"key":"model","value":{"stringValue":"\#(model)"}}"#)
        }
        let startField = start.map { #""startTimeUnixNano":"\#($0)","# } ?? ""
        let valueField = value.contains(".") ? #""asDouble":\#(value)"# : #""asInt":"\#(value)""#
        return #"{\#(valueField),\#(startField)"timeUnixNano":"5","attributes":[\#(attributes.joined(separator: ","))]}"#
    }

    static func line(points: [String], temporality: Int = 2, monotonic: Bool = true) -> Data {
        let json = #"{"resourceMetrics":[{"resource":\#(ConformingEnvelope.resourceJSON(service: "claudebar")),"scopeMetrics":[{"scope":\#(ConformingEnvelope.scopeJSON(service: "claudebar")),"metrics":[{"name":"bar.tokens","unit":"{token}","sum":{"aggregationTemporality":\#(temporality),"isMonotonic":\#(monotonic),"dataPoints":[\#(points.joined(separator: ","))]}}]}]}]}"#
        return Data((json + "\n").utf8)
    }
}
