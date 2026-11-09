import Foundation
import os
import SQLite3

/// The Dashboard's own permanent record of every Telemetry sample it has
/// imported. It is the store of record, not a cache of the Bar Apps' files:
/// those get deleted by retention, so nothing here is ever rebuilt from them.
public actor Archive {
    /// The `user_version` an Archive is upgraded to when it is opened. Each
    /// version's steps run once, in one transaction, and never again.
    private static let schemaVersion: Int32 = 2
    private static let busyTimeoutMilliseconds: Int32 = 10_000

    private let connection: Connection
    private var database: OpaquePointer { connection.handle }
    /// Rollovers detected in each Limit's samples so far, by `app/limit`, so a
    /// read only scans polls newer than the last one it saw.
    private static let logger = Logger(subsystem: "com.gordonbeeming.BarUI", category: "Archive")
    private var reportedUnknownApps: Set<String> = []
    var rolloverCache: [String: DetectedRollovers] = [:]

    public init(url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        var handle: OpaquePointer?
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
        let result = sqlite3_open_v2(url.path, &handle, flags, nil)
        guard result == SQLITE_OK, let handle else {
            let message = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "out of memory"
            sqlite3_close(handle)
            throw ArchiveError(operation: "open \(url.path)", message: message, code: result)
        }
        // Owned from here on, so every later throw closes it on the way out.
        connection = Connection(handle: handle)
        // Another window's or another Bar UI process's connection can hold
        // the write lock for an import; wait it out rather than fail the pass.
        let timeout = sqlite3_busy_timeout(handle, Self.busyTimeoutMilliseconds)
        guard timeout == SQLITE_OK else {
            throw ArchiveError(operation: "set its busy timeout", message: String(cString: sqlite3_errmsg(handle)), code: timeout)
        }
        try Self.migrate(handle)
    }

    // MARK: - Schema and SQLite

    private static func migrate(_ database: OpaquePointer) throws {
        try execute("PRAGMA journal_mode = WAL", on: database, operation: "turn on write-ahead logging")
        // The state is read from which tables exist, never from
        // `user_version` alone: a build from before Accounts opening this file
        // sets it back to 1 and recreates the tables it knows.
        guard try needsUpgrade(database) else {
            return
        }
        // IMMEDIATE so two Bar UI processes opening one Archive can't both
        // run the steps; the one that waits finds nothing left to do.
        try execute("BEGIN IMMEDIATE", on: database, operation: "start upgrading its schema")
        do {
            if try needsUpgrade(database) {
                try execute(versionTwoSchema, on: database, operation: "create its tables")
                try foldInVersionOneTables(in: database)
                try execute("PRAGMA user_version = \(schemaVersion)", on: database, operation: "record its version")
            }
            try execute("COMMIT", on: database, operation: "finish upgrading its schema")
        } catch {
            do {
                try execute("ROLLBACK", on: database, operation: "roll back upgrading its schema")
            } catch let rollbackError {
                throw ArchiveError(operation: "upgrade its schema", message: "\(error.localizedDescription); then \(rollbackError.localizedDescription)", code: SQLITE_ERROR)
            }
            throw error
        }
    }

    private static func tableNames(in database: OpaquePointer) throws -> Set<String> {
        let statement = try Statement(sql: "SELECT name FROM sqlite_master WHERE type = 'table'", database: database)
        var names: Set<String> = []
        while try statement.step() {
            if let name = statement.text(at: 0) {
                names.insert(name)
            }
        }
        return names
    }

    /// True while a version 2 table is missing, or a version 1 table exists
    /// that holds rows still to be folded in.
    private static func needsUpgrade(_ database: OpaquePointer) throws -> Bool {
        let existing = try tableNames(in: database)
        return !Set(foldedTables.map(\.name)).isSubset(of: existing)
            || !existing.isDisjoint(with: foldedTables.map(\.legacyName) + [legacyPerkSamples])
    }

    /// The schema as version 1 left it, under the names it used. An Archive
    /// from then is upgraded by running this, then the steps after it, so it
    /// stays as written. A test builds its version 1 fixture from it.
    static let versionOneSchema = """
            CREATE TABLE IF NOT EXISTS limits (
                app TEXT NOT NULL,
                limit_id TEXT NOT NULL,
                name TEXT NOT NULL,
                window_minutes INTEGER,
                model_id TEXT,
                described_at INTEGER NOT NULL,
                PRIMARY KEY (app, limit_id)
            ) WITHOUT ROWID;
            CREATE TABLE IF NOT EXISTS limit_samples (
                app TEXT NOT NULL,
                limit_id TEXT NOT NULL,
                metric TEXT NOT NULL,
                time_unix_nano INTEGER NOT NULL,
                value REAL NOT NULL,
                PRIMARY KEY (app, limit_id, metric, time_unix_nano)
            ) WITHOUT ROWID;
            CREATE TABLE IF NOT EXISTS token_samples (
                app TEXT NOT NULL,
                model TEXT NOT NULL,
                token_type TEXT NOT NULL,
                time_unix_nano INTEGER NOT NULL,
                start_time_unix_nano INTEGER NOT NULL,
                count INTEGER NOT NULL,
                PRIMARY KEY (app, model, token_type, time_unix_nano)
            ) WITHOUT ROWID;
            CREATE INDEX IF NOT EXISTS token_samples_time ON token_samples (time_unix_nano);
            CREATE TABLE IF NOT EXISTS limit_resets (
                app TEXT NOT NULL,
                limit_id TEXT NOT NULL,
                time_unix_nano INTEGER NOT NULL,
                utilization_last REAL NOT NULL,
                next_resets_at REAL,
                PRIMARY KEY (app, limit_id, time_unix_nano)
            ) WITHOUT ROWID;
            CREATE TABLE IF NOT EXISTS perk_points (
                app TEXT NOT NULL,
                kind TEXT NOT NULL,
                currency TEXT NOT NULL,
                time_unix_nano INTEGER NOT NULL,
                perk_id TEXT NOT NULL,
                value REAL NOT NULL,
                expires_at INTEGER,
                PRIMARY KEY (app, kind, currency, time_unix_nano, perk_id)
            ) WITHOUT ROWID;
            CREATE TABLE IF NOT EXISTS perk_gone_events (
                app TEXT NOT NULL,
                kind TEXT NOT NULL,
                currency TEXT NOT NULL,
                time_unix_nano INTEGER NOT NULL,
                quantity REAL,
                perk_id TEXT NOT NULL,
                expires_at INTEGER,
                reason TEXT
            );
            CREATE UNIQUE INDEX IF NOT EXISTS perk_gone_events_identity ON perk_gone_events (
                app, kind, currency, time_unix_nano, perk_id,
                IFNULL(quantity, -1), IFNULL(expires_at, -1), IFNULL(reason, ''));
            CREATE TABLE IF NOT EXISTS imported_files (
                app TEXT NOT NULL,
                file_name TEXT NOT NULL,
                byte_offset INTEGER NOT NULL,
                dropped_records INTEGER NOT NULL,
                PRIMARY KEY (app, file_name)
            ) WITHOUT ROWID;
            CREATE TABLE IF NOT EXISTS import_folders (
                app TEXT NOT NULL PRIMARY KEY,
                folder TEXT NOT NULL
            ) WITHOUT ROWID;
            CREATE TABLE IF NOT EXISTS limit_events (
                app TEXT NOT NULL,
                limit_id TEXT NOT NULL,
                kind TEXT NOT NULL,
                time_unix_nano INTEGER NOT NULL,
                name TEXT,
                window_minutes INTEGER,
                model_id TEXT,
                PRIMARY KEY (app, limit_id, kind, time_unix_nano)
            ) WITHOUT ROWID;
            CREATE TABLE IF NOT EXISTS tracking_starts (
                app TEXT NOT NULL,
                time_unix_nano INTEGER NOT NULL,
                interval_minutes INTEGER NOT NULL,
                PRIMARY KEY (app, time_unix_nano, interval_minutes)
            ) WITHOUT ROWID;
            CREATE TABLE IF NOT EXISTS perk_available_events (
                app TEXT NOT NULL,
                kind TEXT NOT NULL,
                currency TEXT NOT NULL,
                time_unix_nano INTEGER NOT NULL,
                quantity REAL,
                perk_id TEXT NOT NULL,
                expires_at INTEGER
            );
            CREATE UNIQUE INDEX IF NOT EXISTS perk_available_events_identity ON perk_available_events (
                app, kind, currency, time_unix_nano, perk_id, IFNULL(quantity, -1), IFNULL(expires_at, -1));
        """

    /// Version 2 keeps everything under new names, with an Account in the key
    /// of everything a Bar App's samples belong to. The old names are left
    /// free on purpose: a build from before Accounts that opens the file
    /// creates its own empty tables there and carries on without ever
    /// touching, or being confused by, these. Index names are new for the same
    /// reason, since an index name is taken file-wide.
    static let versionTwoSchema = """
            CREATE TABLE IF NOT EXISTS limits_v2 (
                app TEXT NOT NULL,
                account TEXT NOT NULL,
                limit_id TEXT NOT NULL,
                name TEXT NOT NULL,
                window_minutes INTEGER,
                model_id TEXT,
                described_at INTEGER NOT NULL,
                PRIMARY KEY (app, account, limit_id)
            ) WITHOUT ROWID;
            CREATE TABLE IF NOT EXISTS limit_samples_v2 (
                app TEXT NOT NULL,
                account TEXT NOT NULL,
                limit_id TEXT NOT NULL,
                metric TEXT NOT NULL,
                time_unix_nano INTEGER NOT NULL,
                value REAL NOT NULL,
                PRIMARY KEY (app, account, limit_id, metric, time_unix_nano)
            ) WITHOUT ROWID;
            CREATE TABLE IF NOT EXISTS token_samples_v2 (
                app TEXT NOT NULL,
                account TEXT NOT NULL,
                model TEXT NOT NULL,
                token_type TEXT NOT NULL,
                time_unix_nano INTEGER NOT NULL,
                start_time_unix_nano INTEGER NOT NULL,
                count INTEGER NOT NULL,
                PRIMARY KEY (app, account, model, token_type, time_unix_nano)
            ) WITHOUT ROWID;
            CREATE INDEX IF NOT EXISTS token_samples_v2_time ON token_samples_v2 (time_unix_nano);
            CREATE TABLE IF NOT EXISTS limit_resets_v2 (
                app TEXT NOT NULL,
                account TEXT NOT NULL,
                limit_id TEXT NOT NULL,
                time_unix_nano INTEGER NOT NULL,
                utilization_last REAL NOT NULL,
                next_resets_at REAL,
                PRIMARY KEY (app, account, limit_id, time_unix_nano)
            ) WITHOUT ROWID;
            CREATE TABLE IF NOT EXISTS perk_points_v2 (
                app TEXT NOT NULL,
                account TEXT NOT NULL,
                kind TEXT NOT NULL,
                currency TEXT NOT NULL,
                time_unix_nano INTEGER NOT NULL,
                perk_id TEXT NOT NULL,
                value REAL NOT NULL,
                expires_at INTEGER,
                PRIMARY KEY (app, account, kind, currency, time_unix_nano, perk_id)
            ) WITHOUT ROWID;
            CREATE TABLE IF NOT EXISTS perk_gone_events_v2 (
                app TEXT NOT NULL,
                account TEXT NOT NULL,
                kind TEXT NOT NULL,
                currency TEXT NOT NULL,
                time_unix_nano INTEGER NOT NULL,
                quantity REAL,
                perk_id TEXT NOT NULL,
                expires_at INTEGER,
                reason TEXT
            );
            CREATE UNIQUE INDEX IF NOT EXISTS perk_gone_events_v2_identity ON perk_gone_events_v2 (
                app, account, kind, currency, time_unix_nano, perk_id,
                IFNULL(quantity, -1), IFNULL(expires_at, -1), IFNULL(reason, ''));
            CREATE TABLE IF NOT EXISTS imported_files_v2 (
                app TEXT NOT NULL,
                file_name TEXT NOT NULL,
                byte_offset INTEGER NOT NULL,
                dropped_records INTEGER NOT NULL,
                PRIMARY KEY (app, file_name)
            ) WITHOUT ROWID;
            CREATE TABLE IF NOT EXISTS import_folders_v2 (
                app TEXT NOT NULL PRIMARY KEY,
                folder TEXT NOT NULL
            ) WITHOUT ROWID;
            CREATE TABLE IF NOT EXISTS limit_events_v2 (
                app TEXT NOT NULL,
                account TEXT NOT NULL,
                limit_id TEXT NOT NULL,
                kind TEXT NOT NULL,
                time_unix_nano INTEGER NOT NULL,
                name TEXT,
                window_minutes INTEGER,
                model_id TEXT,
                PRIMARY KEY (app, account, limit_id, kind, time_unix_nano)
            ) WITHOUT ROWID;
            CREATE TABLE IF NOT EXISTS tracking_starts_v2 (
                app TEXT NOT NULL,
                time_unix_nano INTEGER NOT NULL,
                interval_minutes INTEGER NOT NULL,
                PRIMARY KEY (app, time_unix_nano, interval_minutes)
            ) WITHOUT ROWID;
            CREATE TABLE IF NOT EXISTS perk_available_events_v2 (
                app TEXT NOT NULL,
                account TEXT NOT NULL,
                kind TEXT NOT NULL,
                currency TEXT NOT NULL,
                time_unix_nano INTEGER NOT NULL,
                quantity REAL,
                perk_id TEXT NOT NULL,
                expires_at INTEGER
            );
            CREATE UNIQUE INDEX IF NOT EXISTS perk_available_events_v2_identity ON perk_available_events_v2 (
                app, account, kind, currency, time_unix_nano, perk_id, IFNULL(quantity, -1), IFNULL(expires_at, -1));
            CREATE TABLE IF NOT EXISTS account_names (
                app TEXT NOT NULL,
                account TEXT NOT NULL,
                name TEXT NOT NULL,
                updated_at INTEGER NOT NULL,
                PRIMARY KEY (app, account)
            ) WITHOUT ROWID;
        """

    /// A version 2 table and the version 1 table it replaces.
    private struct FoldedTable {
        let name: String
        let legacyName: String
        /// Every column but `app` and, when the table has one, `account`, in the
        /// order they are copied.
        let columns: [String]
        let hasAccount: Bool
        var keepsNewest = false
        /// Tables without a key are read back in insertion order, so the copy
        /// keeps it.
        var ordersByRowID = false
        /// Read positions are folded together with their folder, not row by row.
        var foldsWithFolders = false
    }

    private static let foldedTables: [FoldedTable] = [
        FoldedTable(name: "limits_v2", legacyName: "limits", columns: ["limit_id", "name", "window_minutes", "model_id", "described_at"], hasAccount: true, keepsNewest: true),
        FoldedTable(name: "limit_samples_v2", legacyName: "limit_samples", columns: ["limit_id", "metric", "time_unix_nano", "value"], hasAccount: true),
        FoldedTable(name: "token_samples_v2", legacyName: "token_samples", columns: ["model", "token_type", "time_unix_nano", "start_time_unix_nano", "count"], hasAccount: true),
        FoldedTable(name: "limit_resets_v2", legacyName: "limit_resets", columns: ["limit_id", "time_unix_nano", "utilization_last", "next_resets_at"], hasAccount: true),
        FoldedTable(name: "perk_points_v2", legacyName: "perk_points", columns: ["kind", "currency", "time_unix_nano", "perk_id", "value", "expires_at"], hasAccount: true),
        FoldedTable(name: "perk_gone_events_v2", legacyName: "perk_gone_events", columns: ["kind", "currency", "time_unix_nano", "quantity", "perk_id", "expires_at", "reason"], hasAccount: true, ordersByRowID: true),
        FoldedTable(name: "limit_events_v2", legacyName: "limit_events", columns: ["limit_id", "kind", "time_unix_nano", "name", "window_minutes", "model_id"], hasAccount: true),
        FoldedTable(name: "perk_available_events_v2", legacyName: "perk_available_events", columns: ["kind", "currency", "time_unix_nano", "quantity", "perk_id", "expires_at"], hasAccount: true, ordersByRowID: true),
        FoldedTable(name: "tracking_starts_v2", legacyName: "tracking_starts", columns: ["time_unix_nano", "interval_minutes"], hasAccount: false),
        FoldedTable(name: "imported_files_v2", legacyName: "imported_files", columns: ["file_name", "byte_offset", "dropped_records"], hasAccount: false, foldsWithFolders: true),
        FoldedTable(name: "import_folders_v2", legacyName: "import_folders", columns: ["folder"], hasAccount: false, foldsWithFolders: true)
    ]

    private static let legacyPerkSamples = "perk_samples"

    /// Moves every row of the version 1 tables into the version 2 ones as the
    /// `default` Account, then drops them. It runs on every open that finds
    /// version 1 tables, not just the first: a build from before Accounts
    /// that opened the file in between has recreated them and imported into
    /// them, and that history is as permanent as any other. `OR IGNORE`
    /// keeps what is already there, so a row both sets hold lands once.
    private static func foldInVersionOneTables(in database: OpaquePointer) throws {
        let existing = try tableNames(in: database)
        guard !existing.isDisjoint(with: foldedTables.map(\.legacyName) + [legacyPerkSamples]) else {
            return
        }
        // The older steps are written for the version 1 tables, so they run
        // against those first, with any missing ones created empty.
        try execute(versionOneSchema, on: database, operation: "create its version 1 tables")
        try carryOverPerkSamples(into: database)
        try addLimitEventDescriptorColumns(to: database)
        try foldReadPositions(in: database)
        for table in foldedTables where !table.foldsWithFolders {
            let list = table.columns.joined(separator: ", ")
            let account = table.hasAccount ? ", account" : ""
            let selectedAccount = table.hasAccount ? ", '\(BarAppAccount.defaultID)'" : ""
            let order = table.ordersByRowID ? " ORDER BY rowid" : ""
            let conflict = table.keepsNewest ? """

                ON CONFLICT (app, account, limit_id) DO UPDATE SET
                    name = excluded.name,
                    window_minutes = excluded.window_minutes,
                    model_id = excluded.model_id,
                    described_at = excluded.described_at
                WHERE excluded.described_at >= \(table.name).described_at
                """ : ""
            try execute("""
                INSERT \(table.keepsNewest ? "" : "OR IGNORE ")INTO \(table.name) (app\(account), \(list))
                SELECT app\(selectedAccount), \(list) FROM \(table.legacyName) WHERE true\(order)\(conflict);
                DROP TABLE \(table.legacyName);
                """, on: database, operation: "fold \(table.legacyName) into \(table.name)")
        }
        try execute("DROP TABLE IF EXISTS \(legacyPerkSamples)", on: database, operation: "drop its old Perk readings")
    }

    /// A read position belongs to the file in the folder it was taken in, so
    /// the folder and the positions are reconciled together.
    ///
    /// - The folder the upgraded Archive already imports from stays. An app it
    ///   has no folder for takes the older build's.
    /// - A position from the older build only carries over when that build's
    ///   folder for the app is the one kept. From another folder, the same
    ///   file name may be a different file, so the file starts again at 0:
    ///   records already archived are ignored on the re-read, and nothing is
    ///   skipped over.
    /// - When both hold a position for one file, the one further along wins
    ///   whole, offset and skipped count together. Both are cumulative over
    ///   one append-only file, so adding them or taking each field's largest
    ///   would count the same stretch twice on the next read.
    private static func foldReadPositions(in database: OpaquePointer) throws {
        try execute("""
            INSERT OR IGNORE INTO import_folders_v2 (app, folder) SELECT app, folder FROM import_folders;
            INSERT INTO imported_files_v2 (app, file_name, byte_offset, dropped_records)
            SELECT f.app, f.file_name,
                CASE WHEN older.folder = kept.folder THEN f.byte_offset ELSE 0 END,
                f.dropped_records
            FROM imported_files f
            LEFT JOIN import_folders older ON older.app = f.app
            LEFT JOIN import_folders_v2 kept ON kept.app = f.app
            WHERE true
            ON CONFLICT (app, file_name) DO UPDATE SET
                byte_offset = excluded.byte_offset,
                dropped_records = excluded.dropped_records
            WHERE excluded.byte_offset > imported_files_v2.byte_offset;
            DROP TABLE imported_files;
            DROP TABLE import_folders;
            """, on: database, operation: "fold its read positions in")
    }

    /// An Archive written before Perks were kept per `perk.id` has its
    /// readings in `perk_samples`, whose key has no room for an id. They carry
    /// over as id-less points, and `OR IGNORE` makes every later open a no-op.
    private static func carryOverPerkSamples(into database: OpaquePointer) throws {
        let lookup = try Statement(
            sql: "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = 'perk_samples'",
            database: database
        )
        guard try lookup.step() else {
            return
        }
        try execute("""
            INSERT OR IGNORE INTO perk_points (app, kind, currency, time_unix_nano, perk_id, value, expires_at)
            SELECT app, kind, currency, time_unix_nano, '', value, expires_at FROM perk_samples
            """, on: database, operation: "carry its Perk readings over")
    }

    /// A Limit's name and Window can change while its ID stays, so each
    /// lifecycle event keeps the descriptor it was recorded with. An Archive
    /// written before that has the columns added, and its events take the
    /// Limit's descriptor as it stands now: the nearest record there is.
    /// Only rows still without a name are filled.
    private static func addLimitEventDescriptorColumns(to database: OpaquePointer) throws {
        let columns = try Statement(sql: "PRAGMA table_info(limit_events)", database: database)
        var existing: Set<String> = []
        while try columns.step() {
            if let name = columns.text(at: 1) {
                existing.insert(name)
            }
        }
        let wanted: [(name: String, type: String)] = [("name", "TEXT"), ("window_minutes", "INTEGER"), ("model_id", "TEXT")]
        for column in wanted where !existing.contains(column.name) {
            try execute(
                "ALTER TABLE limit_events ADD COLUMN \(column.name) \(column.type)",
                on: database,
                operation: "add \(column.name) to its Limit events"
            )
        }
        try execute("""
            UPDATE limit_events SET
                name = (SELECT l.name FROM limits l WHERE l.app = limit_events.app AND l.limit_id = limit_events.limit_id),
                window_minutes = (SELECT l.window_minutes FROM limits l WHERE l.app = limit_events.app AND l.limit_id = limit_events.limit_id),
                model_id = (SELECT l.model_id FROM limits l WHERE l.app = limit_events.app AND l.limit_id = limit_events.limit_id)
            WHERE name IS NULL
            """, on: database, operation: "fill in its older Limit events' descriptors")
    }

    private static func execute(_ sql: String, on database: OpaquePointer, operation: String) throws {
        var errorMessage: UnsafeMutablePointer<CChar>?
        let result = sqlite3_exec(database, sql, nil, nil, &errorMessage)
        guard result == SQLITE_OK else {
            let message = errorMessage.map { String(cString: $0) } ?? String(cString: sqlite3_errmsg(database))
            sqlite3_free(errorMessage)
            throw ArchiveError(operation: operation, message: message, code: result)
        }
    }

    func execute(_ sql: String, operation: String) throws {
        try Self.execute(sql, on: database, operation: operation)
    }

    /// A Bar App this build doesn't know (written by a newer Bar UI) can't be
    /// shown, but its rows stay in the Archive untouched. Said once per name
    /// and table so the log shows it without a line for every row.
    func knownApp(_ rawValue: String?, in table: String) -> BarApp? {
        guard let rawValue else {
            return nil
        }
        if let app = BarApp(rawValue: rawValue) {
            return app
        }
        if reportedUnknownApps.insert("\(table)/\(rawValue)").inserted {
            Self.logger.error("Skipping rows of \(table, privacy: .public) for an unknown Bar App \(rawValue, privacy: .public)")
        }
        return nil
    }

    func prepare(_ sql: String) throws -> Statement {
        try Statement(sql: sql, database: database)
    }

    /// Whether any Telemetry has been archived, of any kind and from any time.
    public func holdsTelemetry() throws -> Bool {
        let statement = try prepare("""
            SELECT EXISTS (SELECT 1 FROM limit_samples_v2)
                OR EXISTS (SELECT 1 FROM token_samples_v2)
                OR EXISTS (SELECT 1 FROM limit_resets_v2)
                OR EXISTS (SELECT 1 FROM perk_points_v2)
                OR EXISTS (SELECT 1 FROM perk_gone_events_v2)
                OR EXISTS (SELECT 1 FROM perk_available_events_v2)
                OR EXISTS (SELECT 1 FROM limit_events_v2)
                OR EXISTS (SELECT 1 FROM tracking_starts_v2)
            """)
        guard try statement.step() else {
            return false
        }
        return statement.int64(at: 0) != 0
    }
}
