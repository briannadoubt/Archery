import Foundation
#if canImport(Observation)
@_exported import Observation
#endif
// Runtime shims and macro declarations for Archery.

// MARK: - Navigation & Errors
public protocol NavigationRoute: Hashable, Sendable, NavigationSerializable {}

public enum RepositoryError: Error, Equatable {
    case notFound
    case decodingFailed
    case encodingFailed
    case io(Error)
    case unknown(Error)

    public static func == (lhs: RepositoryError, rhs: RepositoryError) -> Bool {
        switch (lhs, rhs) {
        case (.notFound, .notFound), (.decodingFailed, .decodingFailed), (.encodingFailed, .encodingFailed): return true
        case (.io, .io), (.unknown, .unknown): return true
        default: return false
        }
    }
}

public struct RepositorySourceError: Error, CustomStringConvertible {
    public let function: String
    public let file: String
    public let line: Int
    public let underlying: Error

    public var description: String {
        "\(function) @ \(file):\(line) — \(underlying)"
    }
}

public struct RepositoryTraceEvent: @unchecked Sendable {
    public let function: String
    public let key: String?
    public let start: ContinuousClock.Instant
    public let end: ContinuousClock.Instant
    public let duration: Duration
    public let cacheHit: Bool
    public let coalesced: Bool
    public let error: Error?
    public let metadata: RepositoryTraceMetadata?

    public init(
        function: String,
        key: String?,
        start: ContinuousClock.Instant,
        end: ContinuousClock.Instant,
        duration: Duration,
        cacheHit: Bool,
        coalesced: Bool,
        error: Error?,
        metadata: RepositoryTraceMetadata? = nil
    ) {
        self.function = function
        self.key = key
        self.start = start
        self.end = end
        self.duration = duration
        self.cacheHit = cacheHit
        self.coalesced = coalesced
        self.error = error
        self.metadata = metadata
    }
}

public typealias RepositoryTraceHandler = @Sendable (RepositoryTraceEvent) -> Void

public struct RepositoryTraceMetadata: Sendable {
    public let info: [String: Sendable]
    public init(_ info: [String: Sendable]) { self.info = info }
}

public func normalizeRepositoryError(_ error: Error, function: String, file: String, line: Int) -> RepositoryError {
    if let repoError = error as? RepositoryError {
        return repoError
    }

    if error is URLError {
        return .io(RepositorySourceError(function: function, file: file, line: line, underlying: error))
    }

    return .unknown(RepositorySourceError(function: function, file: file, line: line, underlying: error))
}

public struct CancelableTask: Sendable {
    private let cancelImpl: @Sendable () -> Void
    public init(cancel: @escaping @Sendable () -> Void) { self.cancelImpl = cancel }
    public func cancel() { cancelImpl() }
}

// Lightweight DI container used by generated code
public final class EnvContainer: @unchecked Sendable {
    public static let shared = EnvContainer()
    
    private var storage: [ObjectIdentifier: Any] = [:]
    private var factories: [ObjectIdentifier: () -> Any] = [:]

    public init() {}

    public func register<T>(_ instance: T) {
        storage[ObjectIdentifier(T.self)] = instance
    }

    public func registerFactory<T>(_ factory: @escaping () -> T) {
        factories[ObjectIdentifier(T.self)] = factory
    }

    public func resolve<T>() -> T? {
        if let value = storage[ObjectIdentifier(T.self)] as? T { return value }
        if let factory = factories[ObjectIdentifier(T.self)] {
            let value = factory() as? T
            storage[ObjectIdentifier(T.self)] = value
            return value
        }
        return nil
    }

    public func merge(into other: EnvContainer) {
        storage.forEach { other.storage[$0.key] = $0.value }
        factories.forEach { other.factories[$0.key] = $0.value }
    }

    /// Merges registrations from another container into this one.
    public func merge(from other: EnvContainer) {
        other.merge(into: self)
    }
}

public extension EnvContainer {
    /// Creates a child container that shares registrations/factories from the receiver.
    /// Useful for constructing child repositories that need the same DI shape without mutating the parent.
    func makeChildRepo<R>(_ builder: (EnvContainer) -> R) -> R {
        let child = EnvContainer()
        merge(into: child)
        return builder(child)
    }
}

// Shared UI types
public enum LoadState<Value> {
    case idle
    case loading
    case success(Value)
    case failure(Error)
}

extension LoadState: Equatable where Value: Equatable {
    public static func == (lhs: LoadState<Value>, rhs: LoadState<Value>) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle), (.loading, .loading):
            return true
        case let (.success(a), .success(b)):
            return a == b
        case (.failure, .failure):
            return true // errors considered equivalent for UI change tracking
        default:
            return false
        }
    }
}

public struct AlertState: Equatable {
    public let title: String
    public let message: String?
    public init(title: String, message: String? = nil) {
        self.title = title
        self.message = message
    }
}

public protocol Provides<T> { associatedtype T; func resolve() -> T }
@MainActor public protocol Resettable { func reset() }
@MainActor public protocol ArcheryLoadable { func load() async }
public struct DIManual: Sendable { public init() {} }
public struct ShellSheet: Sendable { public init() {} }
public struct ShellFullScreen: Sendable { public init() {} }
public struct ShellWindow: Sendable { public init() {} }
public struct AutoRegister: Sendable { public init() {} }

// MARK: - Macro Declarations
@attached(member, names: arbitrary)
public macro KeyValueStore() = #externalMacro(module: "ArcheryMacros", type: "KeyValueStoreMacro")

@attached(peer, names: suffixed(Protocol), suffixed(Live), prefixed(Mock))
public macro Repository() = #externalMacro(module: "ArcheryMacros", type: "RepositoryMacro")

@attached(member, names: arbitrary)
@attached(memberAttribute)
@attached(extension, conformances: Observation.Observable, ArcheryLoadable)
public macro ObservableViewModel() = #externalMacro(module: "ArcheryMacros", type: "ObservableViewModelMacro")

@attached(member, names: arbitrary)
public macro ViewModelBound<V>() = #externalMacro(module: "ArcheryMacros", type: "ViewModelBoundMacro")

@attached(member, names: arbitrary)
public macro AppShell() = #externalMacro(module: "ArcheryMacros", type: "AppShellMacro")

@attached(member, names: arbitrary)
public macro PersistenceGateway() = #externalMacro(module: "ArcheryMacros", type: "PersistenceGatewayMacro")

@attached(peer, names: suffixed(Protocol), suffixed(Live), prefixed(Mock))
public macro APIClient() = #externalMacro(module: "ArcheryMacros", type: "APIClientMacro")

@attached(peer)
public macro Cache(
    enabled: Bool = true,
    ttl: Duration? = nil
) = #externalMacro(module: "ArcheryMacros", type: "CacheMacro")

@attached(member, names: arbitrary)
@attached(extension, conformances: DesignTokenSet)
public macro DesignTokens(manifest: String) = #externalMacro(module: "ArcheryMacros", type: "DesignTokensMacro")

@attached(member, names: arbitrary)
@attached(extension, conformances: LocalizationKey)
public macro Localizable() = #externalMacro(module: "ArcheryMacros", type: "LocalizableMacro")

@attached(member, names: arbitrary)
@attached(extension)
public macro SharedModel(
    widget: Bool = true,
    intent: Bool = true,
    liveActivity: Bool = false
) = #externalMacro(module: "ArcheryMacros", type: "SharedModelMacro")

@attached(member, names: arbitrary)
@attached(extension, conformances: AnalyticsEvent)
public macro AnalyticsEvent() = #externalMacro(module: "ArcheryMacros", type: "AnalyticsEventMacro")

@attached(member, names: arbitrary)
@attached(extension)
public macro FeatureFlag() = #externalMacro(module: "ArcheryMacros", type: "FeatureFlagMacro")

// Minimal handle for tests
public struct Archery { public init() {} }

#if canImport(SwiftUI)
import SwiftUI
private struct ArcheryContainerKey: EnvironmentKey { static let defaultValue: EnvContainer? = nil }
public extension EnvironmentValues {
    var archeryContainer: EnvContainer? {
        get { self[ArcheryContainerKey.self] }
        set { self[ArcheryContainerKey.self] = newValue }
    }

    /// Toggle haptics used by sample/previews (e.g., retry button feedback).
    var archeryHapticsEnabled: Bool {
        get { self[ArcheryHapticsEnabledKey.self] }
        set { self[ArcheryHapticsEnabledKey.self] = newValue }
    }
}

private struct ArcheryHapticsEnabledKey: EnvironmentKey {
    static let defaultValue: Bool = true
}
#endif
