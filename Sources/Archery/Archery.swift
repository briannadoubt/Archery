import Foundation
#if canImport(Observation)
@_exported import Observation
#endif
// Runtime shims and macro declarations for Archery.

// MARK: - Navigation & Errors
public protocol NavigationRoute: Hashable, Sendable, NavigationSerializable {}

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

/// Marks a type as a query source provider.
///
/// Use with structs that define QuerySource properties for a specific model/domain.
/// This macro adds conformance to `QuerySourceProvider` protocol.
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
/// }
/// ```
///
/// Then inject at app root:
/// ```swift
/// ContentView()
///     .querySources(TaskSources(api: TasksAPI.live()))
/// ```
///
/// And use in views:
/// ```swift
/// @Query(\TaskSources.all)
/// var tasks: [Task]
/// ```
@attached(extension, conformances: QuerySourceProvider)
public macro QuerySources() = #externalMacro(module: "ArcheryMacros", type: "QuerySourcesMacro")

@attached(member, names: arbitrary)
@attached(memberAttribute)
@attached(extension, conformances: Observation.Observable, ArcheryLoadable)
public macro ObservableViewModel() = #externalMacro(module: "ArcheryMacros", type: "ObservableViewModelMacro")

@attached(member, names: arbitrary)
public macro ViewModelBound<V>() = #externalMacro(module: "ArcheryMacros", type: "ViewModelBoundMacro")

@attached(member, names: arbitrary)
public macro AppShell() = #externalMacro(module: "ArcheryMacros", type: "AppShellMacro")

/// @AppShell with database schema - generates GeneratedAppDatabase with migrations
/// for the specified @Persistable types.
///
/// Example:
/// ```swift
/// @AppShell(schema: [TaskItem.self, Project.self])
/// @main
/// struct MyApp: App {
///     enum Tab: CaseIterable { case home, settings }
/// }
/// ```
///
/// Note: AppShortcutsProvider cannot be macro-generated due to AppIntents metadata
/// processor limitations. Create a separate file with your AppShortcutsProvider.
@attached(member, names: arbitrary)
public macro AppShell(schema: [any AutoMigrating.Type]) = #externalMacro(module: "ArcheryMacros", type: "AppShellMacro")

/// Generates database conformances and optionally full App Intents integration.
///
/// All protocol conformances are auto-generated - no need to declare them manually.
///
/// Basic Example (database only):
/// ```swift
/// @Persistable(table: "players")
/// struct Player {
///     var id: Int64
///     var name: String
///     var score: Int
/// }
/// // Generates: Codable, Identifiable, Hashable, FetchableRecord, PersistableRecord, AutoMigrating
/// ```
///
/// Full Example (database + App Intents):
/// ```swift
/// @Persistable(table: "tasks", displayName: "Task", titleProperty: "title")
/// struct TaskItem: Codable, Identifiable, Hashable, FetchableRecord, PersistableRecord, AppEntity {
///     var id: String
///     var title: String
///     var status: TaskStatus
/// }
/// // Generates EntityQuery, CreateIntent, ListIntent, DeleteIntent
/// // Note: All conformances must be on struct when using AppEntity (Swift 6 actor isolation)
/// ```
///
/// Generates members:
/// - `Columns` enum with type-safe column references
/// - `databaseTableName` static property
/// - `createTableMigration` for automatic schema migration
/// - When `displayName` provided: AppEntity members + nested intents
///
/// Generates conformances via extension (when AppEntity not declared on struct):
/// - `Codable`, `Identifiable`, `Hashable`, `FetchableRecord`, `PersistableRecord`, `AutoMigrating`
/// - Based on properties: `HasTimestamps`, `HasCreatedAt`, `HasUpdatedAt`
///
/// Note: When using Swift 6 with MainActor default isolation, all conformances
/// must be declared on the struct to avoid actor isolation conflicts.
@attached(member, names: named(Columns), named(databaseTableName), named(createTableMigration), arbitrary)
@attached(extension, conformances: Codable, Identifiable, Hashable, FetchableRecord, PersistableRecord, AutoMigrating, HasTimestamps, HasCreatedAt, HasUpdatedAt)
public macro Persistable(
    table: String? = nil,
    primaryKey: String = "id",
    displayName: String? = nil,
    titleProperty: String = "title",
    intents: Bool = true
) = #externalMacro(module: "ArcheryMacros", type: "PersistableMacro")

/// Generates a repository pattern for the database with protocol, live, and mock implementations.
///
/// Example:
/// ```swift
/// @DatabaseRepository(record: Player.self)
/// class PlayerStore {
///     func topScorers(limit: Int) async throws -> [Player] {
///         try await db.read { db in
///             try Player.order(Player.Columns.score.desc).limit(limit).fetchAll(db)
///         }
///     }
/// }
/// ```
@attached(peer, names: suffixed(Protocol), suffixed(Live), prefixed(Mock))
public macro DatabaseRepository<T>(
    record: T.Type,
    tracing: Bool = false
) = #externalMacro(module: "ArcheryMacros", type: "DatabaseRepositoryMacro")

@attached(peer, names: suffixed(Protocol), suffixed(Live), prefixed(Mock))
public macro APIClient() = #externalMacro(module: "ArcheryMacros", type: "APIClientMacro")

@attached(peer)
public macro Cache(
    enabled: Bool = true,
    ttl: Duration? = nil
) = #externalMacro(module: "ArcheryMacros", type: "CacheMacro")

@attached(member, names: arbitrary)
@attached(extension, conformances: LocalizationKey)
public macro Localizable() = #externalMacro(module: "ArcheryMacros", type: "LocalizableMacro")

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

/// Overload for window presentation with ID
@attached(peer)
public macro presents(
    _ style: RoutePresentationStyle,
    id: String,
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

/// Generates `typeDisplayRepresentation` and `caseDisplayRepresentations` for AppEnum.
/// User must add `: AppEnum` conformance to their enum.
@attached(member, names: named(caseDisplayRepresentations))
@attached(extension, names: arbitrary)
public macro IntentEnum(
    displayName: String? = nil
) = #externalMacro(module: "ArcheryMacros", type: "IntentEnumMacro")
#endif

// MARK: - Schema Attribute Macros for @Persistable

/// Marks a property as the primary key for the database table.
/// If not specified, @Persistable assumes a property named "id" is the primary key.
///
/// Example:
/// ```swift
/// @Persistable(table: "players")
/// struct Player: Codable, FetchableRecord, PersistableRecord {
///     @PrimaryKey var playerId: String  // Custom primary key
///     var name: String
/// }
/// ```
@attached(peer)
public macro PrimaryKey() = #externalMacro(module: "ArcheryMacros", type: "PrimaryKeyMacro")

/// Marks a property to have a database index created for faster queries.
/// Use on columns frequently used in WHERE clauses or sorting.
///
/// Example:
/// ```swift
/// @Persistable(table: "tasks")
/// struct Task: Codable, FetchableRecord, PersistableRecord {
///     var id: String
///     @Indexed var status: TaskStatus      // Index on status column
///     @Indexed var projectId: String?      // Index on foreign key
/// }
/// ```
@attached(peer)
public macro Indexed() = #externalMacro(module: "ArcheryMacros", type: "IndexedMacro")

/// Marks a property as having a unique constraint in the database.
/// Optionally takes a group name for composite unique constraints.
///
/// Example:
/// ```swift
/// @Persistable(table: "users")
/// struct User: Codable, FetchableRecord, PersistableRecord {
///     var id: String
///     @Unique var email: String           // Unique email
///     @Unique("org_name") var orgId: String  // Composite unique
///     @Unique("org_name") var username: String
/// }
/// ```
@attached(peer)
public macro Unique(_ group: String? = nil) = #externalMacro(module: "ArcheryMacros", type: "UniqueMacro")

/// Marks a property as a foreign key reference to another @Persistable type.
/// The referenced table name is inferred from the type's databaseTableName.
///
/// Example:
/// ```swift
/// @Persistable(table: "tasks")
/// struct Task: Codable, FetchableRecord, PersistableRecord {
///     var id: String
///     @ForeignKey(Project.self) var projectId: String?  // References projects table
/// }
/// ```
@attached(peer)
public macro ForeignKey<T>(_ type: T.Type) = #externalMacro(module: "ArcheryMacros", type: "ForeignKeyMacro")

/// Marks a Date property to be auto-set to the current date on record insertion.
/// The property should be of type Date (not optional).
///
/// Example:
/// ```swift
/// @Persistable(table: "posts")
/// struct Post: Codable, FetchableRecord, PersistableRecord {
///     var id: String
///     var title: String
///     @CreatedAt var createdAt: Date  // Auto-set on insert
/// }
/// ```
@attached(peer)
public macro CreatedAt() = #externalMacro(module: "ArcheryMacros", type: "CreatedAtMacro")

/// Marks a Date property to be auto-updated to the current date on record update.
/// The property should be of type Date (not optional).
///
/// Example:
/// ```swift
/// @Persistable(table: "posts")
/// struct Post: Codable, FetchableRecord, PersistableRecord {
///     var id: String
///     var title: String
///     @CreatedAt var createdAt: Date
///     @UpdatedAt var updatedAt: Date  // Auto-updated on save
/// }
/// ```
@attached(peer)
public macro UpdatedAt() = #externalMacro(module: "ArcheryMacros", type: "UpdatedAtMacro")

/// Marks a property as transient - it will not be persisted to the database.
/// The property will be excluded from the Columns enum and migration generation.
///
/// Example:
/// ```swift
/// @Persistable(table: "items")
/// struct Item: Codable, FetchableRecord, PersistableRecord {
///     var id: String
///     var name: String
///     @NotPersisted var isSelected: Bool = false  // UI state, not persisted
/// }
/// ```
@attached(peer)
public macro NotPersisted() = #externalMacro(module: "ArcheryMacros", type: "NotPersistedMacro")

/// Marks a property to have a default value in the database schema.
/// This ensures new rows have this value when the column is not specified.
///
/// Example:
/// ```swift
/// @Persistable(table: "tasks")
/// struct Task: Codable, FetchableRecord, PersistableRecord {
///     var id: String
///     var title: String
///     @Default("todo") var status: String
///     @Default(0) var priority: Int
/// }
/// ```
@attached(peer)
public macro Default(_ value: Any) = #externalMacro(module: "ArcheryMacros", type: "DefaultMacro")

/// Explicitly sets the SQLite column type for a property.
/// Use this for enums or custom types where the macro can't infer the correct type.
///
/// Usage:
/// ```swift
/// @Persistable(table: "tasks")
/// struct Task: Codable, FetchableRecord, PersistableRecord {
///     var id: String
///     @ColumnType(.integer)
///     var priority: TaskPriority  // Int-backed enum stored as INTEGER
///     @ColumnType(.text)
///     var status: TaskStatus      // String-backed enum stored as TEXT
/// }
/// ```
///
/// Available types: `.text`, `.integer`, `.double`, `.blob`, `.datetime`
@attached(peer)
public macro ColumnType(_ type: SQLiteColumnType) = #externalMacro(module: "ArcheryMacros", type: "ColumnTypeMacro")

/// SQLite column types for use with @ColumnType
public enum SQLiteColumnType: String {
    case text
    case integer
    case double
    case blob
    case datetime
}

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
