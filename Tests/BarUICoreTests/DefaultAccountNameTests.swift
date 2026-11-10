import Foundation
import Testing
@testable import BarUICore

@Suite("The default Account's name")
@MainActor
struct DefaultAccountNameTests {
    private static let name = "me@example.com"
    private static let file = "claudebar-metrics-2026-10-12.jsonl"
    private static let defaultAccount = BarAppAccount(app: .claudeBar)

    private static func status(folder: URL) -> BarAppStatus {
        BarAppStatus(state: .tracking, settings: TrackingSettings(enabled: true, intervalMinutes: 5, retentionDays: 90, folder: folder))
    }

    @Test("A default file that names itself, with account.id written out as default, gives the default its name")
    func explicitDefaultIsNamed() async throws {
        let fixture = try ImportFixture()
        try AccountFixture.write(from: Self.file, accountID: "default", name: Self.name, as: Self.file, in: fixture.claudeFolder)

        let summary = try await fixture.importer.importMetrics(of: .claudeBar, from: fixture.claudeFolder)

        #expect(summary.droppedRecords == 0)
        #expect(try await fixture.archive.accountNames()[Self.defaultAccount] == Self.name)
        let overview = LimitsOverview(archive: fixture.archive)
        await overview.refresh(statuses: [.claudeBar: Self.status(folder: fixture.claudeFolder)])
        #expect(overview.label(of: Self.defaultAccount) == Self.name)
    }

    @Test("A default file with no account.id at all is named the same way")
    func absentIDIsNamed() async throws {
        let fixture = try ImportFixture()
        try AccountFixture.write(from: Self.file, accountID: nil, name: Self.name, as: Self.file, in: fixture.claudeFolder)

        _ = try await fixture.importer.importMetrics(of: .claudeBar, from: fixture.claudeFolder)

        #expect(try await fixture.archive.accountNames()[Self.defaultAccount] == Self.name)
    }

    @Test("Lines read before the name existed leave it unset until a line that carries it is read")
    func nameComesFromNewLines() async throws {
        let fixture = try ImportFixture()
        let target = try AccountFixture.write(from: Self.file, accountID: nil, as: Self.file, in: fixture.claudeFolder)
        _ = try await fixture.importer.importMetrics(of: .claudeBar, from: fixture.claudeFolder)
        #expect(try await fixture.archive.accountNames()[Self.defaultAccount] == nil)

        // Nothing new in the file: the lines already read are not read again for a name.
        _ = try await fixture.importer.importMetrics(of: .claudeBar, from: fixture.claudeFolder)
        #expect(try await fixture.archive.accountNames()[Self.defaultAccount] == nil)

        let handle = try FileHandle(forWritingTo: target)
        try handle.seekToEnd()
        try handle.write(contentsOf: try AccountFixture.data(from: Self.file, accountID: nil, name: Self.name))
        try handle.close()
        _ = try await fixture.importer.importMetrics(of: .claudeBar, from: fixture.claudeFolder)

        #expect(try await fixture.archive.accountNames()[Self.defaultAccount] == Self.name)
    }
}
