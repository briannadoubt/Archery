import Foundation
import GRDB
import SwiftUI

// MARK: - @GRDBQuery Property Wrapper for Arrays

/// Property wrapper for observing GRDB query results in SwiftUI views
///
/// Usage:
/// ```swift
/// struct PlayerListView: View {
///     @GRDBQuery(Player.all())
///     var players: [Player]
///
///     var body: some View {
///         List(players) { player in
///             Text(player.name)
///         }
///     }
/// }
/// ```
@propertyWrapper
public struct GRDBQuery<Element: FetchableRecord & TableRecord & Sendable>: DynamicProperty {
    @Environment(\.grdbContainer) private var container
    @StateObject private var queryState: GRDBArrayQueryStateObject<Element>

    private let request: GRDBQueryBuilder<Element>

    /// Create a query for observing multiple records
    public init(_ request: GRDBQueryBuilder<Element>) {
        self.request = request
        self._queryState = StateObject(wrappedValue: GRDBArrayQueryStateObject<Element>())
    }

    /// The current query results
    @MainActor
    public var wrappedValue: [Element] {
        queryState.value
    }

    /// Access to query state (loading, error, refresh)
    @MainActor
    public var projectedValue: GRDBQueryProjection<Element> {
        GRDBQueryProjection(state: queryState, request: request, container: container)
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

// MARK: - @GRDBQueryOne Property Wrapper for Single Records

/// Property wrapper for observing a single GRDB record in SwiftUI views
@propertyWrapper
public struct GRDBQueryOne<Element: FetchableRecord & TableRecord & Sendable>: DynamicProperty {
    @Environment(\.grdbContainer) private var container
    @StateObject private var queryState: GRDBSingleQueryStateObject<Element>

    private let request: GRDBSingleQueryBuilder<Element>

    /// Create a query for observing a single record
    public init(_ request: GRDBSingleQueryBuilder<Element>) {
        self.request = request
        self._queryState = StateObject(wrappedValue: GRDBSingleQueryStateObject<Element>())
    }

    /// The current record (or nil if not found)
    @MainActor
    public var wrappedValue: Element? {
        queryState.value
    }

    /// Access to query state (loading, error, refresh)
    @MainActor
    public var projectedValue: GRDBSingleQueryProjection<Element> {
        GRDBSingleQueryProjection(state: queryState, request: request, container: container)
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

// MARK: - @GRDBQueryCount Property Wrapper for Counts

/// Property wrapper for observing record counts in SwiftUI views
@propertyWrapper
public struct GRDBQueryCount<Record: FetchableRecord & TableRecord & Sendable>: DynamicProperty {
    @Environment(\.grdbContainer) private var container
    @StateObject private var queryState: GRDBCountQueryStateObject

    private let request: GRDBCountQueryBuilder<Record>

    /// Create a query for observing a count
    public init(_ request: GRDBCountQueryBuilder<Record>) {
        self.request = request
        self._queryState = StateObject(wrappedValue: GRDBCountQueryStateObject())
    }

    /// The current count
    @MainActor
    public var wrappedValue: Int {
        queryState.value
    }

    /// Access to query state (loading, error, refresh)
    @MainActor
    public var projectedValue: GRDBCountQueryProjection<Record> {
        GRDBCountQueryProjection(state: queryState, request: request, container: container)
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

// MARK: - ObservableObject State Wrappers (for @StateObject compatibility)

@MainActor
final class GRDBArrayQueryStateObject<Element: FetchableRecord & Sendable>: ObservableObject {
    @Published private(set) var value: [Element] = []
    @Published private(set) var state: QueryLoadState = .idle
    @Published private(set) var lastError: Error?

    private var cancellable: AnyDatabaseCancellable?
    private var isStarted = false

    nonisolated init() {}

    func startObservation<Request: GRDBQueryRequest>(
        _ request: Request,
        on container: GRDBContainer
    ) where Request.Element == Element {
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
                    self?.state = .failure(normalizeGRDBError(error))
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

    func restart<Request: GRDBQueryRequest>(
        _ request: Request,
        on container: GRDBContainer
    ) where Request.Element == Element {
        cancel()
        startObservation(request, on: container)
    }
}

@MainActor
final class GRDBSingleQueryStateObject<Element: FetchableRecord & Sendable>: ObservableObject {
    @Published private(set) var value: Element?
    @Published private(set) var state: QueryLoadState = .idle
    @Published private(set) var lastError: Error?

    private var cancellable: AnyDatabaseCancellable?
    private var isStarted = false

    nonisolated init() {}

    func startObservation<Request: GRDBSingleQueryRequest>(
        _ request: Request,
        on container: GRDBContainer
    ) where Request.Element == Element {
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
                    self?.state = .failure(normalizeGRDBError(error))
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

@MainActor
final class GRDBCountQueryStateObject: ObservableObject {
    @Published private(set) var value: Int = 0
    @Published private(set) var state: QueryLoadState = .idle
    @Published private(set) var lastError: Error?

    private var cancellable: AnyDatabaseCancellable?
    private var isStarted = false

    nonisolated init() {}

    func startObservation(
        _ request: some GRDBCountQueryRequest,
        on container: GRDBContainer
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
                    self?.state = .failure(normalizeGRDBError(error))
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

/// Projected value for array queries providing access to state and actions
@MainActor
public struct GRDBQueryProjection<Element: FetchableRecord & TableRecord & Sendable> {
    let state: GRDBArrayQueryStateObject<Element>
    let request: GRDBQueryBuilder<Element>
    let container: GRDBContainer?

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
    public var error: GRDBError? {
        state.state.error
    }

    /// User-friendly error message
    public var errorMessage: String? {
        error?.errorDescription
    }

    /// Refresh the query manually
    public func refresh() {
        guard let container = container else { return }
        state.restart(request, on: container)
    }
}

/// Projected value for single record queries
@MainActor
public struct GRDBSingleQueryProjection<Element: FetchableRecord & TableRecord & Sendable> {
    let state: GRDBSingleQueryStateObject<Element>
    let request: GRDBSingleQueryBuilder<Element>
    let container: GRDBContainer?

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
    public var error: GRDBError? {
        state.state.error
    }

    /// User-friendly error message
    public var errorMessage: String? {
        error?.errorDescription
    }
}

/// Projected value for count queries
@MainActor
public struct GRDBCountQueryProjection<Record: FetchableRecord & TableRecord & Sendable> {
    let state: GRDBCountQueryStateObject
    let request: GRDBCountQueryBuilder<Record>
    let container: GRDBContainer?

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
    public var error: GRDBError? {
        state.state.error
    }

    /// User-friendly error message
    public var errorMessage: String? {
        error?.errorDescription
    }
}
