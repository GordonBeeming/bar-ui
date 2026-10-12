import Foundation
import Testing
@testable import BarUICore

@Suite("Perk gauges in Telemetry Spec v1 metrics")
struct PerkMetricsParsingTests {
    private let time: Int64 = 1_791_791_100_000_000_000

    @Test("A Reset Credit count and a Credit Grant amount are read with their expiry")
    func readsKindsAndExpiry() throws {
        let data = PerkLine.metrics(service: "claudebar", points: [
            .init(kind: "reset_credit", value: 2, time: time, expiresAt: 1_792_000_000),
            .init(kind: "credit_grant", currency: "USD", value: 12.5, time: time)
        ])

        let result = MetricsParser.parse(data, from: .claudeBar)

        #expect(result.droppedRecords == 0)
        #expect(result.limitSamples.isEmpty)
        let reset = try #require(result.perkSamples.first { $0.kind == .resetCredit })
        #expect(reset.app == .claudeBar)
        #expect(reset.currency == nil)
        #expect(reset.value == 2)
        #expect(reset.expiresAt == 1_792_000_000)
        #expect(reset.timeUnixNano == time)
        let grant = try #require(result.perkSamples.first { $0.kind == .creditGrant })
        #expect(grant.currency == "USD")
        #expect(grant.value == 12.5)
        #expect(grant.expiresAt == nil)
    }

    @Test("Points with the same kind and currency in one sample add up, and the earliest expiry is kept")
    func sumsDuplicateKeys() throws {
        let data = PerkLine.metrics(service: "codexbar", points: [
            .init(kind: "guest_pass", value: 1, time: time, expiresAt: 1_793_000_000),
            .init(kind: "guest_pass", value: 2, time: time, expiresAt: 1_792_000_000),
            .init(kind: "guest_pass", value: 1, time: time + 1_000_000_000)
        ])

        let result = MetricsParser.parse(data, from: .codexBar)

        let samples = result.perkSamples.sorted { $0.timeUnixNano < $1.timeUnixNano }
        #expect(samples.map(\.value) == [3, 1])
        #expect(samples.map(\.expiresAt) == [1_792_000_000, nil])
        #expect(result.droppedRecords == 0)
    }

    @Test("Attributes other than the kind and currency don't split a series")
    func ignoresOtherAttributes() throws {
        let data = PerkLine.metrics(service: "claudebar", points: [
            .init(kind: "guest_pass", value: 1, time: time, extraAttribute: ("campaign", "spring")),
            .init(kind: "guest_pass", value: 1, time: time, extraAttribute: ("campaign", "summer"))
        ])

        let result = MetricsParser.parse(data, from: .claudeBar)

        #expect(result.perkSamples.map(\.value) == [2])
    }

    @Test("Points that break the spec are dropped and counted")
    func dropsNonConforming() {
        let data = PerkLine.metrics(service: "claudebar", points: [
            .init(kind: "coupon", value: 1, time: time),
            .init(kind: "credit_grant", value: 5, time: time),
            .init(kind: "credit_grant", currency: "", value: 5, time: time),
            .init(kind: "guest_pass", value: -1, time: time),
            .init(kind: "guest_pass", value: 1, time: 0),
            .init(kind: "guest_pass", value: 1, time: time, expiresAtText: "soon")
        ])

        let result = MetricsParser.parse(data, from: .claudeBar)

        #expect(result.perkSamples.isEmpty)
        #expect(result.droppedRecords == 6)
    }

    @Test("A zero count is a real sample: nothing is available")
    func zeroCount() {
        let data = PerkLine.metrics(service: "claudebar", points: [.init(kind: "reset_credit", value: 0, time: time)])

        let result = MetricsParser.parse(data, from: .claudeBar)

        #expect(result.perkSamples.map(\.value) == [0])
    }
}

enum PerkLine {
    struct Point {
        var kind: String
        var currency: String?
        var value: Double
        var time: Int64
        var expiresAt: Int64?
        var expiresAtText: String?
        var extraAttribute: (String, String)?

        init(
            kind: String,
            currency: String? = nil,
            value: Double,
            time: Int64,
            expiresAt: Int64? = nil,
            expiresAtText: String? = nil,
            extraAttribute: (String, String)? = nil
        ) {
            self.kind = kind
            self.currency = currency
            self.value = value
            self.time = time
            self.expiresAt = expiresAt
            self.expiresAtText = expiresAtText
            self.extraAttribute = extraAttribute
        }
    }

    static func metrics(service: String, points: [Point]) -> Data {
        let resource = ConformingEnvelope.resourceAttributes(service: service)
        let metric: [String: Any] = ["name": "bar.perk.available", "gauge": ["dataPoints": points.map(dataPoint)]]
        let scope = ConformingEnvelope.scope(service: service)
        let request: [String: Any] = ["resourceMetrics": [["resource": ["attributes": resource], "scopeMetrics": [["scope": scope, "metrics": [metric]]]]]]
        return line(request)
    }

    static func line(_ object: [String: Any]) -> Data {
        do {
            return try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]) + Data("\n".utf8)
        } catch {
            Issue.record("Couldn't build a Telemetry line: \(error)")
            return Data()
        }
    }

    private static func dataPoint(_ point: Point) -> [String: Any] {
        var attributes: [[String: Any]] = [["key": "perk.kind", "value": ["stringValue": point.kind]]]
        if let currency = point.currency {
            attributes.append(["key": "perk.currency", "value": ["stringValue": currency]])
        }
        if let expiresAt = point.expiresAt {
            attributes.append(["key": "perk.expires_at", "value": ["intValue": String(expiresAt)]])
        }
        if let text = point.expiresAtText {
            attributes.append(["key": "perk.expires_at", "value": ["stringValue": text]])
        }
        if let (key, value) = point.extraAttribute {
            attributes.append(["key": key, "value": ["stringValue": value]])
        }
        return ["attributes": attributes, "timeUnixNano": String(point.time), "asDouble": point.value]
    }
}
