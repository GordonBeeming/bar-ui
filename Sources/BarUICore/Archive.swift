import Foundation
import SQLite3

/// The Dashboard's own permanent record of every Telemetry sample it has
/// imported. It is the store of record, not a cache of the Bar Apps' files:
/// those get deleted by retention, so nothing here is ever rebuilt from them.
public actor Archive {
    /// Every table is created with `IF NOT EXISTS`, so a later version adds
    /// its tables the same way and bumps this to say which it has.
    private static let schemaVersion: Int32 = 1
    private static let busyTimeoutMilliseconds: Int32 = 10_000

    private let connection: Connection
    private var database: OpaquePointer { connection.handle }
    /// Rollovers detected in each Limit's samples so far, by `app/limit`, so a
    /// read only scans polls newer than the last one it saw.
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
        try execute("""
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
            """, on: database, operation: "create its tables")
        try carryOverPerkSamples(into: database)
        try addLimitEventDescriptors(to: database)
        try execute("PRAGMA user_version = \(schemaVersion)", on: database, operation: "record its version")
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
    /// Only rows still without a name are filled, so every later open is a
    /// no-op.
    private static func addLimitEventDescriptors(to database: OpaquePointer) throws {
        // Another Bar UI process may open the same Archive at once; the write
        // lock keeps the two from both adding a column.
        try execute("BEGIN IMMEDIATE", on: database, operation: "start adding Limit event descriptors")
        do {
            try addLimitEventDescriptorColumns(to: database)
            try execute("COMMIT", on: database, operation: "finish adding Limit event descriptors")
        } catch {
            sqlite3_exec(database, "ROLLBACK", nil, nil, nil)
            throw error
        }
    }

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

    func prepare(_ sql: String) throws -> Statement {
        try Statement(sql: sql, database: database)
    }

    /// Whether any Telemetry has been archived, of any kind and from any time.
    public func holdsTelemetry() throws -> Bool {
        let statement = try prepare("""
            SELECT EXISTS (SELECT 1 FROM limit_samples)
                OR EXISTS (SELECT 1 FROM token_samples)
                OR EXISTS (SELECT 1 FROM limit_resets)
                OR EXISTS (SELECT 1 FROM perk_points)
                OR EXISTS (SELECT 1 FROM perk_gone_events)
                OR EXISTS (SELECT 1 FROM perk_available_events)
                OR EXISTS (SELECT 1 FROM limit_events)
                OR EXISTS (SELECT 1 FROM tracking_starts)
            """)
        guard try statement.step() else {
            return false
        }
        return statement.int64(at: 0) != 0
    }
}
