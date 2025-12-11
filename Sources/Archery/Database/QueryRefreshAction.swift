import Foundation
import GRDB

// MARK: - Query Refresh Action

/// Defines how a query refreshes its data from the network
/// This connects @APIClient network calls to @Query database updates
public struct QueryRefreshAction<Element: FetchableRecord & PersistableRecord & Sendable>: Sendable {
    private let _execute: @Sendable (PersistenceContainer) async throws -> [Element]
    private let _mergeStrategy: QueryMergeStrategy

    /// Create a refresh action with a custom execution closure
    /// - Parameters:
    ///   - merge: How to merge remote data with local database
    ///   - execute: Closure that fetches data and persists it
    public init(
        merge: QueryMergeStrategy = .replace,
        execute: @escaping @Sendable (PersistenceContainer) async throws -> [Element]
    ) {
        self._execute = execute
        self._mergeStrategy = merge
    }

    /// Execute the refresh action
    /// - Parameter container: The persistence container for database operations
    /// - Returns: The fetched elements
    public func execute(container: PersistenceContainer) async throws -> [Element] {
        try await _execute(container)
    }

    /// The merge strategy for this refresh action
    public var mergeStrategy: QueryMergeStrategy {
        _mergeStrategy
    }
}

// MARK: - Query Refresh Builder

/// Builder for creating refresh actions that coordinate with @APIClient
public enum QueryRefreshBuilder {

    /// Create a refresh action from an API client method
    /// - Parameters:
    ///   - fetch: Async closure that fetches data from the API
    ///   - merge: How to merge remote data with local database
    /// - Returns: A QueryRefreshAction that fetches and persists data
    public static func fromAPI<Element: FetchableRecord & PersistableRecord & TableRecord & Sendable>(
        fetch: @escaping @Sendable () async throws -> [Element],
        merge: QueryMergeStrategy = .replace
    ) -> QueryRefreshAction<Element> {
        QueryRefreshAction(merge: merge) { container in
            let remoteData = try await fetch()

            try await container.write { db in
                try Self.mergeData(remoteData, into: db, strategy: merge)
            }

            return remoteData
        }
    }

    /// Create a refresh action from an API client method with transformation
    /// - Parameters:
    ///   - fetch: Async closure that fetches DTOs from the API
    ///   - transform: Transform DTOs to database entities
    ///   - merge: How to merge remote data with local database
    /// - Returns: A QueryRefreshAction that fetches, transforms, and persists data
    public static func fromAPI<DTO, Element: FetchableRecord & PersistableRecord & TableRecord & Sendable>(
        fetch: @escaping @Sendable () async throws -> [DTO],
        transform: @escaping @Sendable (DTO) -> Element,
        merge: QueryMergeStrategy = .replace
    ) -> QueryRefreshAction<Element> {
        QueryRefreshAction(merge: merge) { container in
            let dtos = try await fetch()
            let entities = dtos.map(transform)

            try await container.write { db in
                try Self.mergeData(entities, into: db, strategy: merge)
            }

            return entities
        }
    }

    /// Create a refresh action using an API client instance
    /// - Parameters:
    ///   - client: The API client to use
    ///   - fetch: Method on the client that fetches data
    ///   - merge: How to merge remote data with local database
    /// - Returns: A QueryRefreshAction that fetches and persists data
    public static func using<Client, Element: FetchableRecord & PersistableRecord & TableRecord & Sendable>(
        _ client: Client,
        fetch: @escaping @Sendable (Client) async throws -> [Element],
        merge: QueryMergeStrategy = .replace
    ) -> QueryRefreshAction<Element> where Client: Sendable {
        QueryRefreshAction(merge: merge) { container in
            let remoteData = try await fetch(client)

            try await container.write { db in
                try Self.mergeData(remoteData, into: db, strategy: merge)
            }

            return remoteData
        }
    }

    /// Create a refresh action using an API client with DTO transformation
    /// - Parameters:
    ///   - client: The API client to use
    ///   - fetch: Method on the client that fetches DTOs
    ///   - transform: Transform DTOs to database entities
    ///   - merge: How to merge remote data with local database
    /// - Returns: A QueryRefreshAction that fetches, transforms, and persists data
    public static func using<Client, DTO, Element: FetchableRecord & PersistableRecord & TableRecord & Sendable>(
        _ client: Client,
        fetch: @escaping @Sendable (Client) async throws -> [DTO],
        transform: @escaping @Sendable (DTO) -> Element,
        merge: QueryMergeStrategy = .replace
    ) -> QueryRefreshAction<Element> where Client: Sendable {
        QueryRefreshAction(merge: merge) { container in
            let dtos = try await fetch(client)
            let entities = dtos.map(transform)

            try await container.write { db in
                try Self.mergeData(entities, into: db, strategy: merge)
            }

            return entities
        }
    }

    // MARK: - Private Merge Implementation

    private static func mergeData<Element: PersistableRecord & TableRecord>(
        _ data: [Element],
        into db: Database,
        strategy: QueryMergeStrategy
    ) throws {
        switch strategy {
        case .replace:
            // Delete all existing records, then insert new ones
            try Element.deleteAll(db)
            for item in data {
                try item.insert(db)
            }

        case .upsert:
            // Insert or update based on primary key
            for item in data {
                try item.save(db)
            }

        case .appendNew:
            // Only insert records that don't exist
            for item in data {
                // Try to insert, ignore conflicts
                try? item.insert(db, onConflict: .ignore)
            }

        case .softSync:
            // Mark local records not in remote as deleted (requires soft delete column)
            // For now, fall back to upsert behavior
            for item in data {
                try item.save(db)
            }
        }
    }
}

// MARK: - Single Record Refresh

/// Refresh action for single record queries
public struct SingleQueryRefreshAction<Element: FetchableRecord & PersistableRecord & Sendable>: Sendable {
    private let _execute: @Sendable (PersistenceContainer) async throws -> Element?

    public init(execute: @escaping @Sendable (PersistenceContainer) async throws -> Element?) {
        self._execute = execute
    }

    public func execute(container: PersistenceContainer) async throws -> Element? {
        try await _execute(container)
    }
}

// MARK: - Single Record Builder

extension QueryRefreshBuilder {

    /// Create a refresh action for a single record
    public static func single<Element: FetchableRecord & PersistableRecord & Sendable>(
        fetch: @escaping @Sendable () async throws -> Element?,
        onFetch: @escaping @Sendable (Element, PersistenceContainer) async throws -> Void = { element, container in
            try await container.write { db in
                try element.save(db)
            }
        }
    ) -> SingleQueryRefreshAction<Element> {
        SingleQueryRefreshAction { container in
            guard let element = try await fetch() else { return nil }
            try await onFetch(element, container)
            return element
        }
    }
}
