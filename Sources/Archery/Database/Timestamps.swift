import Foundation
import GRDB

// MARK: - HasTimestamps Protocol

/// Protocol for types with auto-managed `@CreatedAt` and `@UpdatedAt` timestamps.
///
/// Types conforming to this protocol will have their timestamps automatically set:
/// - `createdAt`: Set to current date on insert (if not already set)
/// - `updatedAt`: Set to current date on every update
///
/// Example:
/// ```swift
/// @Persistable(table: "posts")
/// struct Post: Codable, FetchableRecord, PersistableRecord, HasTimestamps {
///     var id: String
///     var title: String
///     @CreatedAt var createdAt: Date
///     @UpdatedAt var updatedAt: Date
/// }
///
/// // Usage:
/// var post = Post(id: "1", title: "Hello", createdAt: Date(), updatedAt: Date())
/// try await writer.insertWithTimestamps(&post)  // Sets both timestamps
/// try await writer.updateWithTimestamps(&post)  // Updates updatedAt only
/// ```
public protocol HasTimestamps {
    /// The creation timestamp (set once on insert)
    var createdAt: Date { get set }

    /// The last update timestamp (set on every update)
    var updatedAt: Date { get set }
}

// MARK: - HasCreatedAt Protocol

/// Protocol for types with only a `@CreatedAt` timestamp.
public protocol HasCreatedAt {
    var createdAt: Date { get set }
}

// MARK: - HasUpdatedAt Protocol

/// Protocol for types with only an `@UpdatedAt` timestamp.
public protocol HasUpdatedAt {
    var updatedAt: Date { get set }
}

// HasTimestamps implies both
extension HasTimestamps {
    // Default implementation for convenience
}

// MARK: - PersistenceWriter Extensions

public extension PersistenceWriter {
    /// Insert a record with auto-managed timestamps.
    /// Sets both `createdAt` and `updatedAt` to the current date.
    @discardableResult
    func insertWithTimestamps<T: PersistableRecord & HasTimestamps & Sendable>(
        _ record: T
    ) async throws -> T {
        let now = Date()
        var mutableRecord = record
        mutableRecord.createdAt = now
        mutableRecord.updatedAt = now
        try await insert(mutableRecord)
        return mutableRecord
    }

    /// Update a record with auto-managed timestamps.
    /// Sets `updatedAt` to the current date.
    @discardableResult
    func updateWithTimestamps<T: PersistableRecord & HasTimestamps & Sendable>(
        _ record: T
    ) async throws -> T {
        var mutableRecord = record
        mutableRecord.updatedAt = Date()
        try await update(mutableRecord)
        return mutableRecord
    }

    /// Upsert a record with auto-managed timestamps.
    /// Sets `updatedAt` to current date. If inserting, also sets `createdAt`.
    @discardableResult
    func upsertWithTimestamps<T: PersistableRecord & HasTimestamps & Sendable>(
        _ record: T
    ) async throws -> T {
        let now = Date()
        var mutableRecord = record
        // If createdAt is the default (epoch), treat as new record
        if mutableRecord.createdAt.timeIntervalSince1970 < 1 {
            mutableRecord.createdAt = now
        }
        mutableRecord.updatedAt = now
        try await upsert(mutableRecord)
        return mutableRecord
    }

    /// Insert a record with only createdAt timestamp.
    @discardableResult
    func insertWithCreatedAt<T: PersistableRecord & HasCreatedAt & Sendable>(
        _ record: T
    ) async throws -> T {
        var mutableRecord = record
        mutableRecord.createdAt = Date()
        try await insert(mutableRecord)
        return mutableRecord
    }

    /// Update a record with only updatedAt timestamp.
    @discardableResult
    func updateWithUpdatedAt<T: PersistableRecord & HasUpdatedAt & Sendable>(
        _ record: T
    ) async throws -> T {
        var mutableRecord = record
        mutableRecord.updatedAt = Date()
        try await update(mutableRecord)
        return mutableRecord
    }
}

// MARK: - PersistenceContainer Extensions

public extension PersistenceContainer {
    /// Insert a record with auto-managed timestamps.
    @discardableResult
    func insertWithTimestamps<T: PersistableRecord & HasTimestamps & Sendable>(
        _ record: T
    ) async throws -> T {
        let now = Date()
        var mutableRecord = record
        mutableRecord.createdAt = now
        mutableRecord.updatedAt = now
        let finalRecord = mutableRecord
        try await write { db in
            try finalRecord.insert(db)
        }
        return finalRecord
    }

    /// Update a record with auto-managed timestamps.
    @discardableResult
    func updateWithTimestamps<T: PersistableRecord & HasTimestamps & Sendable>(
        _ record: T
    ) async throws -> T {
        var mutableRecord = record
        mutableRecord.updatedAt = Date()
        let finalRecord = mutableRecord
        try await write { db in
            try finalRecord.update(db)
        }
        return finalRecord
    }
}
