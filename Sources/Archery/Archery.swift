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

/// Generates GRDB conformances helpers: Columns enum and databaseTableName.
/// User must manually add FetchableRecord, PersistableRecord conformances.
///
/// Example:
/// ```swift
/// @Persistable(table: "players")
/// struct Player: Codable, Identifiable, FetchableRecord, PersistableRecord {
///     var id: Int64
///     var name: String
///     var score: Int
/// }
/// // Macro generates: enum Columns { ... } and static let databaseTableName = "players"
/// ```
@attached(member, names: named(Columns), named(databaseTableName))
@attached(extension, names: arbitrary)
public macro Persistable(
    table: String? = nil,
    primaryKey: String = "id"
) = #externalMacro(module: "ArcheryMacros", type: "PersistableMacro")

/// Generates a repository pattern for GRDB with protocol, live, and mock implementations.
///
/// Example:
/// ```swift
/// @GRDBRepository(record: Player.self)
/// class PlayerStore {
///     func topScorers(limit: Int) async throws -> [Player] {
///         try await db.read { db in
///             try Player.order(Player.Columns.score.desc).limit(limit).fetchAll(db)
///         }
///     }
/// }
/// ```
@attached(peer, names: suffixed(Protocol), suffixed(Live), prefixed(Mock))
public macro GRDBRepository<T>(
    record: T.Type,
    tracing: Bool = false
) = #externalMacro(module: "ArcheryMacros", type: "GRDBRepositoryMacro")

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

/// Generates analytics event tracking methods for enums.
/// Generates: `eventName`, `properties`, `validate()`, `track(with:)`, `redactedProperties()`
/// You add: `AnalyticsEvent` conformance to your enum via extension.
@attached(member, names: arbitrary)
public macro AnalyticsEvent() = #externalMacro(module: "ArcheryMacros", type: "AnalyticsEventMacro")

/// Generates nested flag types for each enum case.
/// Each case generates a struct conforming to `Archery.FeatureFlag`.
@attached(member, names: arbitrary)
public macro FeatureFlag() = #externalMacro(module: "ArcheryMacros", type: "FeatureFlagMacro")

/// Generates URL pattern matching and auto-registration for route enums.
/// Generates: `fromURL()`, `toURLPath()`, `decodeNavigationIdentifier()`, `navigationIdentifier`
/// You add: `NavigationRoute` conformance to your enum.
///
/// Example:
/// ```swift
/// @Route(path: "tasks")
/// enum TasksRoute: NavigationRoute {  // You add NavigationRoute
///     case list              // matches /tasks/list
///     case detail(id: String) // matches /tasks/:id
/// }
/// ```
@attached(member, names: named(fromURL), named(toURLPath), named(entitlementRequirement), named(shouldAutoPaywall), named(presentationStyle), named(presentationMetadata))
@attached(extension, names: arbitrary)
public macro Route(
    path: String,
    requires: Entitlement? = nil,
    autoPaywall: Bool = true
) = #externalMacro(module: "ArcheryMacros", type: "RouteMacro")

// MARK: - Entitlement Gating Macros

/// Marks an enum case, tab, or ViewModel as requiring a specific entitlement.
/// Used with @Route enums to gate access to specific routes.
///
/// Example:
/// ```swift
/// @Route(path: "features")
/// enum FeatureRoute: NavigationRoute {
///     case free                           // No requirement
///     @requires(.premium)
///     case advancedTools                  // Requires premium
///     @requires(.pro, autoPaywall: false)
///     case analytics                      // Requires pro, manual paywall
/// }
/// ```
@attached(peer)
public macro requires(
    _ entitlement: Entitlement,
    autoPaywall: Bool = true,
    behavior: GatedTabBehavior = .locked
) = #externalMacro(module: "ArcheryMacros", type: "RequiresMacro")

/// Marks content as requiring ANY of the specified entitlements (OR logic).
/// Access is granted if the user has at least one of the listed entitlements.
///
/// Example:
/// ```swift
/// @requiresAny(.premium, .pro)
/// case reports  // Accessible with premium OR pro
/// ```
@attached(peer)
public macro requiresAny(
    _ entitlements: Entitlement...,
    autoPaywall: Bool = true,
    behavior: GatedTabBehavior = .locked
) = #externalMacro(module: "ArcheryMacros", type: "RequiresAnyMacro")

/// Marks content as requiring ALL of the specified entitlements (AND logic).
/// Access is granted only if the user has all listed entitlements.
///
/// Example:
/// ```swift
/// @requiresAll(.premium, .unlimitedAccess)
/// case bulkExport  // Requires both premium AND unlimited access
/// ```
@attached(peer)
public macro requiresAll(
    _ entitlements: Entitlement...,
    autoPaywall: Bool = true,
    behavior: GatedTabBehavior = .locked
) = #externalMacro(module: "ArcheryMacros", type: "RequiresAllMacro")

/// Marks a ViewModel class as requiring a specific entitlement.
/// Generates `requiredEntitlement` and `checkEntitlement()` members.
///
/// Example:
/// ```swift
/// @Entitled(.premium)
/// @ObservableViewModel
/// @MainActor
/// class PremiumDashboardViewModel: Resettable {
///     // Generated: static let requiredEntitlement = .required(.premium)
///     // Generated: func checkEntitlement(store:) -> Bool
/// }
/// ```
@attached(member, names: named(requiredEntitlement), named(checkEntitlement))
public macro Entitled(
    _ entitlement: Entitlement
) = #externalMacro(module: "ArcheryMacros", type: "EntitledMacro")

/// Marks a ViewModel as requiring ANY of the specified entitlements.
@attached(member, names: named(requiredEntitlement), named(checkEntitlement))
public macro EntitledAny(
    _ entitlements: Entitlement...
) = #externalMacro(module: "ArcheryMacros", type: "EntitledAnyMacro")

/// Marks a ViewModel as requiring ALL of the specified entitlements.
@attached(member, names: named(requiredEntitlement), named(checkEntitlement))
public macro EntitledAll(
    _ entitlements: Entitlement...
) = #externalMacro(module: "ArcheryMacros", type: "EntitledAllMacro")

// MARK: - Navigation Presentation Macros

/// Specifies how a route case should be presented.
/// Used with @Route enums to declare presentation style for each case.
///
/// Example:
/// ```swift
/// @Route(path: "tasks")
/// enum TasksRoute: NavigationRoute {
///     case list                    // Default: push
///     case detail(id: String)      // Default: push
///
///     @presents(.sheet)
///     case create                  // Presents as sheet
///
///     @presents(.fullScreen)
///     case bulkEdit               // Presents full screen
///
///     @presents(.sheet, detents: [.medium, .large])
///     case quickAction            // Sheet with configurable detents
/// }
/// ```
@attached(peer)
public macro presents(
    _ style: RoutePresentationStyle,
    detents: [RouteSheetDetent] = [.large],
    interactiveDismissDisabled: Bool = false
) = #externalMacro(module: "ArcheryMacros", type: "PresentsMacro")

/// Presentation styles for routes (used by @presents macro)
public enum RoutePresentationStyle: String, Sendable, Codable {
    case push
    case replace
    case sheet
    case fullScreen
    case popover
    case window
}

/// Sheet detent options for routes (used by @presents macro)
public enum RouteSheetDetent: String, Sendable, Codable, CaseIterable {
    case small
    case medium
    case large
}

// MARK: - Flow Navigation Macros

/// Defines a multi-step navigation flow.
///
/// Flows are wizard-like sequences with automatic step tracking,
/// back/forward navigation, and deep link support.
///
/// Example:
/// ```swift
/// @Flow(path: "onboarding", persists: true)
/// enum OnboardingFlow: NavigationFlow {
///     case welcome
///     case permissions
///     case accountSetup
///     case complete
///
///     @branch(replacing: .accountSetup, when: .hasExistingAccount)
///     case signIn
/// }
/// ```
@attached(extension, conformances: NavigationFlow, names: arbitrary)
public macro Flow(
    path: String,
    persists: Bool = false
) = #externalMacro(module: "ArcheryMacros", type: "FlowMacro")

/// Marks a flow step as a conditional branch.
/// When the condition is met, this step replaces the specified step.
@attached(peer)
public macro branch(
    replacing: Any,
    when condition: Any
) = #externalMacro(module: "ArcheryMacros", type: "FlowBranchMacro")

/// Marks a flow step as skippable when a condition is met.
@attached(peer)
public macro skip(
    when condition: Any
) = #externalMacro(module: "ArcheryMacros", type: "FlowSkipMacro")

// MARK: - Platform Scene Macros

/// Marks an enum as a scene for a separate window (macOS/iPadOS).
///
/// Usage:
/// ```swift
/// @AppShell
/// struct MyApp: App {
///     @Window(id: "preferences", title: "Preferences")
///     enum PreferencesScene {
///         case general
///         case accounts
///     }
/// }
/// ```
@attached(peer)
public macro Window(
    id: String,
    title: String? = nil
) = #externalMacro(module: "ArcheryMacros", type: "WindowSceneMacro")

#if os(visionOS)
/// Marks an enum as an immersive space scene (visionOS only).
///
/// Usage:
/// ```swift
/// @AppShell
/// struct MyApp: App {
///     @ImmersiveSpace(id: "viewer", style: .mixed)
///     enum ViewerSpace {
///         case model(id: String)
///     }
/// }
/// ```
@attached(peer)
public macro ImmersiveSpace(
    id: String,
    style: ImmersiveSpaceStyle = .mixed
) = #externalMacro(module: "ArcheryMacros", type: "ImmersiveSpaceMacro")

/// Style for immersive space presentation
public enum ImmersiveSpaceStyle: String, Sendable {
    case mixed
    case full
    case progressive
}
#endif

#if os(macOS)
/// Marks an enum as a settings scene (macOS only).
///
/// Usage:
/// ```swift
/// @AppShell
/// struct MyApp: App {
///     @Settings
///     enum AppSettings {
///         case general
///         case advanced
///     }
/// }
/// ```
@attached(peer)
public macro Settings() = #externalMacro(module: "ArcheryMacros", type: "SettingsSceneMacro")
#endif

#if canImport(AppIntents)
import AppIntents

/// Generates `typeDisplayRepresentation` and `displayRepresentation` for AppEntity.
/// User must add `: AppEntity` conformance and provide `defaultQuery`.
@attached(member)
@attached(extension, names: arbitrary)
public macro IntentEntity(
    displayName: String? = nil
) = #externalMacro(module: "ArcheryMacros", type: "IntentEntityMacro")

/// Generates `typeDisplayRepresentation` and `caseDisplayRepresentations` for AppEnum.
/// User must add `: AppEnum` conformance to their enum.
@attached(member, names: named(caseDisplayRepresentations))
@attached(extension, names: arbitrary)
public macro IntentEnum(
    displayName: String? = nil
) = #externalMacro(module: "ArcheryMacros", type: "IntentEnumMacro")
#endif

// Minimal handle for tests - renamed to avoid shadowing the module name
public struct ArcheryHandle { public init() {} }

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
