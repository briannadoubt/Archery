import Foundation
import GRDB

// MARK: - Query Metadata

/// Tracks staleness metadata for query results
/// Stored in a system table `_archery_query_metadata`
public struct QueryMetadata: Codable, FetchableRecord, PersistableRecord, Sendable, Equatable {
    public static let databaseTableName = "_archery_query_metadata"

    /// Unique identifier for the query (table name + query hash)
    public let queryKey: String

    /// Timestamp when data was last synced from network
    public var lastSyncedAt: Date?

    /// Timestamp when metadata was last modified
    public var lastModifiedAt: Date

    /// ETag or version from server for conditional requests
    public var etag: String?

    /// Number of records at last sync
    public var recordCount: Int

    /// Whether a sync is currently in progress
    public var syncInProgress: Bool

    public init(
        queryKey: String,
        lastSyncedAt: Date? = nil,
        lastModifiedAt: Date = Date(),
        etag: String? = nil,
        recordCount: Int = 0,
        syncInProgress: Bool = false
    ) {
        self.queryKey = queryKey
        self.lastSyncedAt = lastSyncedAt
        self.lastModifiedAt = lastModifiedAt
        self.etag = etag
        self.recordCount = recordCount
        self.syncInProgress = syncInProgress
    }

    // MARK: - Staleness Checking

    /// Check if data is stale based on the given cache policy
    /// - Parameter policy: The cache policy to evaluate against
    /// - Returns: True if data should be refreshed
    public func isStale(policy: QueryCachePolicy) -> Bool {
        // Local-only queries are never stale (no network refresh)
        guard policy.strategy != .localOnly else { return false }

        // Never synced = always stale for network-aware policies
        guard let lastSynced = lastSyncedAt else { return true }

        // No staleness duration = never expires (manual refresh only)
        guard let staleness = policy.staleness else { return false }

        // Check if staleness duration has passed
        let staleDate = lastSynced.addingTimeInterval(staleness.timeInterval)
        return Date() > staleDate
    }

    /// Time remaining until data becomes stale
    /// - Parameter policy: The cache policy to evaluate against
    /// - Returns: Duration until stale, or nil if already stale or no expiry
    public func timeUntilStale(policy: QueryCachePolicy) -> Duration? {
        guard let lastSynced = lastSyncedAt,
              let staleness = policy.staleness else { return nil }

        let staleDate = lastSynced.addingTimeInterval(staleness.timeInterval)
        let remaining = staleDate.timeIntervalSince(Date())

        guard remaining > 0 else { return nil }
        return .seconds(remaining)
    }

    // MARK: - Column Definitions

    public enum Columns: String, ColumnExpression {
        case queryKey
        case lastSyncedAt
        case lastModifiedAt
        case etag
        case recordCount
        case syncInProgress
    }
}

// MARK: - Migration

/// Migration to create the query metadata table
public struct QueryMetadataMigration: DatabaseMigration {
    public static let identifier = "_archery_query_metadata_v1"

    public init() {}

    public func migrate(_ db: Database) throws {
        try db.create(table: QueryMetadata.databaseTableName, ifNotExists: true) { t in
            t.primaryKey("queryKey", .text)
            t.column("lastSyncedAt", .datetime)
            t.column("lastModifiedAt", .datetime).notNull()
            t.column("etag", .text)
            t.column("recordCount", .integer).notNull().defaults(to: 0)
            t.column("syncInProgress", .boolean).notNull().defaults(to: false)
        }

        // Index for finding stale queries
        try db.create(
            index: "idx_query_metadata_last_synced",
            on: QueryMetadata.databaseTableName,
            columns: ["lastSyncedAt"],
            ifNotExists: true
        )
    }
}

// MARK: - Database Migration Protocol

/// Protocol for database migrations
public protocol DatabaseMigration: Sendable {
    static var identifier: String { get }
    func migrate(_ db: Database) throws
}
