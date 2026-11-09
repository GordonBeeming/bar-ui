import Foundation
import SQLite3
import Testing
@testable import BarUICore

/// `Fixtures/ArchiveV1.sqlite` was written by the Archive code from before
/// Accounts (`PRAGMA user_version` 1), so these tests upgrade a real version 1
/// file rather than one the current code made.
@Suite("Archive upgrade to Accounts")
struct ArchiveMigrationTests {
    private static let tables: [(name: String, rows: Int)] = [
        ("limits_v2", 3), ("limit_samples_v2", 6), ("token_samples_v2", 4), ("limit_resets_v2", 1),
        ("perk_points_v2", 2), ("perk_gone_events_v2", 2), ("imported_files_v2", 2), ("import_folders_v2", 1),
        ("limit_events_v2", 2), ("tracking_starts_v2", 1), ("perk_available_events_v2", 2)
    ]

    /// The names version 1 used. A migrated file has none of them, which is
    /// what leaves them free for a build from before Accounts.
    private static let versionOneNames = [
        "limits", "limit_samples", "token_samples", "limit_resets", "perk_points", "perk_gone_events",
        "imported_files", "import_folders", "limit_events", "tracking_starts", "perk_available_events"
    ]

    private func copyOfVersionOne(in folder: TemporaryFolder) throws -> URL {
        let url = folder.url.appendingPathComponent("Archive.sqlite")
        try FileManager.default.copyItem(at: Fixtures.url(named: "ArchiveV1.sqlite"), to: url)
        return url
    }

    /// Reads the file with its own connection, so what is checked is what is
    /// on disk and not what the Archive says about itself.
    private func scalar(_ sql: String, in url: URL) throws -> Int64 {
        var handle: OpaquePointer?
        guard sqlite3_open_v2(url.path, &handle, SQLITE_OPEN_READONLY, nil) == SQLITE_OK, let handle else {
            throw ProbeError.open
        }
        defer { sqlite3_close(handle) }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw ProbeError.prepare(String(cString: sqlite3_errmsg(handle)))
        }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else {
            throw ProbeError.noRow
        }
        return sqlite3_column_int64(statement, 0)
    }

    private enum ProbeError: Error {
        case open
        case prepare(String)
        case noRow
    }

    private func run(_ sql: String, in url: URL) throws {
        var handle: OpaquePointer?
        guard sqlite3_open_v2(url.path, &handle, SQLITE_OPEN_READWRITE, nil) == SQLITE_OK, let handle else {
            throw ProbeError.open
        }
        defer { sqlite3_close(handle) }
        guard sqlite3_exec(handle, sql, nil, nil, nil) == SQLITE_OK else {
            throw ProbeError.prepare(String(cString: sqlite3_errmsg(handle)))
        }
    }

    private static let accountUnion = """
        SELECT app, account FROM limits_v2 UNION SELECT app, account FROM limit_samples_v2
        UNION SELECT app, account FROM limit_resets_v2 UNION SELECT app, account FROM limit_events_v2
        UNION SELECT app, account FROM token_samples_v2 UNION SELECT app, account FROM perk_points_v2
        UNION SELECT app, account FROM perk_gone_events_v2 UNION SELECT app, account FROM perk_available_events_v2
        """

    /// The registry `accounts()` reads has to hold exactly the Accounts the
    /// tables do, which is what scanning them used to answer.
    private func expectRegistryMatchesTables(in url: URL, sourceLocation: SourceLocation = #_sourceLocation) throws {
        #expect(try scalar("SELECT COUNT(*) FROM (SELECT app, account FROM (\(Self.accountUnion)) EXCEPT SELECT app, account FROM accounts_v2)", in: url) == 0, "an Account is missing from the registry", sourceLocation: sourceLocation)
        #expect(try scalar("SELECT COUNT(*) FROM (SELECT app, account FROM accounts_v2 EXCEPT SELECT app, account FROM (\(Self.accountUnion)))", in: url) == 0, "the registry lists an Account no table has", sourceLocation: sourceLocation)
    }

    private func count(_ table: String, in url: URL) throws -> Int {
        Int(try scalar("SELECT COUNT(*) FROM \(table)", in: url))
    }

    @Test("A version 1 Archive keeps every row and moves to version 2")
    func keepsEveryRow() async throws {
        let folder = try TemporaryFolder()
        let url = try copyOfVersionOne(in: folder)
        #expect(try scalar("PRAGMA user_version", in: url) == 1)
        _ = try Archive(url: url)

        for (table, rows) in Self.tables {
            #expect(try count(table, in: url) == rows, "\(table)")
        }
        #expect(try scalar("PRAGMA user_version", in: url) == 2)
        #expect(try scalar("SELECT COUNT(*) FROM perk_gone_events_v2 WHERE account = 'default'", in: url) == 2)
        #expect(try scalar("SELECT COUNT(*) FROM accounts_v2", in: url) == 2)
        try expectRegistryMatchesTables(in: url)
    }

    @Test("Existing rows read as the default Account, and the Account is in every series key")
    func rowsBecomeDefault() async throws {
        let folder = try TemporaryFolder()
        let archive = try Archive(url: try copyOfVersionOne(in: folder))

        #expect(try await archive.accounts() == [BarAppAccount(app: .claudeBar), BarAppAccount(app: .codexBar)])
        let limits = try await archive.currentLimits()
        #expect(limits.map { "\($0.app.rawValue)/\($0.accountID)/\($0.limit.id)=\($0.utilization)" } == [
            "claudeBar/default/weekly_all=42.0",
            "claudeBar/default/weekly_scoped:Fable=3.0",
            "codexBar/default/codex:10080=24.0"
        ])
        let samples = try await archive.tokenSamples()
        #expect(samples.count == 4)
        #expect(samples.allSatisfy { $0.accountID == BarAppAccount.defaultID })
        #expect(try await archive.gonePerks().map(\.accountID) == ["default", "default"])
        #expect(try await archive.perkAvailableEvents().allSatisfy { $0.accountID == "default" })
        #expect(try await archive.limitLifecycleEvents().allSatisfy { $0.accountID == "default" })
        let history = try await archive.limitHistories(of: .claudeBar, since: nil)
        #expect(history.first { $0.limit.id == "weekly_all" }?.resets.count == 1)
        #expect(try await archive.availablePerks().count == 2)
    }

    @Test("Import positions and skipped counts survive, so already imported files aren't read twice")
    func keepsImportPositions() async throws {
        let folder = try TemporaryFolder()
        let archive = try Archive(url: try copyOfVersionOne(in: folder))

        let progress = try await archive.progress(of: .claudeBar, fileName: "claudebar-metrics-2026-10-12.jsonl")

        #expect(progress?.byteOffset == 4321)
        #expect(progress?.droppedRecords == 2)
        #expect(try await archive.skippedRecords(of: .claudeBar).map(\.count) == [2])
    }

    @Test("Opening an upgraded Archive again changes nothing")
    func idempotent() async throws {
        let folder = try TemporaryFolder()
        let url = try copyOfVersionOne(in: folder)
        let first = try Archive(url: url)
        let before = try await first.limitHistories(of: .claudeBar, since: nil)

        let second = try Archive(url: url)

        for (table, rows) in Self.tables {
            #expect(try count(table, in: url) == rows, "\(table)")
        }
        #expect(try scalar("PRAGMA user_version", in: url) == 2)
        #expect(try await second.limitHistories(of: .claudeBar, since: nil) == before)
    }

    @Test("A failure part way leaves the Archive exactly as version 1, with no version 2 table created")
    func failureRollsBack() throws {
        let folder = try TemporaryFolder()
        let url = try copyOfVersionOne(in: folder)
        // A view on a version 2 name makes creating that table fail, after the
        // tables before it in the same script were created.
        try run("CREATE VIEW token_samples_v2 AS SELECT 1 AS squatter", in: url)

        #expect(throws: ArchiveError.self) {
            _ = try Archive(url: url)
        }

        #expect(try scalar("PRAGMA user_version", in: url) == 1)
        #expect(try scalar("SELECT COUNT(*) FROM sqlite_master WHERE type = 'table' AND name LIKE '%_v2'", in: url) == 0)
        #expect(try scalar("SELECT COUNT(*) FROM pragma_table_info('limits') WHERE name = 'account'", in: url) == 0)
        for (table, rows) in Self.tables {
            let legacy = String(table.dropLast(3))
            #expect(try count(legacy, in: url) == rows, "\(legacy)")
        }
    }

    @Test("The version 1 names are left free, so a build from before Accounts finds nothing of its own to trip on")
    func versionOneNamesAreFree() throws {
        let folder = try TemporaryFolder()
        let url = try copyOfVersionOne(in: folder)
        _ = try Archive(url: url)

        for name in Self.versionOneNames {
            #expect(try scalar("SELECT COUNT(*) FROM sqlite_master WHERE name = '\(name)'", in: url) == 0, "\(name)")
        }
        // Its own indexes are free as well, since an index name is file-wide.
        #expect(try scalar("SELECT COUNT(*) FROM sqlite_master WHERE type = 'index' AND name IN ('token_samples_time', 'perk_gone_events_identity', 'perk_available_events_identity')", in: url) == 0)
    }

    @Test("What a build from before Accounts imported after the upgrade is folded in as the default Account, none lost or doubled")
    func foldsInWhatAnOlderBuildWrote() async throws {
        let folder = try TemporaryFolder()
        let url = try copyOfVersionOne(in: folder)
        _ = try Archive(url: url)

        // What an older build does on opening the file: sets the version back,
        // creates its own tables under the names it knows, and imports into them.
        try run(Archive.versionOneSchema + """

            PRAGMA user_version = 1;
            INSERT INTO limits VALUES ('claudeBar', 'weekly_all', 'Weekly (all models)', 10080, NULL, 3000000000);
            INSERT INTO limits VALUES ('grokBar', 'credits', 'Credits', NULL, NULL, 3000000000);
            INSERT INTO limit_samples VALUES ('claudeBar', 'weekly_all', 'bar.limit.utilization', 2000000000, 42);
            INSERT INTO limit_samples VALUES ('claudeBar', 'weekly_all', 'bar.limit.utilization', 3000000000, 44);
            INSERT INTO limit_samples VALUES ('grokBar', 'credits', 'bar.limit.utilization', 3000000000, 10);
            INSERT INTO token_samples VALUES ('claudeBar', 'claude-opus-4-1', 'input', 3000000000, 1, 400);
            INSERT INTO perk_gone_events VALUES ('claudeBar', 'guest_pass', '', 1200000000, 1, 'gp0', 800, 'used');
            INSERT INTO perk_gone_events VALUES ('claudeBar', 'guest_pass', '', 1300000000, 1, 'gp7', NULL, NULL);
            INSERT INTO limit_events VALUES ('claudeBar', 'weekly_all', 'disappeared', 3500000000, 'Weekly (all models)', 10080, NULL);
            INSERT INTO import_folders VALUES ('grokBar', '/grok/telemetry');
            INSERT INTO imported_files VALUES ('grokBar', 'grokbar-metrics-2026-10-13.jsonl', 77, 1);
            INSERT INTO tracking_starts VALUES ('claudeBar', 800000000, 5);
            """, in: url)
        #expect(try scalar("PRAGMA user_version", in: url) == 1)

        let archive = try Archive(url: url)

        #expect(try scalar("PRAGMA user_version", in: url) == 2)
        for name in Self.versionOneNames {
            #expect(try scalar("SELECT COUNT(*) FROM sqlite_master WHERE name = '\(name)'", in: url) == 0, "\(name)")
        }
        // Rows the older build wrote are added; the ones both sets held are not doubled.
        #expect(try count("limits_v2", in: url) == 4)
        #expect(try count("limit_samples_v2", in: url) == 8)
        #expect(try count("token_samples_v2", in: url) == 5)
        #expect(try count("perk_gone_events_v2", in: url) == 3)
        #expect(try count("limit_events_v2", in: url) == 3)
        #expect(try count("imported_files_v2", in: url) == 3)
        #expect(try count("tracking_starts_v2", in: url) == 1)
        #expect(try scalar("SELECT COUNT(*) FROM limit_samples_v2 WHERE account <> 'default'", in: url) == 0)
        // The one an Account's history can't tell from the original is the newest description.
        #expect(try scalar("SELECT described_at FROM limits_v2 WHERE app = 'claudeBar' AND limit_id = 'weekly_all'", in: url) == 3_000_000_000)
        #expect(try await archive.samples(of: .claudeBar, limitID: "weekly_all", metric: .utilization).map(\.value) == [40, 42, 44])
        #expect(try await archive.progress(of: .grokBar, fileName: "grokbar-metrics-2026-10-13.jsonl")?.byteOffset == 77)
        // The offsets the upgraded file already had win over the older build's.
        #expect(try await archive.progress(of: .claudeBar, fileName: "claudebar-metrics-2026-10-12.jsonl")?.byteOffset == 4321)

        // grokBar only exists in what the older build wrote, and it is listed.
        #expect(try await archive.accounts().contains(BarAppAccount(app: .grokBar)))
        try expectRegistryMatchesTables(in: url)

        // Opening again, with nothing new from an older build, changes nothing.
        let again = try Archive(url: url)
        _ = again
        #expect(try count("limit_samples_v2", in: url) == 8)
        #expect(try scalar("PRAGMA user_version", in: url) == 2)
    }

    @Test("A position an older build took in another folder starts that file again rather than skipping ahead")
    func foreignFolderPositionsRestart() async throws {
        let folder = try TemporaryFolder()
        let url = folder.url.appendingPathComponent("Archive.sqlite")
        _ = try Archive(url: url)
        try run("""
            INSERT INTO import_folders_v2 VALUES ('claudeBar', '/folder/b');
            INSERT INTO imported_files_v2 VALUES ('claudeBar', 'kept.jsonl', 500, 2);
            """, in: url)
        // What an older build left, taken in folder A where the same names are other files.
        try run(Archive.versionOneSchema + """

            PRAGMA user_version = 1;
            INSERT INTO import_folders VALUES ('claudeBar', '/folder/a');
            INSERT INTO imported_files VALUES ('claudeBar', 'kept.jsonl', 9999, 7);
            INSERT INTO imported_files VALUES ('claudeBar', 'same-name.jsonl', 9999, 3);
            INSERT INTO import_folders VALUES ('codexBar', '/codex/a');
            INSERT INTO imported_files VALUES ('codexBar', 'codexbar-metrics-2026-10-12.jsonl', 80, 0);
            """, in: url)

        let archive = try Archive(url: url)

        // The retained folder is the upgraded Archive's, and what it already read stands.
        let kept = try await archive.progress(of: .claudeBar, fileName: "kept.jsonl")
        #expect(kept?.byteOffset == 500)
        #expect(kept?.droppedRecords == 2)
        // A file only the older build knew starts from the beginning, with its skipped count kept as folder changes do.
        let restarted = try await archive.progress(of: .claudeBar, fileName: "same-name.jsonl")
        #expect(restarted?.byteOffset == 0)
        #expect(restarted?.droppedRecords == 3)
        // An app the upgraded Archive had no folder for takes the older build's, so its positions are good.
        #expect(try await archive.progress(of: .codexBar, fileName: "codexbar-metrics-2026-10-12.jsonl")?.byteOffset == 80)
        #expect(try scalar("SELECT COUNT(*) FROM import_folders_v2 WHERE app = 'codexBar' AND folder = '/codex/a'", in: url) == 1)
        #expect(try scalar("SELECT COUNT(*) FROM import_folders_v2 WHERE app = 'claudeBar' AND folder = '/folder/b'", in: url) == 1)
    }

    @Test("Reading again a file that was restarted adds no duplicate rows")
    func restartedFileIsReadWithoutDuplicates() async throws {
        let fixture = try ImportFixture()
        let name = "claudebar-metrics-2026-10-12.jsonl"
        try fixture.copyFixture(name, to: fixture.claudeFolder)
        _ = try await fixture.importer.importMetrics(of: .claudeBar, from: fixture.claudeFolder)
        let samples = try scalar("SELECT COUNT(*) FROM limit_samples_v2", in: fixture.archiveURL)
        let tokens = try scalar("SELECT COUNT(*) FROM token_samples_v2", in: fixture.archiveURL)
        #expect(samples > 0)
        // The file's position is gone from the upgraded Archive; an older build
        // took one for a file of that name in a different folder, far past this one's end.
        try run("""
            DELETE FROM imported_files_v2;
            """ + Archive.versionOneSchema + """

            PRAGMA user_version = 1;
            INSERT INTO import_folders VALUES ('claudeBar', '/some/other/folder');
            INSERT INTO imported_files VALUES ('claudeBar', '\(name)', 1000000, 0);
            """, in: fixture.archiveURL)
        let reopened = try Archive(url: fixture.archiveURL)

        #expect(try await reopened.progress(of: .claudeBar, fileName: name)?.byteOffset == 0)
        let summary = try await TelemetryImporter(archive: reopened).importMetrics(of: .claudeBar, from: fixture.claudeFolder)

        #expect(summary.filesRead == 1)
        #expect(try scalar("SELECT COUNT(*) FROM limit_samples_v2", in: fixture.archiveURL) == samples)
        #expect(try scalar("SELECT COUNT(*) FROM token_samples_v2", in: fixture.archiveURL) == tokens)
    }

    @Test("For one file in one folder the position further along wins whole, never summed or mixed")
    func furtherAlongPositionWinsWhole() async throws {
        let folder = try TemporaryFolder()
        let url = folder.url.appendingPathComponent("Archive.sqlite")
        _ = try Archive(url: url)
        try run("""
            INSERT INTO import_folders_v2 VALUES ('claudeBar', '/folder/a');
            INSERT INTO imported_files_v2 VALUES ('claudeBar', 'behind.jsonl', 100, 1);
            INSERT INTO imported_files_v2 VALUES ('claudeBar', 'ahead.jsonl', 300, 0);
            INSERT INTO imported_files_v2 VALUES ('claudeBar', 'tie.jsonl', 200, 5);
            """, in: url)
        try run(Archive.versionOneSchema + """

            PRAGMA user_version = 1;
            INSERT INTO import_folders VALUES ('claudeBar', '/folder/a');
            INSERT INTO imported_files VALUES ('claudeBar', 'behind.jsonl', 300, 4);
            INSERT INTO imported_files VALUES ('claudeBar', 'ahead.jsonl', 50, 9);
            INSERT INTO imported_files VALUES ('claudeBar', 'tie.jsonl', 200, 8);
            """, in: url)

        let archive = try Archive(url: url)

        // Further along: its skipped count comes with it, not added to the other's.
        let behind = try await archive.progress(of: .claudeBar, fileName: "behind.jsonl")
        #expect(behind?.byteOffset == 300)
        #expect(behind?.droppedRecords == 4)
        // The older build behind: the upgraded Archive's row stands, with its own count.
        let ahead = try await archive.progress(of: .claudeBar, fileName: "ahead.jsonl")
        #expect(ahead?.byteOffset == 300)
        #expect(ahead?.droppedRecords == 0)
        let tie = try await archive.progress(of: .claudeBar, fileName: "tie.jsonl")
        #expect(tie?.byteOffset == 200)
        #expect(tie?.droppedRecords == 5)
    }

    @Test("An Account with only Perk telemetry still counts as an Account")
    func perkOnlyAccountAppears() async throws {
        let folder = try TemporaryFolder()
        let archive = try Archive(url: folder.url.appendingPathComponent("Archive.sqlite"))
        let progress = ImportProgress(app: .claudeBar, fileName: "claudebar.work-metrics-2026-10-12.jsonl", byteOffset: 1, droppedRecords: 0)

        try await archive.record(TelemetryRecords(
            perkSamples: [PerkSample(app: .claudeBar, accountID: "work", kind: .guestPass, currency: nil, timeUnixNano: 1, value: 1, expiresAt: nil)]
        ), progress: progress)
        try await archive.record(TelemetryRecords(
            perkGoneEvents: [PerkGoneEvent(app: .codexBar, accountID: "side", kind: .resetCredit, currency: nil, quantity: 1, perkID: nil, expiresAt: nil, reportedReason: nil, timeUnixNano: 2)]
        ), progress: ImportProgress(app: .codexBar, fileName: "codexbar.side-logs-2026-10-12.jsonl", byteOffset: 1, droppedRecords: 0))

        #expect(try await archive.accounts() == [
            BarAppAccount(app: .claudeBar, accountID: "work"),
            BarAppAccount(app: .codexBar, accountID: "side")
        ])
        try expectRegistryMatchesTables(in: folder.url.appendingPathComponent("Archive.sqlite"))
    }

    @Test("A new Archive is created at version 2 with Accounts in its keys")
    func freshArchive() async throws {
        let folder = try TemporaryFolder()
        let url = folder.url.appendingPathComponent("Archive.sqlite")
        _ = try Archive(url: url)

        #expect(try scalar("PRAGMA user_version", in: url) == 2)
        #expect(try scalar("SELECT COUNT(*) FROM pragma_table_info('limit_samples_v2') WHERE name = 'account'", in: url) == 1)
        #expect(try scalar("SELECT COUNT(*) FROM pragma_table_info('limits_v2') WHERE name = 'account'", in: url) == 1)
    }

    @Test("A second Account's samples sit beside the first's without touching them")
    func accountsAreSeparateSeries() async throws {
        let folder = try TemporaryFolder()
        let url = try copyOfVersionOne(in: folder)
        let archive = try Archive(url: url)
        let weekly = LimitDescriptor(id: "weekly_all", name: "Weekly (all models)", windowDurationMinutes: 10080, modelID: nil)
        let progress = ImportProgress(app: .claudeBar, fileName: "claudebar.acme-metrics-2026-10-12.jsonl", byteOffset: 1, droppedRecords: 0)

        try await archive.record(TelemetryRecords(
            limitSamples: [
                LimitSample(app: .claudeBar, accountID: "acme", limit: weekly, metric: .utilization, timeUnixNano: 2_000_000_000, value: 77),
                LimitSample(app: .claudeBar, accountID: "acme", limit: weekly, metric: .resetsAt, timeUnixNano: 2_000_000_000, value: 9_000)
            ],
            accountNames: [AccountName(app: .claudeBar, accountID: "acme", name: "someone@acme.example")]
        ), progress: progress)

        let limits = try await archive.currentLimits().filter { $0.app == .claudeBar && $0.limit.id == "weekly_all" }
        #expect(limits.map { "\($0.accountID)=\($0.utilization)" } == ["default=42.0", "acme=77.0"])
        #expect(try await archive.samples(of: .claudeBar, limitID: "weekly_all", metric: .utilization).map(\.value) == [40, 42])
        #expect(try await archive.samples(of: .claudeBar, account: "acme", limitID: "weekly_all", metric: .utilization).map(\.value) == [77])
        #expect(try await archive.accountNames() == [BarAppAccount(app: .claudeBar, accountID: "acme"): "someone@acme.example"])
        #expect(try await archive.accounts().contains(BarAppAccount(app: .claudeBar, accountID: "acme")))
        try expectRegistryMatchesTables(in: url)
    }

    @Test("Two Accounts' token counters are not read as one counter that restarts")
    func tokenCountersArePerAccount() throws {
        let nano: Int64 = 1_791_791_400_000_000_000
        func sample(_ account: String, _ count: Int64, _ offset: Int64) -> TokenSample {
            TokenSample(app: .claudeBar, accountID: account, model: "m", tokenType: .input, startTimeUnixNano: 1, timeUnixNano: nano + offset, count: count)
        }
        let usage = TokenUsage(
            samples: [sample("default", 100, 0), sample("acme", 5_000, 1), sample("default", 130, 2), sample("acme", 5_020, 3)],
            range: .all,
            now: Date(unixNano: nano + 10),
            calendar: .current
        )

        #expect(usage.totalByAccount == [BarAppAccount(app: .claudeBar): 130, BarAppAccount(app: .claudeBar, accountID: "acme"): 5_020])
        #expect(usage.totalByApp == [.claudeBar: 5_150])
    }
}
