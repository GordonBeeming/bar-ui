import Foundation
import Testing
@testable import BarUICore

@Suite("Tracking, Limit and Perk-available events in Telemetry Spec v1 logs")
struct LifecycleEventParsingTests {
    private let time: Int64 = 1_791_791_100_000_000_000

    @Test("Limit appeared and disappeared events keep the Limit and when it happened")
    func readsLimitEvents() {
        let data = LifecycleEventLine.logs(service: "claudebar", events: [
            .limit("bar.limit.appeared", id: "session", name: "Session (5h)", minutes: 300, time: time),
            .limit("bar.limit.disappeared", id: "weekly_scoped:Fable", name: "Weekly (Fable)", minutes: nil, time: time + 1)
        ])

        let result = LogEventParser.parse(data, from: .claudeBar)

        #expect(result.droppedRecords == 0)
        #expect(result.limitEvents.map(\.kind) == [.appeared, .disappeared])
        #expect(result.limitEvents.map(\.limit.id) == ["session", "weekly_scoped:Fable"])
        #expect(result.limitEvents.map(\.limit.windowDurationMinutes) == [300, nil])
        #expect(result.limitEvents.map(\.timeUnixNano) == [time, time + 1])
        #expect(result.limitEvents.allSatisfy { $0.app == .claudeBar })
    }

    @Test("A tracking started event keeps the sampling interval")
    func readsTrackingStarted() {
        let data = LifecycleEventLine.logs(service: "codexbar", events: [.tracking(minutes: 5, time: time)])

        let result = LogEventParser.parse(data, from: .codexBar)

        #expect(result.droppedRecords == 0)
        #expect(result.trackingStarts == [TrackingStartedEvent(app: .codexBar, intervalMinutes: 5, timeUnixNano: time)])
    }

    @Test("An available event keeps its kind, quantity, expiry and id, held to the same rules as a gone event")
    func readsPerkAvailable() throws {
        let data = LifecycleEventLine.logs(service: "claudebar", events: [
            .perk("bar.perk.available", kind: "credit_grant", currency: "AUD", quantity: 12.5, expiresAt: 1_792_000_000, time: time),
            .perk("bar.perk.available", kind: "guest_pass", time: time + 1),
            .perk("bar.perk.available", kind: "coupon", time: time + 2)
        ])

        let result = LogEventParser.parse(data, from: .claudeBar)

        #expect(result.droppedRecords == 1)
        #expect(result.perkAvailableEvents.count == 2)
        let grant = try #require(result.perkAvailableEvents.first)
        #expect(grant.kind == .creditGrant)
        #expect(grant.currency == "AUD")
        #expect(grant.quantity == 12.5)
        #expect(grant.expiresAt == 1_792_000_000)
        #expect(result.perkAvailableEvents.last?.quantity == 1)
        #expect(result.perkGoneEvents.isEmpty)
    }

    @Test("Events that break the spec are dropped and counted")
    func dropsNonConforming() {
        let data = LifecycleEventLine.logs(service: "claudebar", events: [
            .limit("bar.limit.appeared", id: "", name: "x", minutes: nil, time: time),
            .limit("bar.limit.disappeared", id: "a", name: "x", minutes: nil, time: 0),
            .tracking(minutes: 0, time: time),
            .tracking(minutes: 1441, time: time),
            .tracking(minutes: nil, time: time)
        ])

        let result = LogEventParser.parse(data, from: .claudeBar)

        #expect(result.droppedRecords == 5)
        #expect(result.limitEvents.isEmpty)
        #expect(result.trackingStarts.isEmpty)
    }
}

enum LifecycleEventLine {
    struct Event {
        let name: String
        let time: Int64
        let attributes: [[String: Any]]

        static func limit(_ name: String, id: String, name limitName: String, minutes: Int?, time: Int64) -> Event {
            var attributes: [[String: Any]] = [
                ["key": "limit.id", "value": ["stringValue": id]],
                ["key": "limit.name", "value": ["stringValue": limitName]]
            ]
            if let minutes {
                attributes.append(["key": "limit.window.duration_minutes", "value": ["intValue": String(minutes)]])
            }
            return Event(name: name, time: time, attributes: attributes)
        }

        static func tracking(minutes: Int?, time: Int64) -> Event {
            Event(name: "bar.tracking.started", time: time, attributes: minutes.map {
                [["key": "tracking.interval_minutes", "value": ["intValue": String($0)]]]
            } ?? [])
        }

        static func perk(_ name: String, kind: String, currency: String? = nil, quantity: Double? = nil, expiresAt: Int64? = nil, time: Int64) -> Event {
            var attributes: [[String: Any]] = [["key": "perk.kind", "value": ["stringValue": kind]]]
            if let currency {
                attributes.append(["key": "perk.currency", "value": ["stringValue": currency]])
            }
            if let quantity {
                attributes.append(["key": "perk.quantity", "value": ["doubleValue": quantity]])
            }
            if let expiresAt {
                attributes.append(["key": "perk.expires_at", "value": ["intValue": String(expiresAt)]])
            }
            return Event(name: name, time: time, attributes: attributes)
        }
    }

    static func logs(service: String, events: [Event]) -> Data {
        let resource = ConformingEnvelope.resourceAttributes(service: service)
        let records: [[String: Any]] = events.map {
            [
                "eventName": $0.name,
                "severityNumber": 9,
                "timeUnixNano": String($0.time),
                "observedTimeUnixNano": String($0.time),
                "attributes": $0.attributes
            ]
        }
        return PerkLine.line(["resourceLogs": [["resource": ["attributes": resource], "scopeLogs": [["scope": ConformingEnvelope.scope(service: service), "logRecords": records]]]]])
    }
}
