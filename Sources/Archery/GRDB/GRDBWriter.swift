import Foundation
import GRDB

// MARK: - GRDB Writer

/// Provides write operations for GRDB from SwiftUI views
///
/// Usage:
/// ```swift
/// struct CreatePlayerView: View {
///     @Environment(\.grdbWriter) private var writer
///
///     var body: some View {
///         Button("Create Player") {
///             Task {
///                 try await writer?.insert(Player(name: "New Player", score: 0))
///             }
///         }
///     }
/// }
/// ```
public struct GRDBWriter: Sendable {
    private let container: GRDBContainer

    /// Create a writer for the given container
    public init(container: GRDBContainer) {
        self.container = container
    }

    // MARK: - Insert Operations

    /// Insert a new record into the database
    /// - Parameter record: The record to insert
    /// - Returns: The inserted record (with auto-generated ID if applicable)
    @discardableResult
    public func insert<Record: MutablePersistableRecord & Sendable>(
        _ record: Record
    ) async throws -> Record {
        try await container.write { db in
            var mutableRecord = record
            try mutableRecord.insert(db)
            return mutableRecord
        }
    }

    /// Insert a record that doesn't need mutation (no auto-generated ID)
    @discardableResult
    public func insert<Record: PersistableRecord & Sendable>(
        _ record: Record
    ) async throws -> Record {
        try await container.write { db in
            try record.insert(db)
            return record
        }
    }

    /// Insert multiple records
    public func insertAll<Record: PersistableRecord & Sendable>(
        _ records: [Record]
    ) async throws {
        try await container.write { db in
            for record in records {
                try record.insert(db)
            }
        }
    }

    // MARK: - Update Operations

    /// Update an existing record
    public func update<Record: MutablePersistableRecord & Sendable>(
        _ record: Record
    ) async throws {
        try await container.write { db in
            var mutableRecord = record
            try mutableRecord.update(db)
        }
    }

    /// Update a record, inserting if it doesn't exist
    @discardableResult
    public func upsert<Record: MutablePersistableRecord & Sendable>(
        _ record: Record
    ) async throws -> Record {
        try await container.write { db in
            var mutableRecord = record
            try mutableRecord.save(db)
            return mutableRecord
        }
    }

    /// Update multiple records
    public func updateAll<Record: MutablePersistableRecord & Sendable>(
        _ records: [Record]
    ) async throws {
        try await container.write { db in
            for record in records {
                var mutableRecord = record
                try mutableRecord.update(db)
            }
        }
    }

    // MARK: - Delete Operations

    /// Delete a record from the database
    /// - Returns: true if a record was deleted
    @discardableResult
    public func delete<Record: MutablePersistableRecord & Sendable>(
        _ record: Record
    ) async throws -> Bool {
        try await container.write { db in
            var mutableRecord = record
            return try mutableRecord.delete(db)
        }
    }

    /// Delete a record by ID
    /// - Returns: true if a record was deleted
    @discardableResult
    public func delete<Record: TableRecord & Sendable, ID: DatabaseValueConvertible & Sendable>(
        _ type: Record.Type,
        id: ID
    ) async throws -> Bool {
        try await container.write { db in
            try Record.deleteOne(db, key: id)
        }
    }

    /// Delete all records of a type
    /// - Returns: The number of deleted records
    @discardableResult
    public func deleteAll<Record: TableRecord & Sendable>(
        _ type: Record.Type
    ) async throws -> Int {
        try await container.write { db in
            try Record.deleteAll(db)
        }
    }

    /// Delete records matching a predicate
    /// - Returns: The number of deleted records
    @discardableResult
    public func deleteAll<Record: TableRecord & Sendable>(
        _ type: Record.Type,
        where predicate: some SQLSpecificExpressible & Sendable
    ) async throws -> Int {
        try await container.write { db in
            try Record.filter(predicate).deleteAll(db)
        }
    }

    // MARK: - Batch Operations

    /// Execute multiple operations in a single transaction
    public func batch(
        _ operations: @escaping @Sendable (Database) throws -> Void
    ) async throws {
        try await container.write { db in
            try operations(db)
        }
    }

    /// Execute a custom write transaction and return a value
    public func transaction<T: Sendable>(
        _ block: @escaping @Sendable (Database) throws -> T
    ) async throws -> T {
        try await container.write(block)
    }
}

// MARK: - Convenience Methods

public extension GRDBWriter {
    /// Save a record (insert if new, update if exists)
    @discardableResult
    func save<Record: MutablePersistableRecord & Sendable>(
        _ record: Record
    ) async throws -> Record {
        try await upsert(record)
    }

    /// Delete multiple records
    func deleteAll<Record: MutablePersistableRecord & Sendable>(
        _ records: [Record]
    ) async throws {
        try await container.write { db in
            for record in records {
                var mutableRecord = record
                _ = try mutableRecord.delete(db)
            }
        }
    }
}
