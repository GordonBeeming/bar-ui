import Foundation
import SQLite3

public struct ArchiveError: Error, LocalizedError, Sendable {
    public let operation: String
    public let message: String
    public let code: Int32

    public var errorDescription: String? {
        "The Archive couldn't \(operation): \(message) (SQLite \(code))"
    }
}

/// Owns the SQLite handle so it is closed exactly once, when the Archive goes.
final class Connection {
    let handle: OpaquePointer

    init(handle: OpaquePointer) {
        self.handle = handle
    }

    deinit {
        sqlite3_close(handle)
    }
}

enum SQLValue {
    case text(String)
    case integer(Int64)
    case real(Double)
    case null
}

/// One prepared statement, finalized when it goes out of scope so an early
/// throw can't leak it.
final class Statement {
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
    var unixNano: Int64 {
        Int64((timeIntervalSince1970 * 1_000_000_000).rounded(.down))
    }

    init(unixNano: Int64) {
        let seconds = unixNano / 1_000_000_000
        let nanoseconds = unixNano % 1_000_000_000
        self.init(timeIntervalSince1970: TimeInterval(seconds) + TimeInterval(nanoseconds) / 1_000_000_000)
    }
}
