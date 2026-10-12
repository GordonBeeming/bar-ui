import Foundation
import Testing
@testable import BarUICore

@Suite("Telemetry Spec v1 reset events")
struct LogEventParserTests {
    @Test("ClaudeBar's reset events carry the utilisation just before each reset")
    func claudeBarFixture() throws {
        let data = try Fixtures.data(named: "claudebar-logs-2026-10-12.jsonl")

        let result = LogEventParser.parse(data, from: .claudeBar)

        #expect(result.droppedRecords == 0)
        #expect(result.consumedByteCount == data.count)
        let resets = result.resets.sorted { $0.timeUnixNano < $1.timeUnixNano }
        #expect(resets.map(\.limit.id) == ["weekly_all", "session", "session"])
        #expect(resets.map(\.utilizationLast) == [88, 30, 71.5])
        #expect(resets.map(\.timeUnixNano) == [1_791_700_000_000_000_000, 1_791_762_000_000_000_000, 1_791_780_000_000_000_000])
        #expect(resets.last?.nextResetsAt == Date(timeIntervalSince1970: 1_791_798_000))
        #expect(resets.last?.limit.windowDurationMinutes == 300)
        #expect(resets.last?.app == .claudeBar)
    }

    @Test("Events other than a reset are skipped without counting as dropped")
    func ignoresOtherEvents() throws {
        let data = try Fixtures.data(named: "claudebar-logs-2026-10-12.jsonl")

        let result = LogEventParser.parse(data, from: .claudeBar)

        #expect(result.resets.count == 3)
        #expect(result.droppedRecords == 0)
    }

    @Test("A reset without a usable last utilisation or Limit ID is dropped and counted")
    func brokenResetsAreDropped() {
        let missing = Self.line(attributes: Self.limit)
        let outOfRange = Self.line(attributes: Self.limit + [Self.utilizationLast(120)])
        let noLimitID = Self.line(attributes: [Self.utilizationLast(10)])
        let data = Data((missing + outOfRange + noLimitID).utf8)

        let result = LogEventParser.parse(data, from: .codexBar)

        #expect(result.resets.isEmpty)
        #expect(result.droppedRecords == 3)
    }

    @Test("A reset with no next reset time is kept, and a Window of unknown length is allowed")
    func optionalFields() {
        let line = Self.line(attributes: [
            #"{"key":"limit.id","value":{"stringValue":"codex:primary"}}"#,
            #"{"key":"limit.name","value":{"stringValue":"Primary"}}"#,
            Self.utilizationLast(55)
        ])

        let result = LogEventParser.parse(Data(line.utf8), from: .codexBar)

        #expect(result.droppedRecords == 0)
        #expect(result.resets.count == 1)
        #expect(result.resets.first?.nextResetsAt == nil)
        #expect(result.resets.first?.limit.windowDurationMinutes == nil)
    }

    @Test("An event whose name isn't a string breaks the spec, so it is dropped and counted rather than skipped as unknown")
    func wrongTypedEventName() {
        let line = Self.line(attributes: Self.limit + [Self.utilizationLast(10)])
            .replacingOccurrences(of: #""eventName":"bar.limit.reset""#, with: #""eventName":42"#)

        let result = LogEventParser.parse(Data(line.utf8), from: .codexBar)

        #expect(result.resets.isEmpty)
        #expect(result.droppedRecords == 1)
    }

    @Test("A reset with an optional attribute of the wrong type is dropped and counted, not read as if it were absent")
    func wrongTypedOptionalAttribute() {
        let line = Self.line(attributes: Self.limit + [
            Self.utilizationLast(10),
            #"{"key":"model.id","value":{"stringValue":7}}"#
        ])

        let result = LogEventParser.parse(Data(line.utf8), from: .codexBar)

        #expect(result.resets.isEmpty)
        #expect(result.droppedRecords == 1)
    }

    @Test("Another Bar App's records are dropped")
    func wrongResource() throws {
        let data = try Fixtures.data(named: "claudebar-logs-2026-10-12.jsonl")

        let result = LogEventParser.parse(data, from: .codexBar)

        #expect(result.resets.isEmpty)
        #expect(result.droppedRecords == 2)
    }

    @Test("A trailing partial line waits for the next read")
    func partialLine() {
        let complete = Self.line(attributes: Self.limit + [Self.utilizationLast(10)])
        let data = Data((complete + #"{"resourceLogs":[{"res"#).utf8)

        let result = LogEventParser.parse(data, from: .codexBar)

        #expect(result.resets.count == 1)
        #expect(result.consumedByteCount == complete.utf8.count)
    }

    private static let limit = [
        #"{"key":"limit.id","value":{"stringValue":"codex:10080"}}"#,
        #"{"key":"limit.name","value":{"stringValue":"Weekly"}}"#,
        #"{"key":"limit.window.duration_minutes","value":{"intValue":"10080"}}"#
    ]

    private static func utilizationLast(_ value: Double) -> String {
        #"{"key":"limit.utilization.last","value":{"doubleValue":\#(value)}}"#
    }

    /// One conforming CodexBar log line holding a single `bar.limit.reset`.
    private static func line(attributes: [String]) -> String {
        """
        {"resourceLogs":[{"resource":{"attributes":[{"key":"service.name","value":{"stringValue":"codexbar"}},{"key":"bar.spec.version","value":{"stringValue":"1"}}]},"scopeLogs":[{"logRecords":[{"timeUnixNano":"1791791100000000000","eventName":"bar.limit.reset","attributes":[\(attributes.joined(separator: ","))]}]}]}]}

        """
    }
}
