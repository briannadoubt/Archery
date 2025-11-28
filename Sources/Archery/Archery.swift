// Runtime shims and macro declarations for Archery.

// MARK: - Navigation & Errors
public protocol NavigationRoute: Hashable {}

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

public struct CancelableTask: Sendable {
    private let cancelImpl: @Sendable () -> Void
    public init(cancel: @escaping @Sendable () -> Void) { self.cancelImpl = cancel }
    public func cancel() { cancelImpl() }
}

// Lightweight DI container used by generated code
public final class EnvContainer: @unchecked Sendable {
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
}

// Shared UI types
public enum LoadState<Value> {
    case idle
    case loading
    case success(Value)
    case failure(Error)
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
public protocol Resettable { func reset() }

// MARK: - Macro Declarations
@attached(member, names: arbitrary)
public macro KeyValueStore() = #externalMacro(module: "ArcheryMacros", type: "KeyValueStoreMacro")

@attached(peer, names: suffixed(Protocol), prefixed(Mock))
public macro Repository() = #externalMacro(module: "ArcheryMacros", type: "RepositoryMacro")

@attached(member, names: arbitrary)
public macro ObservableViewModel() = #externalMacro(module: "ArcheryMacros", type: "ObservableViewModelMacro")

@attached(member, names: arbitrary)
public macro ViewModelBound<V>() = #externalMacro(module: "ArcheryMacros", type: "ViewModelBoundMacro")

@attached(member, names: arbitrary)
public macro AppShell() = #externalMacro(module: "ArcheryMacros", type: "AppShellMacro")

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
}
#endif
