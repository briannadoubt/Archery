import Foundation
import SQLite3

public struct SQLiteMigration: Sendable {
    public let fromVersion: Int
    public let toVersion: Int
    public let migrate: @Sendable (_ rows: [String: Data]) throws -> [String: Data]

    public init(
        fromVersion: Int,
        toVersion: Int,
        migrate: @escaping @Sendable (_ rows: [String: Data]) throws -> [String: Data]
    ) {
        self.fromVersion = fromVersion
        self.toVersion = toVersion
        self.migrate = migrate
    }
}

public enum SQLiteGatewayError: Error, Equatable {
    case openDatabase(Int32)
    case prepareFailed(Int32)
    case executionFailed(Int32)
    case stepFailed(Int32)
    case decodingFailure
}

public final class SQLiteKVStore: @unchecked Sendable {
    public struct Change: Sendable, Equatable {
        public let key: String
        public let data: Data?
    }

    private var db: OpaquePointer?
    private let queue = DispatchQueue(label: "archery.sqlite.kvstore")
    private var changeContinuation: AsyncStream<Change>.Continuation?

    public init(url: URL, migrations: [SQLiteMigration] = [], seed: [String: Data] = [:]) throws {
        var handle: OpaquePointer?
        let isMemory = url.path == ":memory:"

        if !isMemory {
            let directory = url.deletingLastPathComponent()
            if !FileManager.default.fileExists(atPath: directory.path) {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            }
        }

        guard sqlite3_open(url.path, &handle) == SQLITE_OK else {
            throw SQLiteGatewayError.openDatabase(sqlite3_errcode(handle))
        }
        db = handle

        if isMemory {
            try executeSync("PRAGMA journal_mode=MEMORY;")
            try executeSync("PRAGMA temp_store=MEMORY;")
        } else {
            try executeSync("PRAGMA journal_mode=WAL;")
        }
        try executeSync("CREATE TABLE IF NOT EXISTS kv (key TEXT PRIMARY KEY, value BLOB NOT NULL);")

        try applyMigrationsSync(migrations)
        if !seed.isEmpty {
            try seedIfNeededSync(seed)
        }
    }

    deinit {
        if let db {
            sqlite3_close(db)
        }
    }

    public static func inMemory(migrations: [SQLiteMigration] = [], seed: [String: Data] = [:]) throws -> SQLiteKVStore {
        try SQLiteKVStore(url: URL(fileURLWithPath: ":memory:"), migrations: migrations, seed: seed)
    }

    public func data(for key: String) async throws -> Data? {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                continuation.resume(with: Result { try self.dataSync(for: key) })
            }
        }
    }

    public func set(data: Data, for key: String) async throws {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                continuation.resume(with: Result {
                    try self.setSync(data: data, for: key)
                    self.notifyChange(key: key, data: data)
                })
            }
        }
    }

    public func remove(_ key: String) async throws {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                continuation.resume(with: Result {
                    try self.removeSync(key)
                    self.notifyChange(key: key, data: nil)
                })
            }
        }
    }

    public func changes() -> AsyncStream<Change> {
        var continuation: AsyncStream<Change>.Continuation!
        let stream = AsyncStream<Change> { cont in
            continuation = cont
        }
        queue.sync {
            self.changeContinuation = continuation
        }
        return stream
    }

    // MARK: - Sync helpers (executed on queue)

    private func executeSync(_ sql: String) throws {
        guard let db else { return }
        if sqlite3_exec(db, sql, nil, nil, nil) != SQLITE_OK {
            throw SQLiteGatewayError.executionFailed(sqlite3_errcode(db))
        }
    }

    private func dataSync(for key: String) throws -> Data? {
        guard let db else { return nil }
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }

        guard sqlite3_prepare_v2(db, "SELECT value FROM kv WHERE key = ? LIMIT 1;", -1, &statement, nil) == SQLITE_OK else {
            throw SQLiteGatewayError.prepareFailed(sqlite3_errcode(db))
        }
        _ = key.withCString { pointer in
            sqlite3_bind_text(statement, 1, pointer, -1, SQLITE_TRANSIENT)
        }

        let step = sqlite3_step(statement)
        if step == SQLITE_ROW {
            if let bytes = sqlite3_column_blob(statement, 0) {
                let size = Int(sqlite3_column_bytes(statement, 0))
                return Data(bytes: bytes, count: size)
            }
            return nil
        }
        if step == SQLITE_DONE {
            return nil
        }
        throw SQLiteGatewayError.stepFailed(step)
    }

    private func setSync(data: Data, for key: String) throws {
        guard let db else { return }
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }

        guard sqlite3_prepare_v2(db, "INSERT OR REPLACE INTO kv (key, value) VALUES (?, ?);", -1, &statement, nil) == SQLITE_OK else {
            throw SQLiteGatewayError.prepareFailed(sqlite3_errcode(db))
        }
        _ = key.withCString { pointer in
            sqlite3_bind_text(statement, 1, pointer, -1, SQLITE_TRANSIENT)
        }
        _ = data.withUnsafeBytes { pointer in
            sqlite3_bind_blob(statement, 2, pointer.baseAddress, Int32(pointer.count), SQLITE_TRANSIENT)
        }

        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw SQLiteGatewayError.stepFailed(sqlite3_errcode(db))
        }
    }

    private func removeSync(_ key: String) throws {
        guard let db else { return }
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }

        guard sqlite3_prepare_v2(db, "DELETE FROM kv WHERE key = ?;", -1, &statement, nil) == SQLITE_OK else {
            throw SQLiteGatewayError.prepareFailed(sqlite3_errcode(db))
        }
        _ = key.withCString { pointer in
            sqlite3_bind_text(statement, 1, pointer, -1, SQLITE_TRANSIENT)
        }

        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw SQLiteGatewayError.stepFailed(sqlite3_errcode(db))
        }
    }

    private func allRowsSync() throws -> [String: Data] {
        guard let db else { return [:] }
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }

        guard sqlite3_prepare_v2(db, "SELECT key, value FROM kv;", -1, &statement, nil) == SQLITE_OK else {
            throw SQLiteGatewayError.prepareFailed(sqlite3_errcode(db))
        }

        var output: [String: Data] = [:]
        while sqlite3_step(statement) == SQLITE_ROW {
            if
                let keyPtr = sqlite3_column_text(statement, 0),
                let blob = sqlite3_column_blob(statement, 1)
            {
                let key = String(cString: keyPtr)
                let size = Int(sqlite3_column_bytes(statement, 1))
                let data = Data(bytes: blob, count: size)
                output[key] = data
            }
        }
        return output
    }

    private func userVersionSync() throws -> Int {
        guard let db else { return 0 }
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        guard sqlite3_prepare_v2(db, "PRAGMA user_version;", -1, &statement, nil) == SQLITE_OK else {
            throw SQLiteGatewayError.prepareFailed(sqlite3_errcode(db))
        }
        guard sqlite3_step(statement) == SQLITE_ROW else {
            throw SQLiteGatewayError.stepFailed(sqlite3_errcode(db))
        }
        return Int(sqlite3_column_int(statement, 0))
    }

    private func setUserVersionSync(_ version: Int) throws {
        try executeSync("PRAGMA user_version = \(version);")
    }

    private func applyMigrationsSync(_ migrations: [SQLiteMigration]) throws {
        guard !migrations.isEmpty else { return }
        var current = try userVersionSync()
        let ordered = migrations.sorted { $0.fromVersion < $1.fromVersion }

        for migration in ordered where migration.fromVersion == current {
            let rows = try allRowsSync()
            let updated = try migration.migrate(rows)
            try replaceAllSync(with: updated)
            try setUserVersionSync(migration.toVersion)
            current = migration.toVersion
        }
    }

    private func replaceAllSync(with rows: [String: Data]) throws {
        try executeSync("DELETE FROM kv;")
        for (key, data) in rows {
            try setSync(data: data, for: key)
        }
    }

    private func seedIfNeededSync(_ seed: [String: Data]) throws {
        let existing = try allRowsSync()
        if !existing.isEmpty { return }
        for (key, data) in seed {
            try setSync(data: data, for: key)
        }
    }

    private func notifyChange(key: String, data: Data?) {
        changeContinuation?.yield(Change(key: key, data: data))
    }
}

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
