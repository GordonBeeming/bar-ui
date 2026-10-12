import Foundation
import Testing
@testable import BarUICore

@Suite("Perks in the Archive")
struct PerkArchiveTests {
    private let t0: Int64 = 1_791_791_100_000_000_000
    private let minute: Int64 = 60_000_000_000

    @Test("The latest reading of each series is what's available now, with its expiry")
    func availableNow() async throws {
        let fixture = try ImportFixture()
        try fixture.write(
            PerkLine.metrics(service: "claudebar", points: [
                .init(kind: "reset_credit", value: 3, time: t0, expiresAt: 1_792_000_000),
                .init(kind: "credit_grant", currency: "USD", value: 20, time: t0)
            ]) + PerkLine.metrics(service: "claudebar", points: [
                .init(kind: "reset_credit", value: 2, time: t0 + minute, expiresAt: 1_792_500_000),
                .init(kind: "credit_grant", currency: "USD", value: 12.5, time: t0 + minute)
            ]),
            named: "claudebar-metrics-2026-10-12.jsonl", in: fixture.claudeFolder
        )

        _ = try await fixture.importer.importMetrics(of: .claudeBar, from: fixture.claudeFolder)

        let perks = try await fixture.archive.availablePerks()
        #expect(perks.map { "\($0.kind.rawValue)/\($0.currency ?? "-")=\($0.quantity)" } == [
            "reset_credit/-=2.0",
            "credit_grant/USD=12.5"
        ])
        #expect(perks.map(\.expiresAt) == [Date(timeIntervalSince1970: 1_792_500_000), nil])
        #expect(perks.map(\.sampledAt) == [Date(unixNano: t0 + minute), Date(unixNano: t0 + minute)])
    }

    @Test("A series whose latest reading is zero isn't available")
    func zeroIsNotAvailable() async throws {
        let fixture = try ImportFixture()
        try fixture.write(
            PerkLine.metrics(service: "codexbar", points: [.init(kind: "guest_pass", value: 1, time: t0)])
                + PerkLine.metrics(service: "codexbar", points: [.init(kind: "guest_pass", value: 0, time: t0 + minute)]),
            named: "codexbar-metrics-2026-10-12.jsonl", in: fixture.codexFolder
        )

        _ = try await fixture.importer.importMetrics(of: .codexBar, from: fixture.codexFolder)

        #expect(try await fixture.archive.availablePerks().isEmpty)
    }

    @Test("Gone Perks come newest first, each with the reason from the event or the rule")
    func goneHistory() async throws {
        let fixture = try ImportFixture()
        let expiry: Int64 = 1_791_791_200
        try fixture.write(
            PerkEventLine.logs(service: "codexbar", events: [
                .init(name: "bar.perk.gone", kind: "reset_credit", time: t0, perkID: "a", expiresAt: expiry + 1_000, reason: "expired"),
                .init(name: "bar.perk.gone", kind: "reset_credit", time: t0 + minute, perkID: "b", expiresAt: expiry + 1_000),
                .init(name: "bar.perk.gone", kind: "guest_pass", time: t0 + 2 * minute, perkID: "c", expiresAt: expiry),
                .init(name: "bar.perk.gone", kind: "credit_grant", currency: "USD", time: t0 + 3 * minute, quantity: .double(5))
            ]),
            named: "codexbar-logs-2026-10-12.jsonl", in: fixture.codexFolder
        )

        let summary = try await fixture.importer.importMetrics(of: .codexBar, from: fixture.codexFolder)

        #expect(summary.filesRead == 1)
        let gone = try await fixture.archive.gonePerks()
        #expect(gone.map { "\($0.kind.rawValue)/\($0.perkID ?? "-")=\($0.reason.rawValue)" } == [
            "credit_grant/-=unknown",
            "guest_pass/c=expired",
            "reset_credit/b=used",
            "reset_credit/a=expired"
        ])
        #expect(gone.first?.quantity == 5)
        #expect(gone.first?.currency == "USD")
    }

    @Test("Reading the same logs again, or after the file shrank, adds no gone Perks twice")
    func reimportDoesNotDuplicate() async throws {
        let fixture = try ImportFixture()
        let data = PerkEventLine.logs(service: "claudebar", events: [
            .init(name: "bar.perk.gone", kind: "guest_pass", time: t0, quantity: .int(2)),
            .init(name: "bar.perk.gone", kind: "credit_grant", currency: "USD", time: t0 + minute)
        ])
        let file = try fixture.write(data, named: "claudebar-logs-2026-10-12.jsonl", in: fixture.claudeFolder)

        _ = try await fixture.importer.importMetrics(of: .claudeBar, from: fixture.claudeFolder)
        let again = try await fixture.importer.importMetrics(of: .claudeBar, from: fixture.claudeFolder)
        try Data(data.prefix(10)).write(to: file)
        _ = try await fixture.importer.importMetrics(of: .claudeBar, from: fixture.claudeFolder)
        try data.write(to: file)
        _ = try await fixture.importer.importMetrics(of: .claudeBar, from: fixture.claudeFolder)

        #expect(again.filesRead == 0)
        #expect(try await fixture.archive.gonePerks().count == 2)
    }

    @Test("Gone Perks stay after the Bar App deletes its logs, and bad events are counted")
    func survivesDeletionAndCountsDrops() async throws {
        let fixture = try ImportFixture()
        let file = try fixture.write(
            PerkEventLine.logs(service: "claudebar", events: [
                .init(name: "bar.perk.gone", kind: "guest_pass", time: t0),
                .init(name: "bar.perk.gone", kind: "coupon", time: t0)
            ]),
            named: "claudebar-logs-2026-10-12.jsonl", in: fixture.claudeFolder
        )

        let summary = try await fixture.importer.importMetrics(of: .claudeBar, from: fixture.claudeFolder)
        try FileManager.default.removeItem(at: file)
        _ = try await fixture.importer.importMetrics(of: .claudeBar, from: fixture.claudeFolder)

        #expect(summary.droppedRecords == 1)
        #expect(try await fixture.archive.gonePerks().count == 1)
        let progress = try await fixture.archive.progress(of: .claudeBar, fileName: "claudebar-logs-2026-10-12.jsonl")
        #expect(progress?.droppedRecords == 1)
    }

    @Test("Only this Bar App's logs files are read")
    func onlyLogsFiles() async throws {
        let fixture = try ImportFixture()
        let data = PerkEventLine.logs(service: "claudebar", events: [.init(name: "bar.perk.gone", kind: "guest_pass", time: t0)])
        try fixture.write(data, named: "codexbar-logs-2026-10-12.jsonl", in: fixture.claudeFolder)

        let summary = try await fixture.importer.importMetrics(of: .claudeBar, from: fixture.claudeFolder)
        let missing = try await fixture.importer.importMetrics(of: .claudeBar, from: fixture.folder.url.appendingPathComponent("Nowhere"))

        #expect(summary.filesRead == 0)
        #expect(missing.filesRead == 0)
        #expect(try await fixture.archive.gonePerks().isEmpty)
    }
}

extension ImportFixture {
    @discardableResult
    func write(_ data: Data, named name: String, in folder: URL) throws -> URL {
        let file = folder.appendingPathComponent(name)
        try data.write(to: file)
        return file
    }
}
