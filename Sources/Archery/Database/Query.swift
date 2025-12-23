import Foundation
import GRDB
import SwiftUI

// MARK: - Type-Erased Refresh Action

/// Type-erased refresh action for storage in Query without PersistableRecord constraint
public struct AnyQueryRefreshAction<Element: FetchableRecord & Sendable>: Sendable {
    private let _execute: @Sendable (PersistenceContainer) async throws -> [Element]

    /// Create from a QueryRefreshAction (requires Element: PersistableRecord at call site)
    public init(_ action: QueryRefreshAction<Element>) where Element: PersistableRecord {
        self._execute = { container in
            try await action.execute(container: container)
        }
    }

    public func execute(container: PersistenceContainer) async throws -> [Element] {
        try await _execute(container)
    }
}

// MARK: - @Query Property Wrapper for Arrays

/// Property wrapper for observing database query results in SwiftUI views
///
/// Basic Usage (local-only, current behavior):
/// ```swift
/// struct PlayerListView: View {
///     @Query(Player.all())
///     var players: [Player]
///
///     var body: some View {
///         List(players) { player in
///             Text(player.name)
///         }
///     }
/// }
/// ```
///
/// With Network Coordination:
/// ```swift
/// struct TaskListView: View {
///     @Query(
///         PersistentTask.all(),
///         cachePolicy: .staleWhileRevalidate(staleAfter: .minutes(5)),
///         refresh: .fromAPI { try await api.fetchTasks() }
///     )
///     var tasks: [PersistentTask]
///
///     var body: some View {
///         List(tasks) { task in
///             TaskRow(task: task)
///         }
///         .refreshable {
///             await $tasks.refresh()
///         }
///     }
/// }
/// ```
// MARK: - KeyPath Box for Sendable Compliance

/// Box to wrap KeyPath for Sendable compliance
/// KeyPath is not Sendable in Swift 6, but we ensure thread safety by only accessing on MainActor
private final class KeyPathBox<Root, Value>: @unchecked Sendable {
    nonisolated(unsafe) let keyPath: KeyPath<Root, Value>

    init(_ keyPath: KeyPath<Root, Value>) {
        self.keyPath = keyPath
    }
}

/// Box to wrap a value for Sendable compliance when we know it's safe
private final class ValueBox<T>: @unchecked Sendable {
    nonisolated(unsafe) let value: T

    init(_ value: T) {
        self.value = value
    }
}

// MARK: - Query Source Resolver

/// Type-erased wrapper for query source resolution
/// Uses @unchecked Sendable because KeyPath is not Sendable but we ensure thread safety
/// by only accessing the keypath on MainActor
private struct AnyQuerySourceResolver<Element: FetchableRecord & TableRecord & Sendable>: @unchecked Sendable {
    private let _resolve: @MainActor (QuerySourceRegistry) -> (QueryBuilder<Element>, QueryCachePolicy, AnyQueryRefreshAction<Element>?)?

    init<Provider: QuerySourceProvider>(
        keyPath: KeyPath<Provider, QuerySource<Element>>
    ) where Element: PersistableRecord {
        // Wrap keypath in a Sendable box
        let box = KeyPathBox(keyPath)
        self._resolve = { @MainActor registry in
            guard let provider = registry.resolve(Provider.self) else {
                return nil
            }
            let source = provider[keyPath: box.keyPath]
            let refreshAction = source.refreshAction.map { AnyQueryRefreshAction($0) }
            return (source.request, source.cachePolicy, refreshAction)
        }
    }

    init<Provider: QuerySourceProvider, Param>(
        keyPath: KeyPath<Provider, (Param) -> QuerySource<Element>>,
        param: Param
    ) where Element: PersistableRecord {
        // Wrap keypath and param in Sendable boxes
        let kpBox = KeyPathBox(keyPath)
        let paramBox = ValueBox(param)
        self._resolve = { @MainActor registry in
            guard let provider = registry.resolve(Provider.self) else {
                return nil
            }
            let factory = provider[keyPath: kpBox.keyPath]
            let source = factory(paramBox.value)
            let refreshAction = source.refreshAction.map { AnyQueryRefreshAction($0) }
            return (source.request, source.cachePolicy, refreshAction)
        }
    }

    @MainActor
    func resolve(from registry: QuerySourceRegistry) -> (QueryBuilder<Element>, QueryCachePolicy, AnyQueryRefreshAction<Element>?)? {
        _resolve(registry)
    }
}

// MARK: - @Query Property Wrapper for Arrays

@propertyWrapper
public struct Query<Element: FetchableRecord & TableRecord & Sendable>: DynamicProperty {
    @Environment(\.databaseContainer) private var container
    @Environment(\.queryNetworkCoordinator) private var networkCoordinator
    @Environment(\.querySourceRegistry) private var registry
    @State private var queryState: ArrayQueryStateObject<Element>

    // Direct initialization values (nil if using keypath resolver)
    private let directRequest: QueryBuilder<Element>?
    private let directCachePolicy: QueryCachePolicy
    private let directRefreshAction: AnyQueryRefreshAction<Element>?

    // Keypath-based resolver (nil if using direct init)
    private let resolver: AnyQuerySourceResolver<Element>?

    // MARK: - Direct Initializers

    /// Create a query for observing multiple records (local-only, backward compatible)
    /// - Parameter request: The query builder defining what records to observe
    public init(_ request: QueryBuilder<Element>) {
        self.directRequest = request
        self.directCachePolicy = .localOnly
        self.directRefreshAction = nil
        self.resolver = nil
        self._queryState = State(initialValue: ArrayQueryStateObject<Element>())
    }

    /// Create a query with configurable cache policy and optional network refresh
    /// - Parameters:
    ///   - request: The query builder defining what records to observe
    ///   - cachePolicy: How to coordinate local cache with network data
    ///   - refresh: Optional action to refresh data from the network
    public init(
        _ request: QueryBuilder<Element>,
        cachePolicy: QueryCachePolicy,
        refresh: QueryRefreshAction<Element>? = nil
    ) where Element: PersistableRecord {
        self.directRequest = request
        self.directCachePolicy = cachePolicy
        self.directRefreshAction = refresh.map { AnyQueryRefreshAction($0) }
        self.resolver = nil
        self._queryState = State(initialValue: ArrayQueryStateObject<Element>())
    }

    // MARK: - Keypath Initializers (Shorthand - Element.Sources)

    /// Create a query from a keypath using the model's associated Sources type
    ///
    /// This is the preferred syntax when Sources is nested in the model:
    /// ```swift
    /// extension Task: HasQuerySources {
    ///     @QuerySources
    ///     struct Sources {
    ///         var all: QuerySource<Task> { ... }
    ///     }
    /// }
    ///
    /// // Usage - Swift infers Task.Sources from [Task]
    /// @Query(\.all)
    /// var tasks: [Task]
    /// ```
    ///
    /// - Parameter keyPath: Keypath to a QuerySource property on Element.Sources
    public init(
        _ keyPath: KeyPath<Element.Sources, QuerySource<Element>>
    ) where Element: PersistableRecord & HasQuerySources {
        self.directRequest = nil
        self.directCachePolicy = .localOnly
        self.directRefreshAction = nil
        self.resolver = AnyQuerySourceResolver(keyPath: keyPath)
        self._queryState = State(initialValue: ArrayQueryStateObject<Element>())
    }

    /// Create a query from a parameterized keypath using the model's associated Sources type
    ///
    /// ```swift
    /// extension Task: HasQuerySources {
    ///     @QuerySources
    ///     struct Sources {
    ///         var byPriority: (Int) -> QuerySource<Task> { ... }
    ///     }
    /// }
    ///
    /// // Usage
    /// @Query(\.byPriority, param: 1)
    /// var highPriority: [Task]
    /// ```
    ///
    /// - Parameters:
    ///   - keyPath: Keypath to a function returning a QuerySource
    ///   - param: The parameter to pass to the function
    public init<Param: Sendable>(
        _ keyPath: KeyPath<Element.Sources, (Param) -> QuerySource<Element>>,
        param: Param
    ) where Element: PersistableRecord & HasQuerySources {
        self.directRequest = nil
        self.directCachePolicy = .localOnly
        self.directRefreshAction = nil
        self.resolver = AnyQuerySourceResolver(keyPath: keyPath, param: param)
        self._queryState = State(initialValue: ArrayQueryStateObject<Element>())
    }

    // MARK: - Keypath Initializers (Explicit Provider)

    /// Create a query from a keypath to a QuerySource on an explicit provider type
    ///
    /// Use this when the provider isn't nested in the model:
    /// ```swift
    /// @Query(\TaskSources.all)
    /// var tasks: [Task]
    /// ```
    ///
    /// - Parameter keyPath: Keypath to a QuerySource property on a QuerySourceProvider
    public init<Provider: QuerySourceProvider>(
        _ keyPath: KeyPath<Provider, QuerySource<Element>>
    ) where Element: PersistableRecord {
        self.directRequest = nil
        self.directCachePolicy = .localOnly
        self.directRefreshAction = nil
        self.resolver = AnyQuerySourceResolver(keyPath: keyPath)
        self._queryState = State(initialValue: ArrayQueryStateObject<Element>())
    }

    /// Create a query from a parameterized keypath on an explicit provider type
    ///
    /// - Parameters:
    ///   - keyPath: Keypath to a function returning a QuerySource
    ///   - param: The parameter to pass to the function
    public init<Provider: QuerySourceProvider, Param: Sendable>(
        _ keyPath: KeyPath<Provider, (Param) -> QuerySource<Element>>,
        param: Param
    ) where Element: PersistableRecord {
        self.directRequest = nil
        self.directCachePolicy = .localOnly
        self.directRefreshAction = nil
        self.resolver = AnyQuerySourceResolver(keyPath: keyPath, param: param)
        self._queryState = State(initialValue: ArrayQueryStateObject<Element>())
    }

    /// The current query results
    @MainActor
    public var wrappedValue: [Element] {
        queryState.value
    }

    /// Access to query state (loading, error, refresh, staleness)
    @MainActor
    public var projectedValue: QueryProjection<Element> {
        // Use resolved values if available, otherwise direct values
        let effectiveRequest = queryState.resolvedRequest ?? directRequest
        let effectiveCachePolicy = queryState.resolvedCachePolicy ?? directCachePolicy
        let effectiveRefreshAction = queryState.resolvedRefreshAction ?? directRefreshAction

        return QueryProjection(
            state: queryState,
            request: effectiveRequest,
            container: container,
            cachePolicy: effectiveCachePolicy,
            refreshAction: effectiveRefreshAction,
            networkCoordinator: networkCoordinator
        )
    }

    /// Called by SwiftUI when the view updates
    public mutating func update() {
        guard let container = container else { return }

        let state = queryState
        let coordinator = networkCoordinator
        let reg = registry
        let resolverRef = resolver

        // Determine request/policy/action (either direct or resolved from keypath)
        let request: QueryBuilder<Element>
        let cachePolicy: QueryCachePolicy
        let refreshAction: AnyQueryRefreshAction<Element>?

        if let directRequest = self.directRequest {
            // Direct initialization
            request = directRequest
            cachePolicy = self.directCachePolicy
            refreshAction = self.directRefreshAction
        } else if let resolverRef = resolverRef {
            // Keypath resolution - resolve from registry on MainActor
            let resolved = MainActor.assumeIsolated {
                resolverRef.resolve(from: reg)
            }

            guard let resolved = resolved else {
                // Provider not registered yet - skip this update
                print("[Query] WARNING: Provider not registered in QuerySourceRegistry - query will not observe")
                return
            }

            request = resolved.0
            cachePolicy = resolved.1
            refreshAction = resolved.2

            // Store resolved values for projectedValue access
            MainActor.assumeIsolated {
                state.resolvedRequest = request
                state.resolvedCachePolicy = cachePolicy
                state.resolvedRefreshAction = refreshAction
            }
        } else {
            // Neither direct nor resolver - shouldn't happen
            return
        }

        MainActor.assumeIsolated {
            state.startObservation(request, on: container)

            // Schedule network refresh if needed
            if let action = refreshAction, let coordinator = coordinator {
                coordinator.scheduleRefreshIfNeeded(
                    queryKey: request.queryKey,
                    policy: cachePolicy,
                    action: action
                )
            }
        }
    }
}

// MARK: - @QueryOne Property Wrapper for Single Records (with Editing Support)

/// Property wrapper for observing and editing a single database record.
///
/// `@QueryOne` provides:
/// - Live observation of a single record
/// - Editable bindings via `$record.propertyName`
/// - Change tracking (`$record.isDirty`)
/// - Save/reset/delete operations
///
/// ```swift
/// struct TaskEditView: View {
///     @QueryOne var task: TaskItem?
///
///     init(taskId: String) {
///         _task = QueryOne(TaskItem.find(taskId))
///     }
///
///     var body: some View {
///         if task != nil {
///             Form {
///                 TextField("Title", text: $task.title.or(""))
///                 Button("Save") { Task { try? await $task.save() } }
///             }
///             .disabled(!$task.isDirty)
///         }
///     }
/// }
/// ```
@propertyWrapper
public struct QueryOne<Element: MutablePersistableRecord & FetchableRecord & TableRecord & Sendable & Encodable>: DynamicProperty {
    @Environment(\.databaseContainer) private var container
    @Environment(\.databaseWriter) private var writer
    @State private var state: SingleEditableQueryState<Element>

    private let request: SingleQueryBuilder<Element>

    /// Create a query for observing and editing a single record
    public init(_ request: SingleQueryBuilder<Element>) {
        self.request = request
        self._state = State(initialValue: SingleEditableQueryState<Element>())
    }

    /// The current record (editing value if modified, otherwise original)
    @MainActor
    public var wrappedValue: Element? {
        state.editingValue ?? state.originalValue
    }

    /// Projection providing property bindings and operations
    @MainActor
    public var projectedValue: SingleQueryOneProjection<Element> {
        SingleQueryOneProjection(state: state, writer: writer)
    }

    /// Called by SwiftUI when the view updates
    public mutating func update() {
        guard let container = container else { return }
        let s = state
        let req = request
        MainActor.assumeIsolated {
            s.startObservation(req, on: container)
        }
    }
}


// MARK: - @QueryCount Property Wrapper for Counts

/// Property wrapper for observing record counts in SwiftUI views
@propertyWrapper
public struct QueryCount<Record: FetchableRecord & TableRecord & Sendable>: DynamicProperty {
    @Environment(\.databaseContainer) private var container
    @State private var queryState: CountQueryStateObject

    private let request: CountQueryBuilder<Record>

    /// Create a query for observing a count
    public init(_ request: CountQueryBuilder<Record>) {
        self.request = request
        self._queryState = State(initialValue: CountQueryStateObject())
    }

    /// The current count
    @MainActor
    public var wrappedValue: Int {
        queryState.value
    }

    /// Access to query state (loading, error, refresh)
    @MainActor
    public var projectedValue: CountQueryProjection<Record> {
        CountQueryProjection(state: queryState, request: request, container: container)
    }

    /// Called by SwiftUI when the view updates
    public mutating func update() {
        guard let container = container else { return }
        let state = queryState
        let req = request
        MainActor.assumeIsolated {
            state.startObservation(req, on: container)
        }
    }
}

// MARK: - Observable State Wrappers

@MainActor
@Observable
final class ArrayQueryStateObject<Element: FetchableRecord & TableRecord & Sendable> {
    private(set) var value: [Element] = []
    private(set) var state: QueryLoadState = .idle
    private(set) var lastError: Error?
    private(set) var isRefreshing: Bool = false
    private(set) var refreshError: Error?

    @ObservationIgnored
    private var cancellable: AnyDatabaseCancellable?
    @ObservationIgnored
    private var isStarted = false

    // Resolved source info (for keypath-based queries)
    // These are populated when a keypath query is resolved from the registry
    // Marked @ObservationIgnored to prevent infinite update loops
    @ObservationIgnored
    var resolvedRequest: QueryBuilder<Element>?
    @ObservationIgnored
    var resolvedCachePolicy: QueryCachePolicy?
    @ObservationIgnored
    var resolvedRefreshAction: AnyQueryRefreshAction<Element>?

    nonisolated init() {}

    func startObservation<Request: QueryRequest>(
        _ request: Request,
        on container: PersistenceContainer
    ) where Request.Element == Element {
        guard !isStarted else { return }
        isStarted = true
        print("[Query] Starting observation for \(Element.self)")

        let observation = request.makeObservation()

        // Defer state change to avoid "publishing changes from within view updates"
        Task { @MainActor [weak self] in
            self?.state = .loading
        }

        cancellable = observation.start(
            in: container.writer,
            scheduling: .async(onQueue: .main),
            onError: { [weak self] error in
                print("[Query] Error for \(Element.self): \(error)")
                Task { @MainActor in
                    self?.state = .failure(normalizePersistenceError(error))
                    self?.lastError = error
                }
            },
            onChange: { [weak self] newValue in
                print("[Query] Received \(newValue.count) \(Element.self) items")
                Task { @MainActor in
                    self?.value = newValue
                    self?.state = .success
                    self?.lastError = nil
                }
            }
        )
    }

    func cancel() {
        cancellable?.cancel()
        cancellable = nil
        isStarted = false
    }

    func restart<Request: QueryRequest>(
        _ request: Request,
        on container: PersistenceContainer
    ) where Request.Element == Element {
        cancel()
        startObservation(request, on: container)
    }

    func setRefreshing(_ refreshing: Bool) {
        isRefreshing = refreshing
        if refreshing {
            refreshError = nil
        }
    }

    func setRefreshError(_ error: Error) {
        refreshError = error
        isRefreshing = false
    }
}

@MainActor
@Observable
final class SingleEditableQueryState<Element: MutablePersistableRecord & FetchableRecord & Sendable & Encodable> {
    var originalValue: Element?
    var editingValue: Element?
    private(set) var loadState: QueryLoadState = .idle
    private(set) var lastError: Error?
    var isSaving = false
    var saveError: Error?

    @ObservationIgnored
    private var cancellable: AnyDatabaseCancellable?
    @ObservationIgnored
    private var isStarted = false

    nonisolated init() {}

    var isDirty: Bool {
        guard let editing = editingValue, let original = originalValue else { return false }
        let encoder = JSONEncoder()
        guard let editData = try? encoder.encode(editing),
              let origData = try? encoder.encode(original) else { return false }
        return editData != origData
    }

    func startObservation<Request: SingleQueryRequest>(
        _ request: Request,
        on container: PersistenceContainer
    ) where Request.Element == Element {
        guard !isStarted else { return }
        isStarted = true

        let observation = request.makeObservation()

        Task { @MainActor [weak self] in
            self?.loadState = .loading
        }

        cancellable = observation.start(
            in: container.writer,
            scheduling: .async(onQueue: .main),
            onError: { [weak self] error in
                Task { @MainActor in
                    self?.loadState = .failure(normalizePersistenceError(error))
                    self?.lastError = error
                }
            },
            onChange: { [weak self] newValue in
                Task { @MainActor in
                    self?.originalValue = newValue
                    // Only set editing value if not already editing
                    if self?.editingValue == nil {
                        self?.editingValue = newValue
                    }
                    self?.loadState = .success
                    self?.lastError = nil
                }
            }
        )
    }

    func reset() {
        editingValue = originalValue
        saveError = nil
    }

    func cancel() {
        cancellable?.cancel()
        cancellable = nil
        isStarted = false
    }
}

@MainActor
@Observable
final class CountQueryStateObject {
    private(set) var value: Int = 0
    private(set) var state: QueryLoadState = .idle
    private(set) var lastError: Error?

    @ObservationIgnored
    private var cancellable: AnyDatabaseCancellable?
    @ObservationIgnored
    private var isStarted = false

    nonisolated init() {}

    func startObservation(
        _ request: some CountQueryRequest,
        on container: PersistenceContainer
    ) {
        guard !isStarted else { return }
        isStarted = true

        let observation = request.makeObservation()

        // Defer state change to avoid "publishing changes from within view updates"
        Task { @MainActor [weak self] in
            self?.state = .loading
        }

        cancellable = observation.start(
            in: container.writer,
            scheduling: .async(onQueue: .main),
            onError: { [weak self] error in
                Task { @MainActor in
                    self?.state = .failure(normalizePersistenceError(error))
                    self?.lastError = error
                }
            },
            onChange: { [weak self] newValue in
                Task { @MainActor in
                    self?.value = newValue
                    self?.state = .success
                    self?.lastError = nil
                }
            }
        )
    }

    func cancel() {
        cancellable?.cancel()
        cancellable = nil
        isStarted = false
    }
}

// MARK: - Query Projections

/// Projected value for array queries providing access to state, staleness, and actions
@MainActor
public struct QueryProjection<Element: FetchableRecord & TableRecord & Sendable> {
    let state: ArrayQueryStateObject<Element>
    let request: QueryBuilder<Element>?
    let container: PersistenceContainer?
    let cachePolicy: QueryCachePolicy
    let refreshAction: AnyQueryRefreshAction<Element>?
    let networkCoordinator: QueryNetworkCoordinator?

    // Internal init for backward compatibility
    init(
        state: ArrayQueryStateObject<Element>,
        request: QueryBuilder<Element>?,
        container: PersistenceContainer?
    ) {
        self.state = state
        self.request = request
        self.container = container
        self.cachePolicy = .localOnly
        self.refreshAction = nil
        self.networkCoordinator = nil
    }

    // Full init with cache policy support
    init(
        state: ArrayQueryStateObject<Element>,
        request: QueryBuilder<Element>?,
        container: PersistenceContainer?,
        cachePolicy: QueryCachePolicy,
        refreshAction: AnyQueryRefreshAction<Element>?,
        networkCoordinator: QueryNetworkCoordinator?
    ) {
        self.state = state
        self.request = request
        self.container = container
        self.cachePolicy = cachePolicy
        self.refreshAction = refreshAction
        self.networkCoordinator = networkCoordinator
    }

    // MARK: - Load State

    /// Current load state
    public var loadState: QueryLoadState {
        state.state
    }

    /// Whether the query is currently loading
    public var isLoading: Bool {
        state.state.isLoading
    }

    /// Whether the query has completed successfully
    public var isSuccess: Bool {
        state.state.isSuccess
    }

    /// Whether the query has failed
    public var hasError: Bool {
        state.state.isFailure
    }

    /// The error if the query failed
    public var error: PersistenceError? {
        state.state.error
    }

    /// User-friendly error message
    public var errorMessage: String? {
        error?.errorDescription
    }

    // MARK: - Staleness (Network-Coordinated Queries)

    /// Whether data is stale according to cache policy
    public var isStale: Bool {
        guard cachePolicy.strategy != .localOnly else { return false }
        guard let request = request else { return false }
        return networkCoordinator?.isStale(queryKey: request.queryKey, policy: cachePolicy) ?? false
    }

    /// Last time this query was synced from network
    public var lastSyncedAt: Date? {
        guard let request = request else { return nil }
        return networkCoordinator?.lastSyncedAt(queryKey: request.queryKey)
    }

    /// Whether a network refresh is in progress
    public var isRefreshing: Bool {
        guard let request = request else { return state.isRefreshing }
        return state.isRefreshing || (networkCoordinator?.isRefreshing(queryKey: request.queryKey) ?? false)
    }

    /// Error from the last refresh attempt
    public var refreshError: Error? {
        guard let request = request else { return state.refreshError }
        return state.refreshError ?? networkCoordinator?.refreshErrors[request.queryKey]
    }

    // MARK: - Refresh Actions

    /// Refresh the query - restarts local observation and triggers network refresh if configured
    public func refresh() async {
        guard let request = request else { return }

        // Restart local observation
        if let container = container {
            state.restart(request, on: container)
        }

        // Trigger network refresh if configured
        guard let _ = container,
              let refreshAction = refreshAction,
              let coordinator = networkCoordinator else {
            return
        }

        state.setRefreshing(true)
        defer { state.setRefreshing(false) }

        do {
            _ = try await coordinator.executeRefresh(
                queryKey: request.queryKey,
                action: refreshAction
            )
        } catch {
            state.setRefreshError(error)
        }
    }

    /// Force a network refresh regardless of staleness
    public func forceRefresh() async {
        guard let request = request else { return }

        guard let _ = container,
              let refreshAction = refreshAction,
              let coordinator = networkCoordinator else {
            // Fall back to restarting local observation only
            if let container = container {
                state.restart(request, on: container)
            }
            return
        }

        state.setRefreshing(true)
        defer { state.setRefreshing(false) }

        do {
            _ = try await coordinator.forceRefresh(
                queryKey: request.queryKey,
                action: refreshAction
            )
        } catch {
            state.setRefreshError(error)
        }
    }

    /// Refresh local observation only (no network call)
    public func refreshLocal() {
        guard let container = container, let request = request else { return }
        state.restart(request, on: container)
    }
}

/// Projected value for @QueryOne providing property bindings and operations
@MainActor
@dynamicMemberLookup
public struct SingleQueryOneProjection<Element: MutablePersistableRecord & FetchableRecord & TableRecord & Sendable & Encodable> {
    private let state: SingleEditableQueryState<Element>
    private let writer: PersistenceWriter?

    init(state: SingleEditableQueryState<Element>, writer: PersistenceWriter?) {
        self.state = state
        self.writer = writer
    }

    // MARK: - State

    /// Current load state
    public var loadState: QueryLoadState { state.loadState }

    /// Whether the query is currently loading
    public var isLoading: Bool { state.loadState.isLoading }

    /// Whether the query has completed successfully
    public var isSuccess: Bool { state.loadState.isSuccess }

    /// Whether the query has failed
    public var hasError: Bool { state.loadState.isFailure }

    /// The error if the query failed
    public var error: PersistenceError? { state.loadState.error }

    /// Whether the record has unsaved changes
    public var isDirty: Bool { state.isDirty }

    /// Whether a save operation is in progress
    public var isSaving: Bool { state.isSaving }

    /// Most recent save error
    public var saveError: Error? { state.saveError }

    // MARK: - Property Bindings via Dynamic Member Lookup

    /// Access record properties as optional bindings
    /// Returns nil if no record is loaded
    public subscript<Value>(dynamicMember keyPath: WritableKeyPath<Element, Value>) -> Binding<Value>? {
        guard state.editingValue != nil else { return nil }
        return Binding(
            get: { state.editingValue![keyPath: keyPath] },
            set: { state.editingValue![keyPath: keyPath] = $0 }
        )
    }

    // MARK: - Operations

    /// Save changes to the database
    public func save() async throws {
        guard let writer, let record = state.editingValue else {
            throw QueryOneError.noWriter
        }
        state.isSaving = true
        state.saveError = nil
        defer { state.isSaving = false }

        do {
            try await writer.update(record)
            state.originalValue = record
        } catch {
            state.saveError = error
            throw error
        }
    }

    /// Reset to original values, discarding edits
    public func reset() {
        state.reset()
    }

    /// Delete the record from the database
    public func delete() async throws {
        guard let writer, let record = state.editingValue else {
            throw QueryOneError.noWriter
        }
        state.isSaving = true
        defer { state.isSaving = false }
        _ = try await writer.delete(record)
    }
}

/// Errors for @QueryOne operations
public enum QueryOneError: LocalizedError {
    case noWriter
    case noRecord

    public var errorDescription: String? {
        switch self {
        case .noWriter:
            return "No database writer available. Ensure the view has a database container in its environment."
        case .noRecord:
            return "No record loaded to perform this operation."
        }
    }
}

/// Projected value for count queries
@MainActor
public struct CountQueryProjection<Record: FetchableRecord & TableRecord & Sendable> {
    let state: CountQueryStateObject
    let request: CountQueryBuilder<Record>
    let container: PersistenceContainer?

    /// Current load state
    public var loadState: QueryLoadState {
        state.state
    }

    /// Whether the query is currently loading
    public var isLoading: Bool {
        state.state.isLoading
    }

    /// Whether the query has completed successfully
    public var isSuccess: Bool {
        state.state.isSuccess
    }

    /// Whether the query has failed
    public var hasError: Bool {
        state.state.isFailure
    }

    /// The error if the query failed
    public var error: PersistenceError? {
        state.state.error
    }

    /// User-friendly error message
    public var errorMessage: String? {
        error?.errorDescription
    }
}
