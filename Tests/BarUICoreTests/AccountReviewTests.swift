import Foundation
import Testing
@testable import BarUICore

/// One small conforming line, so a test controls exactly the account
/// attributes and the times a resource reports.
private enum Line {
    static func resourceAttributes(_ extra: [String]) -> String {
        let base = [
            #"{"key":"service.name","value":{"stringValue":"claudebar"}}"#,
            #"{"key":"service.version","value":{"stringValue":"1.0"}}"#,
            #"{"key":"host.name","value":{"stringValue":"test-mac.local"}}"#,
            #"{"key":"os.type","value":{"stringValue":"darwin"}}"#,
            #"{"key":"bar.spec.version","value":{"stringValue":"1"}}"#
        ]
        return "[" + (base + extra).joined(separator: ",") + "]"
    }

    static func attribute(_ key: String, _ value: String) -> String {
        #"{"key":"\#(key)","value":\#(value)}"#
    }

    static func metrics(time: Int64, extra: [String]) -> String {
        #"""
        {"resourceMetrics":[{"resource":{"attributes":\#(resourceAttributes(extra))},"scopeMetrics":[{"scope":{"name":"com.gordonbeeming.ClaudeBar.telemetry","version":"1.0"},"metrics":[{"name":"bar.limit.utilization","unit":"%","gauge":{"dataPoints":[{"asDouble":10,"timeUnixNano":"\#(time)","attributes":[{"key":"limit.id","value":{"stringValue":"weekly_all"}},{"key":"limit.name","value":{"stringValue":"Weekly"}}]}]}}]}]}]}
        """#
    }

    static func logs(time: Int64, extra: [String]) -> String {
        #"""
        {"resourceLogs":[{"resource":{"attributes":\#(resourceAttributes(extra))},"scopeLogs":[{"scope":{"name":"com.gordonbeeming.ClaudeBar.telemetry","version":"1.0"},"logRecords":[{"eventName":"bar.tracking.started","severityNumber":9,"timeUnixNano":"\#(time)","observedTimeUnixNano":"\#(time)","attributes":[{"key":"tracking.interval_minutes","value":{"intValue":"5"}}]}]}]}]}
        """#
    }

    static func name(_ name: String) -> String {
        attribute("account.name", #"{"stringValue":"\#(name)"}"#)
    }

    static func id(_ value: String) -> String {
        attribute("account.id", value)
    }

    static func data(_ lines: [String]) -> Data {
        Data((lines.joined(separator: "\n") + "\n").utf8)
    }
}

@Suite("Account names follow the newest report")
struct AccountNameTests {
    private static let account = #"{"stringValue":"work"}"#

    @Test("A name that goes A, B, A ends on A, whatever the lines in between")
    func lastReportedNameWins() {
        let data = Line.data([
            Line.metrics(time: 1_000, extra: [Line.id(Self.account), Line.name("A")]),
            Line.metrics(time: 2_000, extra: [Line.id(Self.account), Line.name("B")]),
            Line.metrics(time: 3_000, extra: [Line.id(Self.account), Line.name("A")])
        ])

        let read = MetricsParser.parse(data, from: .claudeBar, account: "work")

        #expect(read.droppedRecords == 0)
        #expect(read.accountNames == [AccountName(app: .claudeBar, accountID: "work", name: "A", reportedAt: 3_000)])
    }

    @Test("A report with an older time doesn't replace a newer one in the same file")
    func olderReportInTheSameFile() {
        let data = Line.data([
            Line.metrics(time: 5_000, extra: [Line.id(Self.account), Line.name("New")]),
            Line.metrics(time: 4_000, extra: [Line.id(Self.account), Line.name("Old")])
        ])

        let read = MetricsParser.parse(data, from: .claudeBar, account: "work")

        #expect(read.accountNames.map(\.name) == ["New"])
    }

    @Test("Log files report names the same way")
    func logsKeepTheLastName() {
        let data = Line.data([
            Line.logs(time: 1_000, extra: [Line.id(Self.account), Line.name("A")]),
            Line.logs(time: 2_000, extra: [Line.id(Self.account), Line.name("B")]),
            Line.logs(time: 3_000, extra: [Line.id(Self.account), Line.name("A")])
        ])

        let read = LogEventParser.parse(data, from: .claudeBar, account: "work")

        #expect(read.accountNames == [AccountName(app: .claudeBar, accountID: "work", name: "A", reportedAt: 3_000)])
    }

    @Test("Importing an older file after a newer one doesn't undo a rename")
    func archiveKeepsTheNewestName() async throws {
        let folder = try TemporaryFolder()
        let archive = try Archive(url: folder.url.appendingPathComponent("Archive.sqlite"))
        let work = BarAppAccount(app: .claudeBar, accountID: "work")
        func report(_ name: String, at time: Int64, file: String) async throws {
            try await archive.record(
                TelemetryRecords(accountNames: [AccountName(app: .claudeBar, accountID: "work", name: name, reportedAt: time)]),
                progress: ImportProgress(app: .claudeBar, fileName: file, byteOffset: 1, droppedRecords: 0)
            )
        }

        try await report("Renamed", at: 20, file: "claudebar.work-metrics-2026-10-13.jsonl")
        try await report("Before the rename", at: 10, file: "claudebar.work-metrics-2026-10-12.jsonl")
        #expect(try await archive.accountNames()[work] == "Renamed")

        // The same time reads as the same report, so the later one read stands.
        try await report("Same time", at: 20, file: "claudebar.work-metrics-2026-10-14.jsonl")
        #expect(try await archive.accountNames()[work] == "Same time")
    }
}

@Suite("A present account.id has to be a valid string")
struct AccountIDPresenceTests {
    private func samples(in extra: [String], account: String = BarAppAccount.defaultID) -> (read: Int, dropped: Int) {
        let read = MetricsParser.parse(Line.data([Line.metrics(time: 1_000, extra: extra)]), from: .claudeBar, account: account)
        return (read.limitSamples.count, read.droppedRecords)
    }

    @Test("Absent means default, and a string default is the same Account")
    func absentAndExplicitDefault() {
        #expect(samples(in: []).read == 1)
        #expect(samples(in: [Line.id(#"{"stringValue":"default"}"#)]).read == 1)
    }

    @Test("A value of another type is a broken record, not an absent one")
    func wrongTypesAreRejected() {
        let wrong = [
            #"{"intValue":"5"}"#,
            #"{"doubleValue":1.5}"#,
            #"{"boolValue":true}"#,
            #"{"stringValue":7}"#,
            "{}"
        ]
        for value in wrong {
            let result = samples(in: [Line.id(value)])
            #expect(result.read == 0, "\(value)")
            #expect(result.dropped > 0, "\(value)")
        }
    }

    @Test("A string outside the id grammar, or for another Account, is rejected")
    func wrongStringsAreRejected() {
        for id in ["", "Work", "a b", "a.b"] {
            #expect(samples(in: [Line.id(#"{"stringValue":"\#(id)"}"#)], account: id).read == 0, "\(id)")
        }
        #expect(samples(in: [Line.id(#"{"stringValue":"work"}"#)]).read == 0)
        #expect(samples(in: [Line.id(#"{"stringValue":"work"}"#)], account: "work").read == 1)
    }
}

@Suite("Labels with Accounts")
@MainActor
struct AccountLabelTests {
    private func overview(names: [String: String]) async throws -> LimitsOverview {
        let folder = try TemporaryFolder()
        let archive = try Archive(url: folder.url.appendingPathComponent("Archive.sqlite"))
        for (id, name) in names {
            try await archive.record(
                TelemetryRecords(accountNames: [AccountName(app: .claudeBar, accountID: id, name: name, reportedAt: 1)]),
                progress: ImportProgress(app: .claudeBar, fileName: "claudebar.\(id)-metrics-2026-10-12.jsonl", byteOffset: 1, droppedRecords: 0)
            )
            try await archive.record(
                TelemetryRecords(perkSamples: [PerkSample(app: .claudeBar, accountID: id, kind: .guestPass, currency: nil, timeUnixNano: 1, value: 1, expiresAt: nil)]),
                progress: ImportProgress(app: .claudeBar, fileName: "claudebar.\(id)-metrics-2026-10-12.jsonl", byteOffset: 2, droppedRecords: 0)
            )
        }
        let overview = LimitsOverview(archive: archive)
        await overview.refresh(statuses: [:])
        return overview
    }

    @Test("Tracking events are named for the Bar App, whatever Accounts it has")
    func trackingEventsAreAppScoped() async throws {
        let overview = try await overview(names: ["work": "work@example.com", "home": "home@example.com"])
        let tracking = OverviewEvent(id: "t", app: .claudeBar, kind: .trackingStarted, title: "Tracking started", detail: "", date: .now)
        let reset = OverviewEvent(id: "r", app: .claudeBar, kind: .limitReset, title: "Weekly reset", detail: "", date: .now, accountID: "work")

        #expect(overview.label(of: tracking) == "ClaudeBar")
        #expect(overview.colorStep(of: tracking) == 0)
        #expect(overview.label(of: reset) == "ClaudeBar · work@example.com")
        #expect(overview.colorStep(of: reset) == 1)
    }

    @Test("Accounts that report the same name stay distinct by id, and keep distinct chart keys")
    func collidingNames() async throws {
        let overview = try await overview(names: ["work": "Same", "home": "Same", "other": "Different"])
        let work = BarAppAccount(app: .claudeBar, accountID: "work")
        let home = BarAppAccount(app: .claudeBar, accountID: "home")

        #expect(overview.label(of: work) == "Same (work)")
        #expect(overview.label(of: home) == "Same (home)")
        #expect(overview.label(of: BarAppAccount(app: .claudeBar, accountID: "other")) == "Different")
        #expect(overview.seriesLabel(of: work) != overview.seriesLabel(of: home))
        // The chart colours by this key, so it can't depend on the label.
        #expect(work.id != home.id)
    }
}
