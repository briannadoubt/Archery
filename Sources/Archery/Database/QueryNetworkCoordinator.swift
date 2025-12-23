import Foundation
import SwiftUI
import GRDB

// MARK: - Query Network Coordinator

/// Coordinates network refresh for @Query property wrappers
/// Manages staleness tracking, background refreshes, and connectivity awareness
@MainActor
@Observable
public final class QueryNetworkCoordinator {
    /// Set of query keys currently being refreshed
    public private(set) var activeRefreshes: Set<String> = []

    /// Errors from recent refresh attempts
    public private(set) var refreshErrors: [String: Error] = [:]

    private let container: PersistenceContainer
    private let connectivity: ConnectivityMonitor
    private var metadataCache: [String: QueryMetadata] = [:]
    private var refreshTasks: [String: Task<Void, Never>] = [:]
    private var scheduledRefreshes: [String: Task<Void, Never>] = [:]

    /// Create a coordinator with the given persistence container
    /// - Parameters:
    ///   - container: The persistence container for database operations
    ///   - connectivity: The connectivity monitor (defaults to shared instance)
    public init(container: PersistenceContainer, connectivity: ConnectivityMonitor = .shared) {
        self.container = container
        self.connectivity = connectivity
    }

    // MARK: - Staleness Checking

    /// Check if a query's data is stale according to its cache policy
    /// - Parameters:
    ///   - queryKey: Unique key for the query
    ///   - policy: The cache policy to evaluate against
    /// - Returns: True if data should be refreshed
    public func isStale(queryKey: String, policy: QueryCachePolicy) -> Bool {
        guard let metadata = metadataCache[queryKey] else {
            // No metadata = never synced = stale for network policies
            return policy.strategy != .localOnly
        }
        return metadata.isStale(policy: policy)
    }

    /// Get the last sync time for a query
    /// - Parameter queryKey: Unique key for the query
    /// - Returns: Date of last successful sync, or nil if never synced
    public func lastSyncedAt(queryKey: String) -> Date? {
        metadataCache[queryKey]?.lastSyncedAt
    }

    /// Get metadata for a query
    /// - Parameter queryKey: Unique key for the query
    /// - Returns: The query metadata, or nil if not tracked
    public func metadata(for queryKey: String) -> QueryMetadata? {
        metadataCache[queryKey]
    }

    /// Check if a refresh is in progress for a query
    /// - Parameter queryKey: Unique key for the query
    /// - Returns: True if a refresh is currently in progress
    public func isRefreshing(queryKey: String) -> Bool {
        activeRefreshes.contains(queryKey)
    }

    // MARK: - Sync Recording

    /// Record that a sync completed successfully
    /// - Parameters:
    ///   - queryKey: Unique key for the query
    ///   - etag: Optional ETag from server response
    ///   - recordCount: Number of records synced
    public func recordSync(queryKey: String, etag: String? = nil, recordCount: Int = 0) async {
        var metadata = metadataCache[queryKey] ?? QueryMetadata(queryKey: queryKey)
        metadata.lastSyncedAt = Date()
        metadata.lastModifiedAt = Date()
        metadata.etag = etag
        metadata.recordCount = recordCount
        metadata.syncInProgress = false
        metadataCache[queryKey] = metadata

        // Clear any previous error
        refreshErrors[queryKey] = nil

        // Persist to database - capture metadata as a let constant for the closure
        let metadataToSave = metadata
        do {
            try await container.write { db in
                try metadataToSave.save(db)
            }
        } catch {
            // Log but don't fail - metadata persistence is best-effort
            print("[QueryNetworkCoordinator] Failed to persist metadata for \(queryKey): \(error)")
        }
    }

    /// Record that a sync failed
    /// - Parameters:
    ///   - queryKey: Unique key for the query
    ///   - error: The error that occurred
    public func recordSyncError(queryKey: String, error: Error) {
        refreshErrors[queryKey] = error

        if var metadata = metadataCache[queryKey] {
            metadata.syncInProgress = false
            metadataCache[queryKey] = metadata
        }
    }

    // MARK: - Refresh Execution

    /// Execute a refresh for a query
    /// - Parameters:
    ///   - queryKey: Unique key for the query
    ///   - action: The refresh action to execute
    /// - Returns: The fetched elements
    @discardableResult
    public func executeRefresh<Element: FetchableRecord & Sendable>(
        queryKey: String,
        action: AnyQueryRefreshAction<Element>
    ) async throws -> [Element] {
        // Mark as refreshing
        activeRefreshes.insert(queryKey)

        if var metadata = metadataCache[queryKey] {
            metadata.syncInProgress = true
            metadataCache[queryKey] = metadata
        }

        defer {
            activeRefreshes.remove(queryKey)
        }

        do {
            let result = try await action.execute(container: container)
            await recordSync(queryKey: queryKey, recordCount: result.count)
            return result
        } catch {
            recordSyncError(queryKey: queryKey, error: error)
            throw error
        }
    }

    // MARK: - Background Refresh Scheduling

    /// Schedule a background refresh if appropriate based on policy
    /// - Parameters:
    ///   - queryKey: Unique key for the query
    ///   - policy: The cache policy for this query
    ///   - action: The refresh action to execute
    public func scheduleRefreshIfNeeded<Element: FetchableRecord & Sendable>(
        queryKey: String,
        policy: QueryCachePolicy,
        action: AnyQueryRefreshAction<Element>
    ) {
        // Local-only queries never need refresh
        guard policy.strategy != .localOnly else { return }

        // Can't refresh if offline
        guard connectivity.isConnected else { return }

        // Already refreshing
        guard !activeRefreshes.contains(queryKey) else { return }

        // Check if refresh is needed based on policy
        let shouldRefresh = shouldRefreshNow(queryKey: queryKey, policy: policy)

        if shouldRefresh && policy.backgroundRefresh {
            executeBackgroundRefresh(queryKey: queryKey, action: action)
        }
    }

    /// Force a refresh regardless of staleness
    /// - Parameters:
    ///   - queryKey: Unique key for the query
    ///   - action: The refresh action to execute
    public func forceRefresh<Element: FetchableRecord & Sendable>(
        queryKey: String,
        action: AnyQueryRefreshAction<Element>
    ) async throws -> [Element] {
        // Cancel any existing scheduled refresh
        scheduledRefreshes[queryKey]?.cancel()
        scheduledRefreshes[queryKey] = nil

        return try await executeRefresh(queryKey: queryKey, action: action)
    }

    // MARK: - Private Helpers

    private func shouldRefreshNow(queryKey: String, policy: QueryCachePolicy) -> Bool {
        switch policy.strategy {
        case .localOnly:
            return false

        case .staleWhileRevalidate:
            return isStale(queryKey: queryKey, policy: policy)

        case .cacheFirst:
            return isStale(queryKey: queryKey, policy: policy)

        case .networkFirst, .networkOnly:
            // Always refresh for network-first strategies
            return true
        }
    }

    private func executeBackgroundRefresh<Element: FetchableRecord & Sendable>(
        queryKey: String,
        action: AnyQueryRefreshAction<Element>
    ) {
        // Cancel any existing task for this query
        refreshTasks[queryKey]?.cancel()

        refreshTasks[queryKey] = Task { [weak self] in
            guard let self = self else { return }

            do {
                _ = try await self.executeRefresh(queryKey: queryKey, action: action)
            } catch {
                // Background refresh errors are logged but not propagated
                print("[QueryNetworkCoordinator] Background refresh failed for \(queryKey): \(error)")
            }

            await MainActor.run {
                self.refreshTasks[queryKey] = nil
            }
        }
    }

    // MARK: - Metadata Loading

    /// Load metadata from database for all tracked queries
    public func loadMetadata() async {
        do {
            let allMetadata = try await container.read { db in
                try QueryMetadata.fetchAll(db)
            }

            for metadata in allMetadata {
                metadataCache[metadata.queryKey] = metadata
            }
        } catch {
            print("[QueryNetworkCoordinator] Failed to load metadata: \(error)")
        }
    }

    /// Clear all cached metadata
    public func clearMetadata() async {
        metadataCache.removeAll()
        refreshErrors.removeAll()

        do {
            try await container.write { db in
                try QueryMetadata.deleteAll(db)
            }
        } catch {
            print("[QueryNetworkCoordinator] Failed to clear metadata: \(error)")
        }
    }

    // MARK: - Cleanup

    /// Cancel all pending refresh tasks
    public func cancelAllRefreshes() {
        for (_, task) in refreshTasks {
            task.cancel()
        }
        refreshTasks.removeAll()

        for (_, task) in scheduledRefreshes {
            task.cancel()
        }
        scheduledRefreshes.removeAll()

        activeRefreshes.removeAll()
    }
}

// MARK: - Environment Integration

private struct QueryNetworkCoordinatorKey: EnvironmentKey {
    static let defaultValue: QueryNetworkCoordinator? = nil
}

public extension EnvironmentValues {
    /// The query network coordinator for coordinating @Query refreshes
    var queryNetworkCoordinator: QueryNetworkCoordinator? {
        get { self[QueryNetworkCoordinatorKey.self] }
        set { self[QueryNetworkCoordinatorKey.self] = newValue }
    }
}

public extension View {
    /// Inject a query network coordinator into the environment
    /// - Parameter coordinator: The coordinator to use
    /// - Returns: A view with the coordinator in its environment
    func queryNetworkCoordinator(_ coordinator: QueryNetworkCoordinator) -> some View {
        environment(\.queryNetworkCoordinator, coordinator)
    }
}

// MARK: - View Modifier for Auto-Setup

/// View modifier that automatically sets up query network coordination
public struct QueryCoordinationModifier: ViewModifier {
    @State private var coordinator: QueryNetworkCoordinator

    public init(container: PersistenceContainer) {
        self._coordinator = State(initialValue: QueryNetworkCoordinator(container: container))
    }

    public func body(content: Content) -> some View {
        content
            .environment(\.queryNetworkCoordinator, coordinator)
            .task {
                await coordinator.loadMetadata()
            }
    }
}

public extension View {
    /// Enable query network coordination for this view hierarchy
    /// - Parameter container: The persistence container to use
    /// - Returns: A view with query coordination enabled
    func enableQueryCoordination(container: PersistenceContainer) -> some View {
        modifier(QueryCoordinationModifier(container: container))
    }
}
