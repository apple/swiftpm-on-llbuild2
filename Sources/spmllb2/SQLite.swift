// This source file is part of the Swift.org open source project
//
// Copyright (c) 2020 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors

import ArgumentParser
import Foundation
import SQLite3
import TSCBasic
import TSCUtility
import TSFCAS
import TSFCASFileTree

struct SQL: ParsableCommand {

    @Option()
    var dbPath: String

    @Argument()
    var sql: String

    func run() throws {
        let dbPath = try AbsolutePath(validating: self.dbPath)
        let db = try SQLite(dbPath: dbPath)
        try db.exec(query: sql) { columns in
            print("===== ROW ====")
            for column in columns {
                print(column.name, column.value)
            }
        }
        try db.close()
    }
}

public final class SQLiteCAS: LLBCASDatabase {
    public let group: LLBFuturesDispatchGroup
    let db: SQLite

    /// Create a new sqlite-backed CAS database.
    ///
    /// Note: The caller is responsibe for closing the backing sqlite database.
    public init(
        group: LLBFuturesDispatchGroup,
        db: SQLite
    ) throws {
        self.group = group
        self.db = db

        let table = """
                CREATE TABLE IF NOT EXISTS CAS (
                    id BLOB PRIMARY KEY NOT NULL,
                    refs BLOB NOT NULL,
                    data BLOB NOT NULL
                );
            """

        try db.exec(query: table)
        try db.exec(query: "PRAGMA journal_mode=WAL;")
    }

    public func supportedFeatures() -> LLBFuture<LLBCASFeatures> {
        group.next().makeSucceededFuture(LLBCASFeatures(preservesIDs: true))
    }

    public func contains(
        _ id: LLBDataID,
        _ ctx: Context
    ) -> LLBFuture<Bool> {
        return group.next().submit {
            let readStmt = try self.db.prepare(query: "SELECT 1 FROM CAS WHERE id == ? LIMIT 1;")
            try readStmt.bind([.blob(id.bytes)])
            let row = try readStmt.step()
            try readStmt.finalize()
            return row != nil
        }
    }

    public func get(
        _ id: LLBDataID,
        _ ctx: Context
    ) -> LLBFuture<LLBCASObject?> {
        fatalError()
    }

    public func put(
        knownID id: LLBDataID,
        refs: [LLBDataID],
        data: LLBByteBuffer,
        _ ctx: Context
    ) -> LLBFuture<LLBDataID> {
        return group.next().submit {
            let refsData = try JSONEncoder().encode(refs)

            let writeStmt = try self.db.prepare(query: "INSERT OR IGNORE INTO CAS VALUES (?, ?, ?)")
            let bindings: [SQLite.SQLiteValue] = [
                .blob(id.bytes),
                .blob(refsData),
                .blob(Data(data.readableBytesView)),
            ]
            try writeStmt.bind(bindings)
            try writeStmt.step()
            try writeStmt.finalize()
            return id
        }
    }

    public func identify(
        refs: [LLBDataID],
        data: LLBByteBuffer,
        _ ctx: Context
    ) -> LLBFuture<LLBDataID> {
        group.next().makeSucceededFuture(LLBDataID(blake3hash: data, refs: refs))
    }

    public func put(
        refs: [LLBDataID],
        data: LLBByteBuffer,
        _ ctx: Context
    ) -> LLBFuture<LLBDataID> {
        let knownID = LLBDataID(blake3hash: data, refs: refs)
        return put(
            knownID: knownID,
            refs: refs,
            data: data,
            ctx
        )
    }
}

/// A minimal SQLite wrapper.
public struct SQLite {
    /// Represents an sqlite value.
    public enum SQLiteValue {
        case null
        case string(String)
        case int(Int)
        case blob(Data)
    }

    /// Represents a row returned by called step() on a prepared statement.
    public struct Row {
        /// The pointer to the prepared statment.
        let stmt: OpaquePointer

        /// Get integer at the given column index.
        func int(at index: Int32) -> Int {
            Int(sqlite3_column_int64(stmt, index))
        }

        /// Get blob data at the given column index.
        func blob(at index: Int32) -> Data {
            let bytes = sqlite3_column_blob(stmt, index)!
            let count = sqlite3_column_bytes(stmt, index)
            return Data(bytes: bytes, count: Int(count))
        }

        /// Get string at the given column index.
        func string(at index: Int32) -> String {
            return String(cString: sqlite3_column_text(stmt, index))
        }
    }

    /// Represents a prepared statement.
    public struct PreparedStatement {
        typealias sqlite3_destructor_type = (@convention(c) (UnsafeMutableRawPointer?) -> Void)
        static let SQLITE_STATIC = unsafeBitCast(0, to: sqlite3_destructor_type.self)
        static let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

        /// The pointer to the prepared statment.
        let stmt: OpaquePointer

        public init(db: OpaquePointer, query: String) throws {
            var stmt: OpaquePointer?
            try sqlite { sqlite3_prepare_v2(db, query, -1, &stmt, nil) }
            self.stmt = stmt!
        }

        /// Evaluate the prepared statement.
        @discardableResult
        public func step() throws -> Row? {
            let result = sqlite3_step(stmt)

            switch result {
            case SQLITE_DONE:
                return nil
            case SQLITE_ROW:
                return Row(stmt: stmt)
            default:
                throw StringError(String(cString: sqlite3_errstr(result)))
            }
        }

        /// Bind the given arguments to the statement.
        func bind(_ arguments: [SQLiteValue]) throws {
            for (idx, argument) in arguments.enumerated() {
                let idx = Int32(idx) + 1
                switch argument {
                case .null:
                    try sqlite { sqlite3_bind_null(stmt, idx) }
                case .int(let int):
                    try sqlite { sqlite3_bind_int64(stmt, idx, Int64(int)) }
                case .string(let str):
                    try sqlite { sqlite3_bind_text(stmt, idx, str, -1, Self.SQLITE_TRANSIENT) }
                case .blob(let blob):
                    try sqlite {
                        blob.withUnsafeBytes { ptr in
                            sqlite3_bind_blob(
                                stmt,
                                idx,
                                ptr.baseAddress,
                                Int32(blob.count),
                                Self.SQLITE_TRANSIENT
                            )
                        }
                    }
                }
            }
        }

        /// Reset the prepared statement.
        public func reset() throws {
            try sqlite { sqlite3_reset(stmt) }
        }

        /// Clear bindings from the prepared statment.
        public func clearBindings() throws {
            try sqlite { sqlite3_clear_bindings(stmt) }
        }

        /// Finalize the statement and free up resources.
        public func finalize() throws {
            try sqlite { sqlite3_finalize(stmt) }
        }
    }

    /// The path to the database file.
    let dbPath: AbsolutePath

    /// Pointer to the database.
    let db: OpaquePointer

    /// Create or open the database at the given path.
    ///
    /// The database is opened in serialized mode.
    public init(dbPath: AbsolutePath) throws {
        self.dbPath = dbPath

        var db: OpaquePointer? = nil
        try sqlite("unable to open database at \(dbPath)") {
            sqlite3_open_v2(
                dbPath.pathString,
                &db,
                SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX,
                nil
            )
        }

        self.db = db!
        try sqlite { sqlite3_extended_result_codes(db, 1) }
        try sqlite { sqlite3_busy_timeout(db, 5 * 1000 /* 5s */) }
    }

    /// Prepare the given query.
    func prepare(query: String) throws -> PreparedStatement {
        try PreparedStatement(db: db, query: query)
    }

    /// Directly execute the given query.
    ///
    /// Note: Use withCString for string arguments.
    func exec(query: String, args: [CVarArg] = [], _ callback: SQLiteExecCallback? = nil) throws {
        let query = withVaList(args) { ptr in
            sqlite3_vmprintf(query, ptr)
        }

        let wcb = callback.map { CallbackWrapper($0) }
        let callbackCtx = wcb.map { Unmanaged.passUnretained($0).toOpaque() }

        var err: UnsafeMutablePointer<Int8>? = nil
        try sqlite { sqlite3_exec(db, query, sqlite_callback, callbackCtx, &err) }

        if let err = err {
            let errorString = String(cString: err)
            sqlite3_free(err)
            throw StringError(errorString)
        }

        sqlite3_free(query)
    }

    func close() throws {
        try sqlite { sqlite3_close(db) }
    }

    struct Column {
        var name: String
        var value: String
    }

    typealias SQLiteExecCallback = ([Column]) -> Void
}

private class CallbackWrapper {
    var callback: SQLite.SQLiteExecCallback
    init(_ callback: @escaping SQLite.SQLiteExecCallback) {
        self.callback = callback
    }
}

func sqlite_callback(
    _ ctx: UnsafeMutableRawPointer?,
    _ numColumns: Int32,
    _ columns: UnsafeMutablePointer<UnsafeMutablePointer<Int8>?>?,
    _ columnNames: UnsafeMutablePointer<UnsafeMutablePointer<Int8>?>?
) -> Int32 {
    guard let ctx = ctx else { return 0 }
    guard let columnNames = columnNames, let columns = columns else { return 0 }
    let numColumns = Int(numColumns)
    var result: [SQLite.Column] = []

    for idx in 0..<numColumns {
        var name = ""
        if let ptr = columnNames.advanced(by: idx).pointee {
            name = String(cString: ptr)
        }
        var value = ""
        if let ptr = columns.advanced(by: idx).pointee {
            value = String(cString: ptr)
        }
        result.append(SQLite.Column(name: name, value: value))
    }

    let wcb = Unmanaged<CallbackWrapper>.fromOpaque(ctx).takeUnretainedValue()
    wcb.callback(result)

    return 0
}

@inlinable
func sqlite(_ errorPrefix: String? = nil, _ fn: () -> Int32) throws {
    let result = fn()
    if result != SQLITE_OK {
        var error = ""
        if let errorPrefix = errorPrefix {
            error += errorPrefix + ": "
        }
        error += String(cString: sqlite3_errstr(result))
        throw StringError(error)
    }
}

struct Refs: Codable {
    var refs: [LLBDataID]
}
