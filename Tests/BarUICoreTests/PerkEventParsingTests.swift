import Foundation
import Testing
@testable import BarUICore

@Suite("Perk events in Telemetry Spec v1 logs")
struct PerkEventParsingTests {
    private let time: Int64 = 1_791_791_100_000_000_000

    @Test("A gone event keeps its kind, quantity, expiry, id and the reason the Bar App wrote")
    func readsGoneEvent() throws {
        let data = PerkEventLine.logs(service: "codexbar", events: [
            .init(name: "bar.perk.gone", kind: "reset_credit", time: time, quantity: .int(1), perkID: "rc-1", expiresAt: 1_792_000_000, reason: "used")
        ])

        let result = LogEventParser.parse(data, from: .codexBar)

        #expect(result.droppedRecords == 0)
        #expect(result.consumedByteCount == data.count)
        let event = try #require(result.perkGoneEvents.first)
        #expect(result.perkGoneEvents.count == 1)
        #expect(event.app == .codexBar)
        #expect(event.kind == .resetCredit)
        #expect(event.quantity == 1)
        #expect(event.perkID == "rc-1")
        #expect(event.expiresAt == 1_792_000_000)
        #expect(event.reportedReason == .used)
        #expect(event.timeUnixNano == time)
    }

    @Test("A missing quantity is one for counted Perks and unknown for a Credit Grant")
    func quantityDefaults() {
        let data = PerkEventLine.logs(service: "claudebar", events: [
            .init(name: "bar.perk.gone", kind: "guest_pass", time: time),
            .init(name: "bar.perk.gone", kind: "credit_grant", currency: "AUD", time: time + 1),
            .init(name: "bar.perk.gone", kind: "credit_grant", currency: "AUD", time: time + 2, quantity: .double(7.5))
        ])

        let result = LogEventParser.parse(data, from: .claudeBar)

        #expect(result.perkGoneEvents.map(\.quantity) == [1, nil, 7.5])
        #expect(result.perkGoneEvents.map(\.currency) == [nil, "AUD", "AUD"])
        #expect(result.perkGoneEvents.map(\.reportedReason) == [nil, nil, nil])
    }

    @Test("Available events and events Bar UI doesn't read are not gone events and not dropped")
    func ignoresOtherEvents() {
        let data = PerkEventLine.logs(service: "claudebar", events: [
            .init(name: "bar.perk.available", kind: "guest_pass", time: time),
            .init(name: "claude.something", kind: nil, time: time)
        ])

        let result = LogEventParser.parse(data, from: .claudeBar)

        #expect(result.perkGoneEvents.isEmpty)
        #expect(result.droppedRecords == 0)
    }

    @Test("Perk events that break the spec, and other apps' or versions' records, are dropped and counted")
    func dropsNonConforming() {
        var data = PerkEventLine.logs(service: "claudebar", events: [
            .init(name: "bar.perk.gone", kind: "coupon", time: time),
            .init(name: "bar.perk.gone", kind: "credit_grant", time: time),
            .init(name: "bar.perk.gone", kind: "guest_pass", time: time, quantity: .int(0)),
            .init(name: "bar.perk.gone", kind: "guest_pass", time: time, reason: "stolen"),
            .init(name: "bar.perk.gone", kind: "guest_pass", time: 0),
            .init(name: "bar.perk.available", kind: "coupon", time: time)
        ])
        data += PerkEventLine.logs(service: "codexbar", events: [.init(name: "bar.perk.gone", kind: "guest_pass", time: time)])
        data += PerkEventLine.logs(service: "claudebar", specVersion: "2", events: [.init(name: "bar.perk.gone", kind: "guest_pass", time: time)])
        data += Data("not json\n".utf8)

        let result = LogEventParser.parse(data, from: .claudeBar)

        #expect(result.perkGoneEvents.isEmpty)
        #expect(result.droppedRecords == 9)
    }

    @Test("A half-written last line waits for the next read")
    func partialLine() {
        let line = PerkEventLine.logs(service: "claudebar", events: [.init(name: "bar.perk.gone", kind: "guest_pass", time: time)])
        let data = line + line.prefix(30)

        let result = LogEventParser.parse(data, from: .claudeBar)

        #expect(result.perkGoneEvents.count == 1)
        #expect(result.consumedByteCount == line.count)
    }
}

enum PerkEventLine {
    enum Quantity {
        case int(Int)
        case double(Double)
    }

    struct Event {
        var name: String
        var kind: String?
        var currency: String?
        var time: Int64
        var quantity: Quantity?
        var perkID: String?
        var expiresAt: Int64?
        var reason: String?

        init(
            name: String,
            kind: String?,
            currency: String? = nil,
            time: Int64,
            quantity: Quantity? = nil,
            perkID: String? = nil,
            expiresAt: Int64? = nil,
            reason: String? = nil
        ) {
            self.name = name
            self.kind = kind
            self.currency = currency
            self.time = time
            self.quantity = quantity
            self.perkID = perkID
            self.expiresAt = expiresAt
            self.reason = reason
        }
    }

    static func logs(service: String, specVersion: String = "1", events: [Event]) -> Data {
        let resource = ConformingEnvelope.resourceAttributes(service: service, specVersion: specVersion)
        let scope = ConformingEnvelope.scope(service: service)
        let request: [String: Any] = ["resourceLogs": [["resource": ["attributes": resource], "scopeLogs": [["scope": scope, "logRecords": events.map(record)]]]]]
        return PerkLine.line(request)
    }

    private static func record(_ event: Event) -> [String: Any] {
        var attributes: [[String: Any]] = []
        func string(_ key: String, _ value: String?) {
            if let value {
                attributes.append(["key": key, "value": ["stringValue": value]])
            }
        }
        string("perk.kind", event.kind)
        string("perk.currency", event.currency)
        string("perk.id", event.perkID)
        string("perk.gone.reason", event.reason)
        switch event.quantity {
        case .int(let value): attributes.append(["key": "perk.quantity", "value": ["intValue": String(value)]])
        case .double(let value): attributes.append(["key": "perk.quantity", "value": ["doubleValue": value]])
        case nil: break
        }
        if let expiresAt = event.expiresAt {
            attributes.append(["key": "perk.expires_at", "value": ["intValue": String(expiresAt)]])
        }
        return [
            "eventName": event.name,
            "severityNumber": 9,
            "timeUnixNano": String(event.time),
            "observedTimeUnixNano": String(event.time),
            "attributes": attributes
        ]
    }
}
