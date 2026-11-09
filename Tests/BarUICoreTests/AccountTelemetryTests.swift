import Foundation
import Testing
@testable import BarUICore

@Suite("Telemetry file names with Accounts")
struct AccountFileNameTests {
    @Test("A file name is the service, an optional account part, the kind and a day")
    func acceptsTheGrammar() {
        let accepted = [
            "claudebar-metrics-2026-10-12.jsonl": "default",
            "claudebar-logs-2026-10-12.jsonl": "default",
            "claudebar.acme-metrics-2026-10-12.jsonl": "acme",
            "claudebar.client-2-logs-2026-10-12.jsonl": "client-2",
            "claudebar.metrics-metrics-2026-10-12.jsonl": "metrics"
        ]
        for (name, account) in accepted {
            #expect(BarApp.claudeBar.telemetryFile(named: name)?.accountID == account, "\(name)")
        }
        #expect(BarApp.claudeBar.telemetryFile(named: "claudebar.acme-logs-2026-10-12.jsonl")?.isLogs == true)
        #expect(BarApp.claudeBar.telemetryFile(named: "claudebar-metrics-2026-10-12.jsonl")?.isLogs == false)
    }

    @Test("Names outside the grammar, another app's files and a spelled-out default are rejected")
    func rejectsTheRest() {
        let rejected = [
            "claudebar.default-metrics-2026-10-12.jsonl",
            "claudebar.-metrics-2026-10-12.jsonl",
            "claudebar.Client-metrics-2026-10-12.jsonl",
            "claudebar.a_b-metrics-2026-10-12.jsonl",
            "claudebar.a.b-metrics-2026-10-12.jsonl",
            "codexbar.acme-metrics-2026-10-12.jsonl",
            "claudebar.acme-traces-2026-10-12.jsonl",
            "claudebar.acme-metrics-2026-10-12.json",
            "claudebar.acme-metrics-20261012.jsonl",
            ".DS_Store"
        ]
        for name in rejected {
            #expect(BarApp.claudeBar.telemetryFile(named: name) == nil, "\(name)")
            #expect(!BarApp.claudeBar.isTelemetryFileName(name), "\(name)")
        }
    }

    @Test("Account ids follow the spec's grammar")
    func idGrammar() {
        for id in ["default", "acme", "client-2", "0"] {
            #expect(BarAppAccount.isValidID(id), "\(id)")
        }
        for id in ["", "Upper", "under_score", "dot.ted", "spa ce", "é"] {
            #expect(!BarAppAccount.isValidID(id), "\(id)")
        }
    }

    @Test("The pre-Accounts reader's pattern skips the dotted names")
    func olderReadersSkipThem() {
        let olderPattern = /^[a-z]+-(?:metrics|logs)-\d{4}-\d{2}-\d{2}\.jsonl$/
        #expect("claudebar-metrics-2026-10-12.jsonl".wholeMatch(of: olderPattern) != nil)
        #expect("claudebar.acme-metrics-2026-10-12.jsonl".wholeMatch(of: olderPattern) == nil)
    }
}

@Suite("Reading Accounts from Telemetry")
struct AccountParsingTests {
    @Test("The resource's account.id has to match the file's Account")
    func mismatchIsNonConforming() throws {
        let matching = try AccountFixture.data(from: "claudebar-metrics-2026-10-12.jsonl", accountID: "acme", name: "someone@acme.example")
        let mismatched = try AccountFixture.data(from: "claudebar-metrics-2026-10-12.jsonl", accountID: "other")
        let absent = try AccountFixture.data(from: "claudebar-metrics-2026-10-12.jsonl", accountID: nil)

        let read = MetricsParser.parse(matching, from: .claudeBar, account: "acme")
        #expect(read.droppedRecords == 0)
        #expect(!read.limitSamples.isEmpty)
        #expect(read.limitSamples.allSatisfy { $0.accountID == "acme" })
        #expect(read.tokenSamples.allSatisfy { $0.accountID == "acme" })
        #expect(read.accountNames.map(\.name) == ["someone@acme.example"])
        #expect(read.accountNames.map(\.accountID) == ["acme"])
        #expect(read.accountNames.first?.reportedAt ?? 0 > 0)

        let wrongID = MetricsParser.parse(mismatched, from: .claudeBar, account: "acme")
        #expect(wrongID.limitSamples.isEmpty)
        #expect(wrongID.droppedRecords > 0)

        // No account.id means default, so it can't sit in another Account's file.
        let inAnotherFile = MetricsParser.parse(absent, from: .claudeBar, account: "acme")
        #expect(inAnotherFile.limitSamples.isEmpty)
        #expect(inAnotherFile.droppedRecords > 0)
        let inDefaultFile = MetricsParser.parse(absent, from: .claudeBar)
        #expect(!inDefaultFile.limitSamples.isEmpty)
        #expect(inDefaultFile.limitSamples.allSatisfy { $0.accountID == BarAppAccount.defaultID })
    }

    @Test("A record naming an Account doesn't read as the default Account's")
    func namedAccountInDefaultFile() throws {
        let data = try AccountFixture.data(from: "claudebar-metrics-2026-10-12.jsonl", accountID: "acme")

        let read = MetricsParser.parse(data, from: .claudeBar)

        #expect(read.limitSamples.isEmpty)
        #expect(read.droppedRecords > 0)
    }

    @Test("Log events are held to the same rule")
    func logsMustMatchToo() throws {
        let matching = try AccountFixture.data(from: "claudebar-logs-2026-10-12.jsonl", accountID: "acme")
        let mismatched = try AccountFixture.data(from: "claudebar-logs-2026-10-12.jsonl", accountID: "other")

        let read = LogEventParser.parse(matching, from: .claudeBar, account: "acme")
        let rejected = LogEventParser.parse(mismatched, from: .claudeBar, account: "acme")

        #expect(!read.resets.isEmpty)
        #expect(read.resets.allSatisfy { $0.accountID == "acme" })
        #expect(read.limitEvents.allSatisfy { $0.accountID == "acme" })
        #expect(rejected.resets.isEmpty)
        #expect(rejected.droppedRecords > 0)
    }
}

@Suite("Importing several Accounts of one Bar App")
@MainActor
struct AccountImportTests {
    private static let now = Date(timeIntervalSince1970: 1_791_791_400)
    private static let acmeFile = "claudebar.acme-metrics-2026-10-12.jsonl"

    private static func status(_ state: TrackingState, folder: URL) -> BarAppStatus {
        BarAppStatus(state: state, settings: TrackingSettings(enabled: state == .tracking, intervalMinutes: 5, retentionDays: 90, folder: folder))
    }

    /// The default Account's file and a second Account's, side by side in one folder.
    private func twoAccounts() throws -> ImportFixture {
        let fixture = try ImportFixture()
        try fixture.copyFixture("claudebar-metrics-2026-10-12.jsonl", to: fixture.claudeFolder)
        try AccountFixture.write(
            from: "claudebar-metrics-2026-10-12.jsonl",
            accountID: "acme",
            name: "someone@acme.example",
            as: Self.acmeFile,
            in: fixture.claudeFolder
        )
        return fixture
    }

    @Test("Each Account's files import into their own series and keep their own offsets")
    func separateSeriesAndOffsets() async throws {
        let fixture = try twoAccounts()

        let first = try await fixture.importer.importMetrics(of: .claudeBar, from: fixture.claudeFolder)

        #expect(first.filesRead == 2)
        #expect(first.droppedRecords == 0)
        let limits = try await fixture.archive.currentLimits()
        #expect(limits.filter { $0.accountID == "acme" }.count == 3)
        #expect(limits.filter { $0.accountID == BarAppAccount.defaultID }.count == 3)
        let defaultOffset = try await fixture.archive.progress(of: .claudeBar, fileName: "claudebar-metrics-2026-10-12.jsonl")
        let acmeOffset = try await fixture.archive.progress(of: .claudeBar, fileName: Self.acmeFile)
        #expect(defaultOffset?.byteOffset ?? 0 > 0)
        #expect(acmeOffset?.byteOffset ?? 0 > 0)

        // Appending to one Account's file reads only that file's new lines.
        let file = fixture.claudeFolder.appendingPathComponent(Self.acmeFile)
        let handle = try FileHandle(forWritingTo: file)
        try handle.seekToEnd()
        try handle.write(contentsOf: try AccountFixture.data(from: "claudebar-metrics-2026-10-12.jsonl", accountID: "acme"))
        try handle.close()
        let second = try await fixture.importer.importMetrics(of: .claudeBar, from: fixture.claudeFolder)
        #expect(second.filesRead == 1)
        #expect(try await fixture.archive.progress(of: .claudeBar, fileName: "claudebar-metrics-2026-10-12.jsonl") == defaultOffset)
        #expect(try await fixture.archive.accounts() == [BarAppAccount(app: .claudeBar), BarAppAccount(app: .claudeBar, accountID: "acme")])
    }

    @Test("A file whose records name another Account is counted as skipped and imports nothing")
    func mismatchedFileIsSkipped() async throws {
        let fixture = try ImportFixture()
        try AccountFixture.write(from: "claudebar-metrics-2026-10-12.jsonl", accountID: "someoneelse", as: Self.acmeFile, in: fixture.claudeFolder)

        let summary = try await fixture.importer.importMetrics(of: .claudeBar, from: fixture.claudeFolder)

        #expect(summary.droppedRecords > 0)
        #expect(try await fixture.archive.currentLimits().isEmpty)
        #expect(try await fixture.archive.skippedRecords(of: .claudeBar).map(\.count) == [summary.droppedRecords])
    }

    @Test("The Overview shows a card per Account, named by what each Account called itself")
    func overviewHasBothAccounts() async throws {
        let fixture = try twoAccounts()
        let overview = LimitsOverview(archive: fixture.archive, now: { Self.now })
        await overview.show(.all, by: UUID())

        await overview.refresh(statuses: [.claudeBar: Self.status(.tracking, folder: fixture.claudeFolder)])

        // The five hour session is under a day, so it is left out of the cards.
        #expect(overview.cards(now: Self.now).map(\.id) == [
            "claudeBar/weekly_all", "claudeBar/weekly_scoped:claude-opus-4-1",
            "claudeBar.acme/weekly_all", "claudeBar.acme/weekly_scoped:claude-opus-4-1"
        ])
        #expect(overview.accounts.count == 2)
        let acme = BarAppAccount(app: .claudeBar, accountID: "acme")
        #expect(overview.label(of: acme) == "someone@acme.example")
        #expect(overview.label(of: BarAppAccount(app: .claudeBar)) == "Default")
        #expect(overview.seriesLabel(of: acme) == "ClaudeBar · someone@acme.example")
        #expect(overview.colorStep(of: BarAppAccount(app: .claudeBar)) == 0)
        #expect(overview.colorStep(of: acme) == 1)
        #expect(overview.tokenUsage(range: .all, now: Self.now).totalByAccount.keys.sorted() == [BarAppAccount(app: .claudeBar), acme])
        #expect(overview.problem == nil)
    }

    @Test("With one Account the series is named as the Bar App, as before")
    func singleAccountKeepsAppName() async throws {
        let fixture = try ImportFixture()
        try fixture.copyFixture("claudebar-metrics-2026-10-12.jsonl", to: fixture.claudeFolder)
        let overview = LimitsOverview(archive: fixture.archive)

        await overview.refresh(statuses: [.claudeBar: Self.status(.tracking, folder: fixture.claudeFolder)])

        #expect(overview.seriesLabel(of: BarAppAccount(app: .claudeBar)) == "ClaudeBar")
    }

    @Test("The Menu Bar Preview has rows for each Account, keyed so their rates don't mix")
    func previewHasBothAccounts() async throws {
        let fixture = try twoAccounts()
        let preview = MenuBarPreview(archive: fixture.archive, overview: LimitsOverview(archive: fixture.archive))

        await preview.refresh(statuses: [.claudeBar: Self.status(.tracking, folder: fixture.claudeFolder)], now: Self.now)

        let ids = preview.rows.map(\.id)
        #expect(ids.count == 4)
        #expect(Set(ids).count == 4)
        #expect(Set(preview.rows.map(\.account)) == [BarAppAccount(app: .claudeBar), BarAppAccount(app: .claudeBar, accountID: "acme")])
        let acmeWeekly = try #require(preview.rows.first { $0.id == "claudeBar.acme/weekly_all" })
        #expect(acmeWeekly.burnRateText == "+12%/h")
        #expect(preview.seriesLabel(of: acmeWeekly.account) == "ClaudeBar · someone@acme.example")
        #expect(preview.problem == nil)
    }

    @Test("Events from two Accounts keep distinct ids")
    func eventIDsAreDistinct() async throws {
        let fixture = try ImportFixture()
        try fixture.copyFixture("claudebar-logs-2026-10-12.jsonl", to: fixture.claudeFolder)
        try AccountFixture.write(from: "claudebar-logs-2026-10-12.jsonl", accountID: "acme", as: "claudebar.acme-logs-2026-10-12.jsonl", in: fixture.claudeFolder)
        let overview = LimitsOverview(archive: fixture.archive, now: { Self.now })
        await overview.show(.all, by: UUID())

        await overview.refresh(statuses: [.claudeBar: Self.status(.tracking, folder: fixture.claudeFolder)])

        let events = overview.events(range: .all, now: Self.now)
        #expect(!events.isEmpty)
        #expect(Set(events.map(\.id)).count == events.count)
        #expect(Set(events.map(\.accountID)).isSuperset(of: ["default", "acme"]))
    }
}

@Suite("Sidebar with Accounts")
struct AccountSidebarTests {
    private let acme = BarAppAccount(app: .claudeBar, accountID: "acme")
    private let main = BarAppAccount(app: .claudeBar)

    @Test("A Bar App with one Account keeps its single row")
    func oneAccount() {
        let items = SidebarSection.sections(accounts: [main, BarAppAccount(app: .codexBar)])[1].items

        #expect(items == [.barApp(.claudeBar), .barApp(.codexBar), .barApp(.grokBar)])
    }

    @Test("A Bar App whose only Account isn't the default keeps that Account, not the empty default page")
    func onlyNonDefaultAccount() {
        let items = SidebarSection.sections(accounts: [acme])[1].items

        #expect(items == [.account(acme), .barApp(.codexBar), .barApp(.grokBar)])
    }

    @Test("A Bar App with several Accounts is listed as its Accounts, the default first")
    func severalAccounts() {
        let sections = SidebarSection.sections(accounts: [acme, main, BarAppAccount(app: .codexBar)])

        #expect(sections[1].items == [.account(main), .account(acme), .barApp(.codexBar), .barApp(.grokBar)])
        #expect(sections.map(\.title) == [nil, "Bar Apps", "Archive"])
    }

    @Test("Account rows are titled by name, with ids that can't collide with the Bar App's")
    func titlesAndIDs() {
        let names = [acme: "someone@acme.example"]

        #expect(SidebarItem.account(acme).title(names: names) == "someone@acme.example")
        #expect(SidebarItem.account(acme).title == "acme")
        #expect(SidebarItem.account(main).title == "Default")
        let ids = [SidebarItem.barApp(.claudeBar), .account(main), .account(acme)].map(\.id)
        #expect(ids == ["barApp.claudeBar", "barApp.claudeBar", "barApp.claudeBar.acme"])
        #expect(SidebarItem.account(acme).app == .claudeBar)
    }
}
