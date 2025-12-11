import Foundation
import GRDB

// MARK: - Query Source

/// A complete query definition bundling local query, remote fetch, and cache policy.
///
/// QuerySource provides a fluent API for defining reusable, network-coordinated queries
/// that can be referenced via keypaths in `@Query` property wrappers.
///
/// Example:
/// ```swift
/// @QuerySources
/// struct TaskSources {
///     let api: TasksAPIProtocol
///
///     var all: QuerySource<Task> {
///         QuerySource(Task.all().order(by: .createdAt))
///             .remote { try await api.fetchAll() }
///             .cache(.staleWhileRevalidate(staleAfter: .minutes(5)))
///     }
///
///     var completed: QuerySource<Task> {
///         QuerySource(Task.all().filter(Task.Columns.isCompleted == true))
///             .remote { try await api.fetchCompleted() }
///             .cache(.cacheFirst(ttl: .hours(1)))
///     }
///
///     // Local-only query (no remote fetch)
///     var recent: QuerySource<Task> {
///         QuerySource(Task.all().order(by: .createdAt).limit(10))
///     }
/// }
/// ```
public struct QuerySource<Element: FetchableRecord & PersistableRecord & TableRecord & Sendable> {
    /// The local database query
    public let request: QueryBuilder<Element>

    /// Cache policy for network coordination
    public let cachePolicy: QueryCachePolicy

    /// Optional action to refresh data from network
    public let refreshAction: QueryRefreshAction<Element>?

    // MARK: - Initializers

    /// Create a local-only query source (no remote fetch)
    /// - Parameter request: The query builder defining what records to observe
    public init(_ request: QueryBuilder<Element>) {
        self.request = request
        self.cachePolicy = .localOnly
        self.refreshAction = nil
    }

    /// Internal initializer with all parameters
    internal init(
        request: QueryBuilder<Element>,
        cachePolicy: QueryCachePolicy,
        refreshAction: QueryRefreshAction<Element>?
    ) {
        self.request = request
        self.cachePolicy = cachePolicy
        self.refreshAction = refreshAction
    }

    // MARK: - Fluent API

    /// Add remote fetch capability
    /// - Parameters:
    ///   - merge: How to merge remote data with local database (default: replace)
    ///   - fetch: Async closure that fetches data from the network
    /// - Returns: A new QuerySource with remote fetch configured
    public func remote(
        merge: QueryMergeStrategy = .replace,
        fetch: @escaping @Sendable () async throws -> [Element]
    ) -> QuerySource<Element> {
        QuerySource(
            request: request,
            cachePolicy: cachePolicy,
            refreshAction: QueryRefreshBuilder.fromAPI(fetch: fetch, merge: merge)
        )
    }

    /// Set the cache policy
    /// - Parameter policy: The cache policy to use
    /// - Returns: A new QuerySource with the specified cache policy
    public func cache(_ policy: QueryCachePolicy) -> QuerySource<Element> {
        QuerySource(
            request: request,
            cachePolicy: policy,
            refreshAction: refreshAction
        )
    }

    // MARK: - Convenience Cache Policies

    /// Configure stale-while-revalidate caching
    /// - Parameter staleAfter: Duration after which data is considered stale
    /// - Returns: A new QuerySource with stale-while-revalidate cache policy
    public func staleWhileRevalidate(after staleAfter: Duration) -> QuerySource<Element> {
        cache(.staleWhileRevalidate(staleAfter: staleAfter))
    }

    /// Configure cache-first caching
    /// - Parameter ttl: Time-to-live for cached data
    /// - Returns: A new QuerySource with cache-first cache policy
    public func cacheFirst(ttl: Duration) -> QuerySource<Element> {
        cache(.cacheFirst(ttl: ttl))
    }

    /// Configure network-first caching
    /// - Parameter fallbackToCache: Whether to use cached data on network failure
    /// - Returns: A new QuerySource with network-first cache policy
    public func networkFirst(fallbackToCache: Bool = true) -> QuerySource<Element> {
        cache(.networkFirst(fallbackToCache: fallbackToCache))
    }
}

// MARK: - Sendable Conformance

extension QuerySource: Sendable where Element: Sendable {}
