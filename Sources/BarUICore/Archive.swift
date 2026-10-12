import Foundation
import SQLite3

/// How far the Archive has read one Telemetry file. Files are append-only, so
/// the next import starts at `byteOffset` instead of re-reading the file.
public struct ImportProgress: Sendable, Hashable {
    public let app: BarApp
    public let fileName: String
    public let byteOffset: Int64
    /// Running total for the file, so the Imports page can show it later.
    public let droppedRecords: Int

    public init(app: BarApp, fileName: String, byteOffset: Int64, droppedRecords: Int) {
        self.app = app
        self.fileName = fileName
        self.byteOffset = byteOffset
        self.droppedRecords = droppedRecords
    }
}

/// A Limit as it stands at its latest sample.
public struct CurrentLimit: Sendable, Hashable {
    public let app: BarApp
    public let limit: LimitDescriptor
    public let utilization: Double
    public let sampledAt: Date
    /// Nil until a reset time has been recorded for the Limit.
    public let resetsAt: Date?

    public init(app: BarApp, limit: LimitDescriptor, utilization: Double, sampledAt: Date, resetsAt: Date?) {
        self.app = app
        self.limit = limit
        self.utilization = utilization
        self.sampledAt = sampledAt
        self.resetsAt = resetsAt
    }
}

public struct ArchivedSample: Sendable, Hashable {
    public let timeUnixNano: Int64
    public let value: Double

    public init(timeUnixNano: Int64, value: Double) {
        self.timeUnixNano = timeUnixNano
        self.value = value
    }
}

/// One Limit's utilisation and resets over a stretch of the Archive.
public struct LimitHistory: Sendable, Hashable {
    public let app: BarApp
    public let limit: LimitDescriptor
    public let utilization: [ArchivedSample]
    /// The newest utilisation sample ever archived, even when it falls before
    /// the range the rest was read for.
    public let latest: ArchivedSample?
    public let resets: [LimitReset]

    public init(app: BarApp, limit: LimitDescriptor, utilization: [ArchivedSample], latest: ArchivedSample?, resets: [LimitReset]) {
        self.app = app
        self.limit = limit
        self.utilization = utilization
        self.latest = latest
        self.resets = resets
    }
}

public struct ArchiveError: Error, LocalizedError, Sendable {
    public let operation: String
    public let message: String
    public let code: Int32

    public var errorDescription: String? {
        "The Archive couldn't \(operation): \(message) (SQLite \(code))"
    }
}

/// The Dashboard's own permanent record of every Telemetry sample it has
/// imported. It is the store of record, not a cache of the Bar Apps' files:
/// those get deleted by retention, so nothing here is ever rebuilt from them.
public actor Archive {
    private static let schemaVersion: Int32 = 1
    private static let busyTimeoutMilliseconds: Int32 = 10_000

    private let connection: Connection
    private var database: OpaquePointer { connection.handle }

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

    /// Stores the samples and the file's new read position together, so a
    /// crash part way can't move the position past samples that were lost.
    /// Samples already in the Archive are left as they are.
    public func record(_ samples: [LimitSample], tokenSamples: [TokenSample] = [], resets: [LimitReset] = [], perkSamples: [PerkSample] = [], perkGoneEvents: [PerkGoneEvent] = [], progress: ImportProgress) throws {
        let records = Records(samples: samples, tokenSamples: tokenSamples, resets: resets, perkSamples: perkSamples, perkGoneEvents: perkGoneEvents)
        _ = try record(records, progress: progress, expecting: .anything)
    }

    /// Like `record(_:tokenSamples:resets:perkSamples:perkGoneEvents:progress:)`,
    /// but only if the file's stored position is still `previous`, the one the
    /// records were read from (nil when the file had none). Another window or
    /// Bar UI process importing the same file may have moved it on in the
    /// meantime; recording on top of that would count its skipped records
    /// twice or move the position backwards. Returns false, recording
    /// nothing, when the position had moved.
    public func record(
        _ samples: [LimitSample],
        tokenSamples: [TokenSample] = [],
        resets: [LimitReset] = [],
        perkSamples: [PerkSample] = [],
        perkGoneEvents: [PerkGoneEvent] = [],
        progress: ImportProgress,
        readFrom previous: ImportProgress?
    ) throws -> Bool {
        let records = Records(samples: samples, tokenSamples: tokenSamples, resets: resets, perkSamples: perkSamples, perkGoneEvents: perkGoneEvents)
        return try record(records, progress: progress, expecting: .exactly(previous))
    }

    private struct Records {
        let samples: [LimitSample]
        let tokenSamples: [TokenSample]
        let resets: [LimitReset]
        let perkSamples: [PerkSample]
        let perkGoneEvents: [PerkGoneEvent]
    }

    private enum ExpectedProgress {
        case anything
        case exactly(ImportProgress?)
    }

    private func record(_ records: Records, progress: ImportProgress, expecting expected: ExpectedProgress) throws -> Bool {
        let samples = records.samples
        let tokenSamples = records.tokenSamples
        let resets = records.resets
        let perkSamples = records.perkSamples
        let perkGoneEvents = records.perkGoneEvents
        // IMMEDIATE takes the write lock before the position is checked, so
        // no other connection can move it between the check and the write.
        try execute("BEGIN IMMEDIATE", operation: "start an import")
        do {
            if case .exactly(let previous) = expected {
                let stored = try storedProgress(of: progress.app, fileName: progress.fileName)
                guard stored == previous else {
                    try execute("ROLLBACK", operation: "give up a stale import")
                    return false
                }
            }
            let describe = try prepare("""
                INSERT INTO limits (app, limit_id, name, window_minutes, model_id, described_at)
                VALUES (?1, ?2, ?3, ?4, ?5, ?6)
                ON CONFLICT (app, limit_id) DO UPDATE SET
                    name = excluded.name,
                    window_minutes = excluded.window_minutes,
                    model_id = excluded.model_id,
                    described_at = excluded.described_at
                WHERE excluded.described_at >= limits.described_at
                """)
            let insert = try prepare("""
                INSERT OR IGNORE INTO limit_samples (app, limit_id, metric, time_unix_nano, value)
                VALUES (?1, ?2, ?3, ?4, ?5)
                """)
            let insertReset = try prepare("""
                INSERT OR IGNORE INTO limit_resets (app, limit_id, time_unix_nano, utilization_last, next_resets_at)
                VALUES (?1, ?2, ?3, ?4, ?5)
                """)
            func describeLimit(of app: BarApp, _ limit: LimitDescriptor, at time: Int64) throws {
                try describe.run(
                    .text(app.rawValue),
                    .text(limit.id),
                    .text(limit.name),
                    limit.windowDurationMinutes.map { .integer(Int64($0)) } ?? .null,
                    limit.modelID.map { .text($0) } ?? .null,
                    .integer(time)
                )
            }
            for reset in resets {
                try describeLimit(of: reset.app, reset.limit, at: reset.timeUnixNano)
                try insertReset.run(
                    .text(reset.app.rawValue),
                    .text(reset.limit.id),
                    .integer(reset.timeUnixNano),
                    .real(reset.utilizationLast),
                    reset.nextResetsAt.map { .real($0.timeIntervalSince1970) } ?? .null
                )
            }
            for sample in samples {
                try describeLimit(of: sample.app, sample.limit, at: sample.timeUnixNano)
                try insert.run(
                    .text(sample.app.rawValue),
                    .text(sample.limit.id),
                    .text(sample.metric.rawValue),
                    .integer(sample.timeUnixNano),
                    .real(sample.value)
                )
            }
            let insertTokens = try prepare("""
                INSERT OR IGNORE INTO token_samples (app, model, token_type, time_unix_nano, start_time_unix_nano, count)
                VALUES (?1, ?2, ?3, ?4, ?5, ?6)
                """)
            for sample in tokenSamples {
                try insertTokens.run(
                    .text(sample.app.rawValue),
                    .text(sample.model),
                    .text(sample.tokenType.rawValue),
                    .integer(sample.timeUnixNano),
                    .integer(sample.startTimeUnixNano),
                    .integer(sample.count)
                )
            }
            let insertPerk = try prepare("""
                INSERT OR IGNORE INTO perk_samples (app, kind, currency, time_unix_nano, value, expires_at)
                VALUES (?1, ?2, ?3, ?4, ?5, ?6)
                """)
            for sample in perkSamples {
                try insertPerk.run(
                    .text(sample.app.rawValue),
                    .text(sample.kind.rawValue),
                    .text(sample.currency ?? ""),
                    .integer(sample.timeUnixNano),
                    .real(sample.value),
                    sample.expiresAt.map { .integer($0) } ?? .null
                )
            }
            // The unique index on the table makes a repeat of the same event a no-op.
            let insertGone = try prepare("""
                INSERT OR IGNORE INTO perk_gone_events
                    (app, kind, currency, time_unix_nano, quantity, perk_id, expires_at, reason)
                VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8)
                """)
            for event in perkGoneEvents {
                try insertGone.run(
                    .text(event.app.rawValue),
                    .text(event.kind.rawValue),
                    .text(event.currency ?? ""),
                    .integer(event.timeUnixNano),
                    event.quantity.map { .real($0) } ?? .null,
                    .text(event.perkID ?? ""),
                    event.expiresAt.map { .integer($0) } ?? .null,
                    event.reportedReason.map { .text($0.rawValue) } ?? .null
                )
            }
            try prepare("""
                INSERT INTO imported_files (app, file_name, byte_offset, dropped_records)
                VALUES (?1, ?2, ?3, ?4)
                ON CONFLICT (app, file_name) DO UPDATE SET
                    byte_offset = excluded.byte_offset,
                    dropped_records = excluded.dropped_records
                """).run(
                .text(progress.app.rawValue),
                .text(progress.fileName),
                .integer(progress.byteOffset),
                .integer(Int64(progress.droppedRecords))
            )
            try execute("COMMIT", operation: "finish an import")
            return true
        } catch {
            do {
                try execute("ROLLBACK", operation: "roll back a failed import")
            } catch let rollbackError {
                // The original error is the one worth surfacing; SQLite rolls
                // back an open transaction on close anyway.
                throw ArchiveError(operation: "import", message: "\(error.localizedDescription); then \(rollbackError.localizedDescription)", code: SQLITE_ERROR)
            }
            throw error
        }
    }

    public func availablePerks() throws -> [AvailablePerk] {
        let statement = try prepare("""
            SELECT p.app, p.kind, p.currency, p.value, p.expires_at, p.time_unix_nano
            FROM perk_samples p
            WHERE p.value > 0 AND p.time_unix_nano = (
                SELECT MAX(m.time_unix_nano) FROM perk_samples m
                WHERE m.app = p.app AND m.kind = p.kind AND m.currency = p.currency)
            """)
        var perks: [AvailablePerk] = []
        while try statement.step() {
            guard let appName = statement.text(at: 0), let app = BarApp(rawValue: appName),
                  let kindName = statement.text(at: 1), let kind = PerkKind(rawValue: kindName) else {
                continue
            }
            perks.append(AvailablePerk(
                app: app,
                kind: kind,
                currency: statement.text(at: 2).flatMap { $0.isEmpty ? nil : $0 },
                quantity: statement.double(at: 3),
                expiresAt: statement.optionalInt64(at: 4).map { Date(timeIntervalSince1970: TimeInterval($0)) },
                sampledAt: Date(unixNano: statement.int64(at: 5))
            ))
        }
        return perks.sorted { ($0.app.rawValue, $0.kind.sortOrder, $0.currency ?? "") < ($1.app.rawValue, $1.kind.sortOrder, $1.currency ?? "") }
    }

    /// Every gone Perk, newest first, each with its reason settled.
    public func gonePerks() throws -> [GonePerk] {
        let statement = try prepare("""
            SELECT app, kind, currency, quantity, perk_id, expires_at, reason, time_unix_nano
            FROM perk_gone_events
            ORDER BY time_unix_nano DESC, rowid DESC
            """)
        var perks: [GonePerk] = []
        while try statement.step() {
            guard let appName = statement.text(at: 0), let app = BarApp(rawValue: appName),
                  let kindName = statement.text(at: 1), let kind = PerkKind(rawValue: kindName) else {
                continue
            }
            let goneAt = Date(unixNano: statement.int64(at: 7))
            let expiresAt = statement.optionalInt64(at: 5).map { Date(timeIntervalSince1970: TimeInterval($0)) }
            perks.append(GonePerk(
                app: app,
                kind: kind,
                currency: statement.text(at: 2).flatMap { $0.isEmpty ? nil : $0 },
                quantity: statement.optionalDouble(at: 3),
                perkID: statement.text(at: 4).flatMap { $0.isEmpty ? nil : $0 },
                expiresAt: expiresAt,
                goneAt: goneAt,
                // No event records a redemption yet, so nothing can turn an
                // unexplained disappearance without an expiry into "used".
                reason: PerkGoneReason.resolve(
                    reported: statement.text(at: 6).flatMap(PerkGoneReason.init(rawValue:)),
                    goneAt: goneAt,
                    expiresAt: expiresAt,
                    redemptionOnRecord: false
                )
            ))
        }
        return perks
    }

    public func progress(of app: BarApp, fileName: String) throws -> ImportProgress? {
        try storedProgress(of: app, fileName: fileName)
    }

    private func storedProgress(of app: BarApp, fileName: String) throws -> ImportProgress? {
        let statement = try prepare("SELECT byte_offset, dropped_records FROM imported_files WHERE app = ?1 AND file_name = ?2")
        try statement.bind(.text(app.rawValue), .text(fileName))
        guard try statement.step() else {
            return nil
        }
        return ImportProgress(
            app: app,
            fileName: fileName,
            byteOffset: statement.int64(at: 0),
            droppedRecords: Int(statement.int64(at: 1))
        )
    }

    /// Records dropped for a Bar App, per day of the file they were in, oldest
    /// first. Counted from the files' import progress, so it stays complete
    /// after the Bar App deletes the files.
    public func skippedRecords(of app: BarApp) throws -> [SkippedRecords] {
        let statement = try prepare("SELECT file_name, dropped_records FROM imported_files WHERE app = ?1 AND dropped_records > 0")
        try statement.bind(.text(app.rawValue))
        var perDay: [TelemetryDay: Int] = [:]
        while try statement.step() {
            guard let name = statement.text(at: 0), let day = TelemetryDay(fileName: name) else {
                continue
            }
            perDay[day, default: 0] += Int(statement.int64(at: 1))
        }
        return perDay.map { SkippedRecords(day: $0.key, count: $0.value) }.sorted { $0.day < $1.day }
    }

    public func currentLimits() throws -> [CurrentLimit] {
        let statement = try prepare("""
            SELECT l.app, l.limit_id, l.name, l.window_minutes, l.model_id, u.time_unix_nano, u.value,
                (SELECT r.value FROM limit_samples r
                 WHERE r.app = l.app AND r.limit_id = l.limit_id AND r.metric = ?2
                 ORDER BY r.time_unix_nano DESC LIMIT 1)
            FROM limits l
            JOIN limit_samples u ON u.app = l.app AND u.limit_id = l.limit_id AND u.metric = ?1
            WHERE u.time_unix_nano = (
                SELECT MAX(m.time_unix_nano) FROM limit_samples m
                WHERE m.app = l.app AND m.limit_id = l.limit_id AND m.metric = ?1)
            ORDER BY l.app, l.limit_id
            """)
        try statement.bind(.text(LimitMetric.utilization.rawValue), .text(LimitMetric.resetsAt.rawValue))
        var limits: [CurrentLimit] = []
        while try statement.step() {
            // A Bar App this build doesn't know (written by a newer Bar UI)
            // can't be shown, but its rows stay in the Archive untouched.
            guard let appName = statement.text(at: 0), let app = BarApp(rawValue: appName),
                  let id = statement.text(at: 1), let name = statement.text(at: 2) else {
                continue
            }
            let limit = LimitDescriptor(
                id: id,
                name: name,
                windowDurationMinutes: statement.optionalInt64(at: 3).map { Int($0) },
                modelID: statement.text(at: 4)
            )
            limits.append(CurrentLimit(
                app: app,
                limit: limit,
                utilization: statement.double(at: 6),
                sampledAt: Date(unixNano: statement.int64(at: 5)),
                resetsAt: statement.optionalDouble(at: 7).map { Date(timeIntervalSince1970: $0) }
            ))
        }
        return limits
    }

    public func samples(of app: BarApp, limitID: String, metric: LimitMetric) throws -> [ArchivedSample] {
        try samples(of: app, limitID: limitID, metric: metric, since: Int64.min)
    }

    private func samples(of app: BarApp, limitID: String, metric: LimitMetric, since floor: Int64) throws -> [ArchivedSample] {
        let statement = try prepare("""
            SELECT time_unix_nano, value FROM limit_samples
            WHERE app = ?1 AND limit_id = ?2 AND metric = ?3 AND time_unix_nano >= ?4
            ORDER BY time_unix_nano
            """)
        try statement.bind(.text(app.rawValue), .text(limitID), .text(metric.rawValue), .integer(floor))
        var samples: [ArchivedSample] = []
        while try statement.step() {
            samples.append(ArchivedSample(timeUnixNano: statement.int64(at: 0), value: statement.double(at: 1)))
        }
        return samples
    }

    /// Every cumulative token point ever imported, oldest first. Turning them
    /// into usage per period is `TokenUsage`'s job, because that needs the
    /// whole series to tell a counter restart from a drop.
    public func tokenSamples() throws -> [TokenSample] {
        let statement = try prepare("""
            SELECT app, model, token_type, start_time_unix_nano, time_unix_nano, count
            FROM token_samples
            ORDER BY time_unix_nano, app, model, token_type
            """)
        var samples: [TokenSample] = []
        while try statement.step() {
            // Rows from a Bar App or Token Type this build doesn't know stay
            // in the Archive untouched but can't be shown.
            guard let appName = statement.text(at: 0), let app = BarApp(rawValue: appName),
                  let model = statement.text(at: 1),
                  let typeName = statement.text(at: 2), let tokenType = TokenType(rawValue: typeName) else {
                continue
            }
            samples.append(TokenSample(
                app: app,
                model: model,
                tokenType: tokenType,
                startTimeUnixNano: statement.int64(at: 3),
                timeUnixNano: statement.int64(at: 4),
                count: statement.int64(at: 5)
            ))
        }
        return samples
    }

    /// Every Limit the Archive holds for the Bar App, each with its
    /// utilisation samples and resets from `since` on (all of them when nil).
    /// A Limit with nothing in the range still comes back, so it can say so.
    public func limitHistories(of app: BarApp, since: Date?) throws -> [LimitHistory] {
        let floor = since.map { Int64(($0.timeIntervalSince1970 * 1_000_000_000).rounded(.down)) } ?? Int64.min
        let limits = try prepare("""
            SELECT limit_id, name, window_minutes, model_id FROM limits WHERE app = ?1 ORDER BY limit_id
            """)
        try limits.bind(.text(app.rawValue))
        var descriptors: [LimitDescriptor] = []
        while try limits.step() {
            guard let id = limits.text(at: 0), let name = limits.text(at: 1) else {
                continue
            }
            descriptors.append(LimitDescriptor(
                id: id,
                name: name,
                windowDurationMinutes: limits.optionalInt64(at: 2).map { Int($0) },
                modelID: limits.text(at: 3)
            ))
        }

        let resets = try prepare("""
            SELECT time_unix_nano, utilization_last, next_resets_at FROM limit_resets
            WHERE app = ?1 AND limit_id = ?2 AND time_unix_nano >= ?3
            ORDER BY time_unix_nano
            """)
        let latest = try prepare("""
            SELECT time_unix_nano, value FROM limit_samples
            WHERE app = ?1 AND limit_id = ?2 AND metric = ?3
            ORDER BY time_unix_nano DESC LIMIT 1
            """)
        var histories: [LimitHistory] = []
        for descriptor in descriptors {
            try resets.bind(.text(app.rawValue), .text(descriptor.id), .integer(floor))
            var events: [LimitReset] = []
            while try resets.step() {
                events.append(LimitReset(
                    app: app,
                    limit: descriptor,
                    timeUnixNano: resets.int64(at: 0),
                    utilizationLast: resets.double(at: 1),
                    nextResetsAt: resets.optionalDouble(at: 2).map { Date(timeIntervalSince1970: $0) }
                ))
            }
            try latest.bind(.text(app.rawValue), .text(descriptor.id), .text(LimitMetric.utilization.rawValue))
            let latestSample = try latest.step()
                ? ArchivedSample(timeUnixNano: latest.int64(at: 0), value: latest.double(at: 1))
                : nil
            histories.append(LimitHistory(
                app: app,
                limit: descriptor,
                utilization: try samples(of: app, limitID: descriptor.id, metric: .utilization, since: floor),
                latest: latestSample,
                resets: events
            ))
        }
        return histories
    }

    // MARK: - SQLite

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
            CREATE TABLE IF NOT EXISTS limit_resets (
                app TEXT NOT NULL,
                limit_id TEXT NOT NULL,
                time_unix_nano INTEGER NOT NULL,
                utilization_last REAL NOT NULL,
                next_resets_at REAL,
                PRIMARY KEY (app, limit_id, time_unix_nano)
            ) WITHOUT ROWID;
            CREATE TABLE IF NOT EXISTS perk_samples (
                app TEXT NOT NULL,
                kind TEXT NOT NULL,
                currency TEXT NOT NULL,
                time_unix_nano INTEGER NOT NULL,
                value REAL NOT NULL,
                expires_at INTEGER,
                PRIMARY KEY (app, kind, currency, time_unix_nano)
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
            PRAGMA user_version = \(schemaVersion);
            """, on: database, operation: "create its tables")
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

    private func execute(_ sql: String, operation: String) throws {
        try Self.execute(sql, on: database, operation: operation)
    }

    private func prepare(_ sql: String) throws -> Statement {
        try Statement(sql: sql, database: database)
    }
}

/// Owns the SQLite handle so it is closed exactly once, when the Archive goes.
private final class Connection {
    let handle: OpaquePointer

    init(handle: OpaquePointer) {
        self.handle = handle
    }

    deinit {
        sqlite3_close(handle)
    }
}

private enum SQLValue {
    case text(String)
    case integer(Int64)
    case real(Double)
    case null
}

/// One prepared statement, finalized when it goes out of scope so an early
/// throw can't leak it.
private final class Statement {
    /// SQLite copies bound text straight away instead of holding Swift's buffer.
    private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    private let handle: OpaquePointer
    private let database: OpaquePointer

    init(sql: String, database: OpaquePointer) throws {
        var handle: OpaquePointer?
        let result = sqlite3_prepare_v2(database, sql, -1, &handle, nil)
        guard result == SQLITE_OK, let handle else {
            throw ArchiveError(operation: "prepare a query", message: String(cString: sqlite3_errmsg(database)), code: result)
        }
        self.handle = handle
        self.database = database
    }

    deinit {
        sqlite3_finalize(handle)
    }

    func bind(_ values: SQLValue...) throws {
        try bind(values)
    }

    /// Binds, steps to completion and resets, ready to run again.
    func run(_ values: SQLValue...) throws {
        try bind(values)
        while try step() {}
    }

    /// True while there is a row to read.
    func step() throws -> Bool {
        let result = sqlite3_step(handle)
        switch result {
        case SQLITE_ROW:
            return true
        case SQLITE_DONE:
            return false
        default:
            throw ArchiveError(operation: "run a query", message: String(cString: sqlite3_errmsg(database)), code: result)
        }
    }

    func text(at column: Int32) -> String? {
        sqlite3_column_text(handle, column).map { String(cString: $0) }
    }

    func int64(at column: Int32) -> Int64 {
        sqlite3_column_int64(handle, column)
    }

    func double(at column: Int32) -> Double {
        sqlite3_column_double(handle, column)
    }

    func optionalInt64(at column: Int32) -> Int64? {
        sqlite3_column_type(handle, column) == SQLITE_NULL ? nil : int64(at: column)
    }

    func optionalDouble(at column: Int32) -> Double? {
        sqlite3_column_type(handle, column) == SQLITE_NULL ? nil : double(at: column)
    }

    private func bind(_ values: [SQLValue]) throws {
        sqlite3_reset(handle)
        sqlite3_clear_bindings(handle)
        for (offset, value) in values.enumerated() {
            let index = Int32(offset + 1)
            let result: Int32 = switch value {
            case .text(let text): sqlite3_bind_text(handle, index, text, -1, Self.transient)
            case .integer(let integer): sqlite3_bind_int64(handle, index, integer)
            case .real(let real): sqlite3_bind_double(handle, index, real)
            case .null: sqlite3_bind_null(handle, index)
            }
            guard result == SQLITE_OK else {
                throw ArchiveError(operation: "bind a query value", message: String(cString: sqlite3_errmsg(database)), code: result)
            }
        }
    }
}

extension Date {
    init(unixNano: Int64) {
        let seconds = unixNano / 1_000_000_000
        let nanoseconds = unixNano % 1_000_000_000
        self.init(timeIntervalSince1970: TimeInterval(seconds) + TimeInterval(nanoseconds) / 1_000_000_000)
    }
}
