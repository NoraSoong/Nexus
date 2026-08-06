import Foundation
import SQLite3

final class DatabaseAccessGate: @unchecked Sendable {
    private let lock = NSRecursiveLock()

    func acquire() {
        lock.lock()
    }

    func release() {
        lock.unlock()
    }
}

enum SQLiteError: Error, CustomStringConvertible {
    case openFailed(String)
    case executeFailed(String)
    case prepareFailed(String)
    case stepFailed(String)

    var description: String {
        switch self {
        case .openFailed(let message): return "open failed: \(message)"
        case .executeFailed(let message): return "execute failed: \(message)"
        case .prepareFailed(let message): return "prepare failed: \(message)"
        case .stepFailed(let message): return "step failed: \(message)"
        }
    }
}

final class SQLiteDatabase {
    private var db: OpaquePointer?
    private let accessGate: DatabaseAccessGate?
    private var ownsAccessGate = false

    init(url: URL, accessGate: DatabaseAccessGate? = nil) throws {
        self.accessGate = accessGate
        accessGate?.acquire()
        ownsAccessGate = accessGate != nil

        do {
            var handle: OpaquePointer?
            let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
            if sqlite3_open_v2(url.path, &handle, flags, nil) != SQLITE_OK {
                let message = handle.flatMap { sqlite3_errmsg($0) }.map(String.init(cString:)) ?? "unknown"
                sqlite3_close(handle)
                throw SQLiteError.openFailed(message)
            }
            db = handle
            try execute("PRAGMA journal_mode=WAL;")
            try execute("PRAGMA busy_timeout=2000;")
            try execute("PRAGMA foreign_keys=ON;")
        } catch {
            sqlite3_close(db)
            db = nil
            releaseAccessGate()
            throw error
        }
    }

    deinit {
        sqlite3_close(db)
        releaseAccessGate()
    }

    func execute(_ sql: String) throws {
        var error: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(db, sql, nil, nil, &error) != SQLITE_OK {
            let message = error.map { String(cString: $0) } ?? lastErrorMessage
            sqlite3_free(error)
            throw SQLiteError.executeFailed(message)
        }
    }

    func execute(_ sql: String, bindings: [String?]) throws {
        var statement: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &statement, nil) != SQLITE_OK {
            throw SQLiteError.prepareFailed(lastErrorMessage)
        }
        defer { sqlite3_finalize(statement) }

        bind(bindings, to: statement)

        let result = sqlite3_step(statement)
        if result != SQLITE_DONE {
            throw SQLiteError.stepFailed(lastErrorMessage)
        }
    }

    func queryOne(_ sql: String, bindings: [String] = []) throws -> [String: String]? {
        try queryAll(sql, bindings: bindings.map(Optional.some)).first
    }

    func queryAll(_ sql: String, bindings: [String?] = []) throws -> [[String: String]] {
        var statement: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &statement, nil) != SQLITE_OK {
            throw SQLiteError.prepareFailed(lastErrorMessage)
        }
        defer { sqlite3_finalize(statement) }

        bind(bindings, to: statement)

        var rows: [[String: String]] = []
        while true {
            let result = sqlite3_step(statement)
            if result == SQLITE_DONE {
                return rows
            }
            if result != SQLITE_ROW {
                throw SQLiteError.stepFailed(lastErrorMessage)
            }
            var row: [String: String] = [:]
            for index in 0..<sqlite3_column_count(statement) {
                let name = String(cString: sqlite3_column_name(statement, index))
                if let text = sqlite3_column_text(statement, index) {
                    row[name] = String(cString: text)
                }
            }
            rows.append(row)
        }
    }

    var lastInsertRowID: Int64 {
        sqlite3_last_insert_rowid(db)
    }

    private var lastErrorMessage: String {
        db.flatMap { sqlite3_errmsg($0) }.map(String.init(cString:)) ?? "unknown"
    }

    private func bind(_ bindings: [String?], to statement: OpaquePointer?) {
        for (index, value) in bindings.enumerated() {
            if let value {
                sqlite3_bind_text(statement, Int32(index + 1), value, -1, sqliteTransient)
            } else {
                sqlite3_bind_null(statement, Int32(index + 1))
            }
        }
    }

    private func releaseAccessGate() {
        guard ownsAccessGate else { return }
        ownsAccessGate = false
        accessGate?.release()
    }
}

private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
