import Foundation

// MARK: - Cache Policy

/// Configurable cache policy for @Query that coordinates local database with network refresh
public struct QueryCachePolicy: Sendable, Equatable {
    /// The caching strategy to use
    public let strategy: CacheStrategy

    /// How long data remains fresh before becoming stale
    public let staleness: Duration?

    /// Whether to refresh in the background (true) or block UI (false)
    public let backgroundRefresh: Bool

    public init(
        strategy: CacheStrategy = .localOnly,
        staleness: Duration? = nil,
        backgroundRefresh: Bool = false
    ) {
        self.strategy = strategy
        self.staleness = staleness
        self.backgroundRefresh = backgroundRefresh
    }

    // MARK: - Preset Policies

    /// Local database only, no network coordination (current/default behavior)
    public static let localOnly = QueryCachePolicy(
        strategy: .localOnly,
        staleness: nil,
        backgroundRefresh: false
    )

    /// Returns cached data immediately, then fetches network in background and updates
    /// - Parameter staleAfter: Duration after which data is considered stale
    /// - Returns: A cache policy configured for stale-while-revalidate
    public static func staleWhileRevalidate(staleAfter: Duration = .seconds(60)) -> QueryCachePolicy {
        QueryCachePolicy(
            strategy: .staleWhileRevalidate,
            staleness: staleAfter,
            backgroundRefresh: true
        )
    }

    /// Returns cached data if fresh (within TTL), otherwise waits for network fetch
    /// - Parameter ttl: Time-to-live for cached data
    /// - Returns: A cache policy configured for cache-first behavior
    public static func cacheFirst(ttl: Duration) -> QueryCachePolicy {
        QueryCachePolicy(
            strategy: .cacheFirst,
            staleness: ttl,
            backgroundRefresh: false
        )
    }

    /// Always fetches from network first, falls back to cache if offline/error
    /// - Parameter fallbackToCache: Whether to use cached data on network failure
    /// - Returns: A cache policy configured for network-first behavior
    public static func networkFirst(fallbackToCache: Bool = true) -> QueryCachePolicy {
        QueryCachePolicy(
            strategy: fallbackToCache ? .networkFirst : .networkOnly,
            staleness: nil,
            backgroundRefresh: false
        )
    }

    /// Cache never expires automatically, only manual refresh updates data
    public static let manualRefresh = QueryCachePolicy(
        strategy: .cacheFirst,
        staleness: nil,
        backgroundRefresh: false
    )

    /// Always refresh on view appearance, but show cached data immediately
    public static func alwaysRefresh(backgroundRefresh: Bool = true) -> QueryCachePolicy {
        QueryCachePolicy(
            strategy: .staleWhileRevalidate,
            staleness: .zero,
            backgroundRefresh: backgroundRefresh
        )
    }
}

// MARK: - Cache Strategy

/// Core caching strategies for @Query
public enum CacheStrategy: String, Sendable, Codable, Equatable {
    /// Local database only, no network refresh
    case localOnly

    /// Return cached/stale data immediately, refresh in background
    case staleWhileRevalidate

    /// Return cached if fresh, otherwise wait for network
    case cacheFirst

    /// Always try network first, cache as fallback on failure
    case networkFirst

    /// Network only, no cache fallback (errors if offline)
    case networkOnly
}

// MARK: - Query Merge Strategy

/// How to merge remote data with local database for @Query refresh
public enum QueryMergeStrategy: Sendable, Equatable {
    /// Replace all local data with remote data (delete all, then insert)
    case replace

    /// Insert or update based on primary key
    case upsert

    /// Only insert records that don't exist locally
    case appendNew

    /// Soft delete: mark local records not in remote as deleted
    case softSync
}

// MARK: - Duration Helpers

extension Duration {
    /// Convert Duration to TimeInterval for Date arithmetic
    public var timeInterval: TimeInterval {
        let (seconds, attoseconds) = components
        return Double(seconds) + Double(attoseconds) / 1e18
    }
}
