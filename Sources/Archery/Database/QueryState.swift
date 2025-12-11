import Foundation
import GRDB
import Combine

// MARK: - Query Load State

/// Represents the loading state of a GRDB query
public enum QueryLoadState: Sendable, Equatable {
    case idle
    case loading
    case success
    case failure(PersistenceError)

    public var isLoading: Bool {
        if case .loading = self { return true }
        return false
    }

    public var isSuccess: Bool {
        if case .success = self { return true }
        return false
    }

    public var isFailure: Bool {
        if case .failure = self { return true }
        return false
    }

    public var error: PersistenceError? {
        if case .failure(let error) = self { return error }
        return nil
    }
}

// MARK: - Query State for Arrays

/// Observable state container for array query results
@MainActor
@Observable
public final class GRDBArrayQueryState<Element: FetchableRecord & Sendable> {
    public private(set) var value: [Element] = []
    public private(set) var state: QueryLoadState = .idle
    public private(set) var lastError: Error?

    private var cancellable: AnyDatabaseCancellable?
    private var isStarted = false

    public init() {}

    /// Start observing the query on the given container
    func startObservation<Request: QueryRequest>(
        _ request: Request,
        on container: PersistenceContainer
    ) where Request.Element == Element {
        guard !isStarted else { return }
        isStarted = true
        state = .loading

        let observation = request.makeObservation()

        cancellable = observation.start(
            in: container.writer,
            scheduling: .async(onQueue: .main),
            onError: { [weak self] error in
                Task { @MainActor in
                    self?.handleError(error)
                }
            },
            onChange: { [weak self] newValue in
                Task { @MainActor in
                    self?.handleValue(newValue)
                }
            }
        )
    }

    private func handleValue(_ newValue: [Element]) {
        self.value = newValue
        self.state = .success
        self.lastError = nil
    }

    private func handleError(_ error: Error) {
        self.state = .failure(normalizePersistenceError(error))
        self.lastError = error
    }

    /// Cancel the observation
    public func cancel() {
        cancellable?.cancel()
        cancellable = nil
        isStarted = false
    }

    /// Restart the observation (useful for manual refresh)
    func restart<Request: QueryRequest>(
        _ request: Request,
        on container: PersistenceContainer
    ) where Request.Element == Element {
        cancel()
        startObservation(request, on: container)
    }
}

// MARK: - Query State for Single Record

/// Observable state container for single record query results
@MainActor
@Observable
public final class GRDBSingleQueryState<Element: FetchableRecord & Sendable> {
    public private(set) var value: Element?
    public private(set) var state: QueryLoadState = .idle
    public private(set) var lastError: Error?

    private var cancellable: AnyDatabaseCancellable?
    private var isStarted = false

    public init() {}

    /// Start observing the query on the given container
    func startObservation<Request: SingleQueryRequest>(
        _ request: Request,
        on container: PersistenceContainer
    ) where Request.Element == Element {
        guard !isStarted else { return }
        isStarted = true
        state = .loading

        let observation = request.makeObservation()

        cancellable = observation.start(
            in: container.writer,
            scheduling: .async(onQueue: .main),
            onError: { [weak self] error in
                Task { @MainActor in
                    self?.handleError(error)
                }
            },
            onChange: { [weak self] newValue in
                Task { @MainActor in
                    self?.handleValue(newValue)
                }
            }
        )
    }

    private func handleValue(_ newValue: Element?) {
        self.value = newValue
        self.state = .success
        self.lastError = nil
    }

    private func handleError(_ error: Error) {
        self.state = .failure(normalizePersistenceError(error))
        self.lastError = error
    }

    /// Cancel the observation
    public func cancel() {
        cancellable?.cancel()
        cancellable = nil
        isStarted = false
    }
}

// MARK: - Query State for Count

/// Observable state container for count query results
@MainActor
@Observable
public final class GRDBCountQueryState {
    public private(set) var value: Int = 0
    public private(set) var state: QueryLoadState = .idle
    public private(set) var lastError: Error?

    private var cancellable: AnyDatabaseCancellable?
    private var isStarted = false

    public init() {}

    /// Start observing the count on the given container
    func startObservation(
        _ request: some CountQueryRequest,
        on container: PersistenceContainer
    ) {
        guard !isStarted else { return }
        isStarted = true
        state = .loading

        let observation = request.makeObservation()

        cancellable = observation.start(
            in: container.writer,
            scheduling: .async(onQueue: .main),
            onError: { [weak self] error in
                Task { @MainActor in
                    self?.handleError(error)
                }
            },
            onChange: { [weak self] newValue in
                Task { @MainActor in
                    self?.handleValue(newValue)
                }
            }
        )
    }

    private func handleValue(_ newValue: Int) {
        self.value = newValue
        self.state = .success
        self.lastError = nil
    }

    private func handleError(_ error: Error) {
        self.state = .failure(normalizePersistenceError(error))
        self.lastError = error
    }

    /// Cancel the observation
    public func cancel() {
        cancellable?.cancel()
        cancellable = nil
        isStarted = false
    }
}
