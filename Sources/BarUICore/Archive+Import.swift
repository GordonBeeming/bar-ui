import Foundation
import SQLite3

/// How far the Archive has read one Telemetry file. Files are append-only, so
/// the next import starts at `byteOffset` instead of re-reading the file.
public struct ImportProgress: Sendable, Hashable {
    public let app: BarApp
    public let fileName: String
    /// Zero means nothing of the file has been read yet, including after the
    /// Bar App's files started coming from another folder.
    public let byteOffset: Int64
    /// Running total for the file. It outlives the file, which is how skipped
    /// records stay reported after the Bar App's retention deletes it. A read
    /// from offset zero counts the file afresh and replaces it.
    public let droppedRecords: Int

    public init(app: BarApp, fileName: String, byteOffset: Int64, droppedRecords: Int) {
        self.app = app
        self.fileName = fileName
        self.byteOffset = byteOffset
        self.droppedRecords = droppedRecords
    }
}

extension Archive {
    /// Makes `folder` the one a Bar App's files are imported from. Read
    /// positions belong to the files they were taken in, so when the folder
    /// differs from the last one (or none was kept yet), every file of that
    /// Bar App goes back to offset zero and is read again from the start. A
    /// same-named file in the new folder, such as an old file appended to one
    /// already there, would otherwise be read from a position in a different
    /// file. Records already archived are ignored on the re-read, and skipped
    /// counts stay on files that didn't come along until a re-read replaces
    /// them.
    public func useImportFolder(_ folder: URL, for app: BarApp) throws {
        // IMMEDIATE so two importers switching at once can't both reset, and
        // so the reset lands between imports rather than inside one.
        try execute("BEGIN IMMEDIATE", operation: "start switching import folders")
        do {
            let path = Self.folderIdentity(folder)
            if try storedImportFolder(of: app) != path {
                try prepare("UPDATE imported_files SET byte_offset = 0 WHERE app = ?1")
                    .run(.text(app.rawValue))
                try prepare("""
                    INSERT INTO import_folders (app, folder) VALUES (?1, ?2)
                    ON CONFLICT (app) DO UPDATE SET folder = excluded.folder
                    """).run(.text(app.rawValue), .text(path))
            }
            try execute("COMMIT", operation: "finish switching import folders")
        } catch {
            do {
                try execute("ROLLBACK", operation: "roll back switching import folders")
            } catch let rollbackError {
                throw ArchiveError(operation: "switch import folders", message: "\(error.localizedDescription); then \(rollbackError.localizedDescription)", code: SQLITE_ERROR)
            }
            throw error
        }
    }

    /// Stores the records and the file's new read position together, so a
    /// crash part way can't move the position past records that were lost,
    /// but only if the file's stored position is still `previous`, the one the
    /// records were read from (nil when the file had none), and `folder` is
    /// still the Bar App's import folder. Another window or Bar UI process
    /// importing the same file may have moved it on, or switched folders, in
    /// the meantime; recording on top of that would count its skipped records
    /// twice, move the position backwards, or leave a position from a file
    /// that is no longer the one being read. Returns false, recording
    /// nothing, in either case. Records already in the Archive are left as
    /// they are.
    public func record(_ records: TelemetryRecords, progress: ImportProgress, readFrom previous: ImportProgress?, in folder: URL) throws -> Bool {
        try record(records, progress: progress, expecting: .exactly(previous, folder: Self.folderIdentity(folder)))
    }

    /// Records whatever position the file had. Only tests set up an Archive
    /// this way; an import must go through the guarded overload, or two
    /// importers reading the same file could count it twice.
    func record(_ records: TelemetryRecords, progress: ImportProgress) throws {
        _ = try record(records, progress: progress, expecting: .anything)
    }

    private enum ExpectedProgress {
        case anything
        case exactly(ImportProgress?, folder: String)
    }

    private static func folderIdentity(_ folder: URL) -> String {
        folder.standardizedFileURL.path
    }

    private func record(_ records: TelemetryRecords, progress: ImportProgress, expecting expected: ExpectedProgress) throws -> Bool {
        // IMMEDIATE takes the write lock before the position is checked, so
        // no other connection can move it between the check and the write.
        try execute("BEGIN IMMEDIATE", operation: "start an import")
        do {
            if case .exactly(let previous, let folder) = expected {
                let stored = try storedProgress(of: progress.app, fileName: progress.fileName)
                guard stored == previous, try storedImportFolder(of: progress.app) == folder else {
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
            let insertLimitEvent = try prepare("""
                INSERT OR IGNORE INTO limit_events (app, limit_id, kind, time_unix_nano, name, window_minutes, model_id)
                VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7)
                """)
            let insertTrackingStart = try prepare("""
                INSERT OR IGNORE INTO tracking_starts (app, time_unix_nano, interval_minutes)
                VALUES (?1, ?2, ?3)
                """)
            let insertAvailable = try prepare("""
                INSERT OR IGNORE INTO perk_available_events
                    (app, kind, currency, time_unix_nano, quantity, perk_id, expires_at)
                VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7)
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
            for reset in records.resets {
                try describeLimit(of: reset.app, reset.limit, at: reset.timeUnixNano)
                try insertReset.run(
                    .text(reset.app.rawValue),
                    .text(reset.limit.id),
                    .integer(reset.timeUnixNano),
                    .real(reset.utilizationLast),
                    reset.nextResetsAt.map { .real($0.timeIntervalSince1970) } ?? .null
                )
            }
            for sample in records.limitSamples {
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
            for sample in records.tokenSamples {
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
                INSERT OR IGNORE INTO perk_points (app, kind, currency, time_unix_nano, perk_id, value, expires_at)
                VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7)
                """)
            for sample in records.perkSamples {
                try insertPerk.run(
                    .text(sample.app.rawValue),
                    .text(sample.kind.rawValue),
                    .text(sample.currency ?? ""),
                    .integer(sample.timeUnixNano),
                    .text(sample.perkID ?? ""),
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
            for event in records.perkGoneEvents {
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
            for event in records.limitEvents {
                try describeLimit(of: event.app, event.limit, at: event.timeUnixNano)
                try insertLimitEvent.run(
                    .text(event.app.rawValue),
                    .text(event.limit.id),
                    .text(event.kind.rawValue),
                    .integer(event.timeUnixNano),
                    .text(event.limit.name),
                    event.limit.windowDurationMinutes.map { .integer(Int64($0)) } ?? .null,
                    event.limit.modelID.map { .text($0) } ?? .null
                )
            }
            for event in records.trackingStarts {
                try insertTrackingStart.run(
                    .text(event.app.rawValue),
                    .integer(event.timeUnixNano),
                    .integer(Int64(event.intervalMinutes))
                )
            }
            for event in records.perkAvailableEvents {
                try insertAvailable.run(
                    .text(event.app.rawValue),
                    .text(event.kind.rawValue),
                    .text(event.currency ?? ""),
                    .integer(event.timeUnixNano),
                    event.quantity.map { .real($0) } ?? .null,
                    .text(event.perkID ?? ""),
                    event.expiresAt.map { .integer($0) } ?? .null
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

    public func progress(of app: BarApp, fileName: String) throws -> ImportProgress? {
        try storedProgress(of: app, fileName: fileName)
    }

    private func storedImportFolder(of app: BarApp) throws -> String? {
        let statement = try prepare("SELECT folder FROM import_folders WHERE app = ?1")
        try statement.bind(.text(app.rawValue))
        guard try statement.step() else {
            return nil
        }
        return statement.text(at: 0)
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
}
