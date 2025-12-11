# Query Sources Design

## Overview

This document outlines the design for a modular, DI-friendly query source system that allows users to define network-coordinated queries co-located with their models and reference them via keypaths.

## Goals

1. **Modular Definitions** - Each model/domain defines its own query sources
2. **Co-location** - Query sources live near the models they query
3. **Clean Usage** - Use queries via keypath syntax: `@Query(\TaskSources.all)`
4. **DI-Friendly** - Inject dependencies per domain, swap for mocks in tests
5. **Type-Safe** - Full compile-time type checking
6. **Flexible** - Support parameterized queries

---

## User Experience

### 1. Define Query Sources Per Model

```swift
// Sources/MyApp/Models/Task/TaskSources.swift
// Co-located with Task model

@QuerySources
struct TaskSources {
    let api: TasksAPIProtocol

    var all: QuerySource<Task> {
        QuerySource(Task.all().order(by: .createdAt))
            .remote { try await api.fetchAll() }
            .cache(.staleWhileRevalidate(staleAfter: .minutes(5)))
    }

    var completed: QuerySource<Task> {
        QuerySource(Task.all().filter(Task.Columns.isCompleted == true))
            .remote { try await api.fetchCompleted() }
            .cache(.cacheFirst(ttl: .hours(1)))
    }

    var byPriority: (Int) -> QuerySource<Task> {
        { priority in
            QuerySource(Task.all().filter(Task.Columns.priority == priority))
                .remote { [api] in try await api.fetchByPriority(priority) }
                .cache(.staleWhileRevalidate(staleAfter: .minutes(10)))
        }
    }

    // Local-only query (no remote fetch needed)
    var recent: QuerySource<Task> {
        QuerySource(Task.all().order(by: .createdAt).limit(10))
    }
}
```

```swift
// Sources/MyApp/Models/User/UserSources.swift

@QuerySources
struct UserSources {
    let api: UsersAPIProtocol

    var all: QuerySource<User> {
        QuerySource(User.all())
            .remote { try await api.fetchAll() }
            .cache(.cacheFirst(ttl: .hours(1)))
    }

    var active: QuerySource<User> {
        QuerySource(User.all().filter(User.Columns.isActive == true))
            .remote { try await api.fetchActive() }
            .cache(.staleWhileRevalidate(staleAfter: .minutes(15)))
    }
}
```

```swift
// Sources/MyApp/Models/Project/ProjectSources.swift

@QuerySources
struct ProjectSources {
    let api: ProjectsAPIProtocol

    var active: QuerySource<Project> {
        QuerySource(Project.all().filter(Project.Columns.isArchived == false))
            .remote { try await api.fetchActive() }
            .cache(.staleWhileRevalidate(staleAfter: .minutes(10)))
    }
}
```

### 2. Inject at App Root (Each Domain Separately)

```swift
@main
struct MyApp: App {
    let database = try! PersistenceContainer.file(at: dbURL)

    var body: some Scene {
        WindowGroup {
            ContentView()
                // Database setup
                .databaseContainer(database)
                .enableQueryCoordination(container: database)
                // Inject each domain's sources
                .querySources(TaskSources(api: TasksAPI.live()))
                .querySources(UserSources(api: UsersAPI.live()))
                .querySources(ProjectSources(api: ProjectsAPI.live()))
        }
    }
}
```

### 3. Use in Views

```swift
struct TaskListView: View {
    @Query(\TaskSources.all)
    var tasks: [Task]

    @Query(\TaskSources.completed)
    var completed: [Task]

    var body: some View {
        List(tasks) { task in
            TaskRow(task: task)
        }
        .refreshable {
            await $tasks.refresh()
        }
        .overlay {
            if $tasks.isStale {
                Text("Data may be outdated")
            }
        }
    }
}

struct TeamView: View {
    @Query(\UserSources.active)
    var users: [User]

    @Query(\ProjectSources.active)
    var projects: [Project]

    var body: some View {
        // Mix queries from different sources
        VStack {
            UserList(users: users)
            ProjectList(projects: projects)
        }
    }
}
```

### 4. Parameterized Queries

```swift
struct PriorityTasksView: View {
    let priority: Int

    @Query(\TaskSources.byPriority, param: 1)
    var highPriority: [Task]

    var body: some View {
        List(highPriority) { task in
            TaskRow(task: task)
        }
    }
}
```

### 5. Testing

```swift
func testTaskListView() {
    // Create mock API
    let mockAPI = MockTasksAPI()
    mockAPI.tasksToReturn = [Task.sample]

    // Inject mock sources
    let view = TaskListView()
        .querySources(TaskSources(api: mockAPI))
        .databaseContainer(try! .inMemory())

    // Assert...
}

func testTeamView() {
    // Can inject only the sources needed for this test
    let view = TeamView()
        .querySources(UserSources(api: MockUsersAPI()))
        .querySources(ProjectSources(api: MockProjectsAPI()))
        .databaseContainer(try! .inMemory())

    // Assert...
}
```

### 6. Feature Modules

For modular apps, each feature module can define and inject its own sources:

```swift
// In TasksFeature module
public struct TasksFeature: View {
    let api: TasksAPIProtocol

    public var body: some View {
        TaskListView()
            .querySources(TaskSources(api: api))
    }
}

// In main app
TasksFeature(api: TasksAPI.live())
```

---

## Implementation Plan

### Phase 1: QuerySource Type

**File:** `Sources/Archery/Database/QuerySource.swift`

```swift
/// A complete query definition bundling local query, remote fetch, and cache policy
public struct QuerySource<Element: FetchableRecord & PersistableRecord & TableRecord & Sendable>: Sendable {
    public let request: QueryBuilder<Element>
    public let cachePolicy: QueryCachePolicy
    public let refreshAction: QueryRefreshAction<Element>?

    /// Create a local-only query source (no remote fetch)
    public init(_ request: QueryBuilder<Element>) {
        self.request = request
        self.cachePolicy = .localOnly
        self.refreshAction = nil
    }

    /// Add remote fetch capability (fluent)
    public func remote(
        merge: QueryMergeStrategy = .replace,
        fetch: @escaping @Sendable () async throws -> [Element]
    ) -> QuerySource<Element> {
        QuerySource(
            request: request,
            cachePolicy: cachePolicy,
            refreshAction: .fromAPI(fetch: fetch, merge: merge)
        )
    }

    /// Set cache policy (fluent)
    public func cache(_ policy: QueryCachePolicy) -> QuerySource<Element> {
        QuerySource(
            request: request,
            cachePolicy: policy,
            refreshAction: refreshAction
        )
    }

    // Internal full init
    internal init(
        request: QueryBuilder<Element>,
        cachePolicy: QueryCachePolicy,
        refreshAction: QueryRefreshAction<Element>?
    ) {
        self.request = request
        self.cachePolicy = cachePolicy
        self.refreshAction = refreshAction
    }
}
```

### Phase 2: QuerySourceProvider Protocol & Environment

**File:** `Sources/Archery/Database/QuerySourceProvider.swift`

```swift
import SwiftUI

/// Protocol for types that provide query sources
/// Conformance is generated by @QuerySources macro
public protocol QuerySourceProvider {}

/// Type-erased storage for query source providers
@MainActor
public final class QuerySourceRegistry: ObservableObject {
    public static let shared = QuerySourceRegistry()

    private var providers: [ObjectIdentifier: Any] = [:]

    public func register<P: QuerySourceProvider>(_ provider: P) {
        providers[ObjectIdentifier(P.self)] = provider
    }

    public func resolve<P: QuerySourceProvider>(_ type: P.Type) -> P? {
        providers[ObjectIdentifier(P.self)] as? P
    }
}

/// Environment key for the registry
private struct QuerySourceRegistryKey: EnvironmentKey {
    static let defaultValue = QuerySourceRegistry.shared
}

public extension EnvironmentValues {
    var querySourceRegistry: QuerySourceRegistry {
        get { self[QuerySourceRegistryKey.self] }
        set { self[QuerySourceRegistryKey.self] = newValue }
    }
}

/// View modifier for injecting query sources
public extension View {
    func querySources<P: QuerySourceProvider>(_ provider: P) -> some View {
        modifier(QuerySourcesModifier(provider: provider))
    }
}

struct QuerySourcesModifier<P: QuerySourceProvider>: ViewModifier {
    let provider: P
    @Environment(\.querySourceRegistry) private var registry

    func body(content: Content) -> some View {
        content
            .onAppear {
                registry.register(provider)
            }
    }
}
```

### Phase 3: @Query Keypath Initializers

**File:** `Sources/Archery/Database/Query.swift` (additions)

```swift
extension Query {
    /// Create a query from a keypath to a QuerySource on a provider
    public init<Provider: QuerySourceProvider>(
        _ keyPath: KeyPath<Provider, QuerySource<Element>>
    ) where Element: PersistableRecord {
        self.init(keyPathSource: .provider(keyPath))
    }

    /// Create a query from a parameterized keypath
    public init<Provider: QuerySourceProvider, Param>(
        _ keyPath: KeyPath<Provider, (Param) -> QuerySource<Element>>,
        param: Param
    ) where Element: PersistableRecord, Param: Sendable {
        self.init(keyPathSource: .parameterized(keyPath, param))
    }
}

// Internal storage for keypath-based sources
enum QueryKeyPathSource<Element: FetchableRecord & TableRecord & Sendable>: @unchecked Sendable {
    case direct(QuerySource<Element>)
    case provider(AnyKeyPath, resolve: @MainActor (QuerySourceRegistry) -> QuerySource<Element>?)
    case parameterized(AnyKeyPath, param: Any, resolve: @MainActor (QuerySourceRegistry) -> QuerySource<Element>?)
}
```

### Phase 4: @QuerySources Macro

**File:** `Sources/ArcheryMacros/QuerySourcesMacro.swift`

The macro adds `QuerySourceProvider` conformance:

```swift
// Input:
@QuerySources
struct TaskSources {
    let api: TasksAPIProtocol
    var all: QuerySource<Task> { ... }
}

// Output:
struct TaskSources: QuerySourceProvider {
    let api: TasksAPIProtocol
    var all: QuerySource<Task> { ... }
}
```

**Macro declaration in Archery.swift:**

```swift
/// Marks a type as a query source provider.
/// Use with structs that define QuerySource properties for a specific model/domain.
///
/// Example:
/// ```swift
/// @QuerySources
/// struct TaskSources {
///     let api: TasksAPIProtocol
///
///     var all: QuerySource<Task> {
///         QuerySource(Task.all())
///             .remote { try await api.fetchAll() }
///             .cache(.staleWhileRevalidate(staleAfter: .minutes(5)))
///     }
/// }
/// ```
@attached(extension, conformances: QuerySourceProvider)
public macro QuerySources() = #externalMacro(module: "ArcheryMacros", type: "QuerySourcesMacro")
```

---

## Files to Create/Modify

### New Files

| File | Purpose |
|------|---------|
| `Sources/Archery/Database/QuerySource.swift` | QuerySource type with fluent builder |
| `Sources/Archery/Database/QuerySourceProvider.swift` | Protocol + registry + environment |
| `Sources/ArcheryMacros/QuerySourcesMacro.swift` | @QuerySources macro implementation |

### Modified Files

| File | Changes |
|------|---------|
| `Sources/Archery/Database/Query.swift` | Add keypath-based initializers |
| `Sources/Archery/Archery.swift` | Add @QuerySources macro declaration |

### Showcase Files

| File | Purpose |
|------|---------|
| `ArcheryShowcase/Core/Persistence/QuerySourcesShowcase.swift` | Demo of the full pattern |

---

## Implementation Order

1. **`QuerySource<Element>`** - Fluent builder type
2. **`QuerySourceProvider` protocol** - Protocol + registry + environment
3. **`@Query` keypath inits** - Resolve sources from registry
4. **`@QuerySources` macro** - Generate protocol conformance
5. **Showcase + tests** - Demo and validate

---

## Directory Structure Example

```
Sources/MyApp/
├── Models/
│   ├── Task/
│   │   ├── Task.swift           # @Persistable model
│   │   ├── TaskSources.swift    # @QuerySources for Task
│   │   └── TasksAPI.swift       # @APIClient for Task
│   ├── User/
│   │   ├── User.swift
│   │   ├── UserSources.swift
│   │   └── UsersAPI.swift
│   └── Project/
│       ├── Project.swift
│       ├── ProjectSources.swift
│       └── ProjectsAPI.swift
├── Features/
│   ├── TaskList/
│   │   └── TaskListView.swift   # Uses @Query(\TaskSources.all)
│   └── Team/
│       └── TeamView.swift       # Uses @Query(\UserSources.active)
└── App/
    └── MyApp.swift              # Injects all sources
```

---

## Benefits of Modular Approach

| Aspect | Centralized (❌) | Modular (✅) |
|--------|------------------|--------------|
| **File size** | One giant file | Small focused files |
| **Discoverability** | Hunt through AppQueries | Find next to model |
| **Dependencies** | All APIs injected together | Each domain independent |
| **Testing** | Must mock everything | Mock only what you need |
| **Team collaboration** | Merge conflicts | Independent work |
| **Feature modules** | Tight coupling | Each module owns its queries |

---

## Migration from Direct @Query

**Before (verbose, not reusable):**
```swift
@Query(
    Task.all().order(by: .createdAt),
    cachePolicy: .staleWhileRevalidate(staleAfter: .minutes(5)),
    refresh: .fromAPI { try await api.fetchTasks() }
)
var tasks: [Task]
```

**After (clean, reusable):**
```swift
@Query(\TaskSources.all)
var tasks: [Task]
```

The direct API still works for one-off queries that don't need reuse.
