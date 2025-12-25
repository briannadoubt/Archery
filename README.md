# Archery

A production-ready, macro-first SwiftUI architecture framework that eliminates boilerplate while maintaining strong typing, dependency injection, and comprehensive testing across all Apple platforms.

## Features

### Core Architecture
- **Swift Macros**: Generate boilerplate code automatically while keeping it readable and debuggable
- **Dependency Injection**: Built-in DI container with auto-registration and manual opt-outs
- **Type Safety**: Strongly typed navigation, routes, and data flow throughout
- **Testing First**: Mandatory snapshot tests, navigation validation, and UI smoke tests

### Platform Support
- iOS, iPadOS
- macOS, Mac Catalyst
- watchOS, visionOS
- Minimum SDK: v26, Swift 6.2, Xcode 26

## Quick Start

### Installation

Add Archery to your Swift package:

```swift
dependencies: [
    .package(url: "https://github.com/briannadoubt/Archery.git", from: "1.0.0")
]
```

### Basic Usage

#### 1. Define a Persistable Model

```swift
@Persistable(table: "tasks", displayName: "Task", titleProperty: "title")
struct TaskItem: Codable, Identifiable, FetchableRecord, PersistableRecord {
    var id: String
    var title: String
    @Indexed var status: TaskStatus
    @CreatedAt var createdAt: Date
    @UpdatedAt var updatedAt: Date
}
```

#### 2. Create Query Sources

```swift
extension TaskItem: HasQuerySources {
    @QuerySources
    struct Sources {
        let api: TasksAPIProtocol

        var all: QuerySource<TaskItem> {
            QuerySource(TaskItem.all().order(by: .createdAt))
                .remote { try await api.fetchAll() }
                .cache(.staleWhileRevalidate(staleAfter: .minutes(5)))
        }

        var completed: QuerySource<TaskItem> {
            QuerySource(TaskItem.all().filter(TaskItem.Columns.status == .done))
                .remote { try await api.fetchCompleted() }
        }
    }
}
```

#### 3. Use @Query in Views

```swift
struct TaskListView: View {
    // Shorthand syntax with type inference
    @Query(\.all)
    var tasks: [TaskItem]

    var body: some View {
        List(tasks) { task in
            TaskRow(task: task)
        }
        .refreshable {
            await $tasks.refresh()
        }
    }
}
```

#### 4. Edit Records with @QueryOne

```swift
struct TaskEditView: View {
    @QueryOne var task: TaskItem?

    init(taskId: String) {
        _task = QueryOne(TaskItem.find(taskId))
    }

    var body: some View {
        if task != nil {
            Form {
                TextField("Title", text: $task.title.or(""))
                Button("Save") { Task { try? await $task.save() } }
            }
            .disabled(!$task.isDirty)
        }
    }
}
```

#### 5. Create an API Client

```swift
@APIClient
class TasksAPI {
    func fetchAll() async throws -> [TaskItem] { ... }
    func fetchCompleted() async throws -> [TaskItem] { ... }

    @Cache(ttl: .minutes(10))
    func getTask(id: String) async throws -> TaskItem { ... }
}
// Generates: TasksAPIProtocol, TasksAPILive, MockTasksAPI
```

#### 6. Define a View Model

```swift
@ObservableViewModel
@MainActor
class TaskListViewModel: Resettable {
    var loadState: LoadState<[TaskItem]> = .idle

    let api: TasksAPIProtocol

    init(api: TasksAPIProtocol) {
        self.api = api
    }

    func load() async {
        loadState = .loading
        do {
            let tasks = try await api.fetchAll()
            loadState = .success(tasks)
        } catch {
            loadState = .failure(error)
        }
    }

    func reset() {
        loadState = .idle
    }
}
```

#### 7. Setup App Shell

```swift
@AppShell(schema: [TaskItem.self, Project.self])
@main
struct MyApp: App {
    enum Tab: CaseIterable {
        case tasks
        case settings
    }
}
```

## Core Macros

### Data & Persistence

| Macro | Description |
|-------|-------------|
| `@Persistable` | Generates GRDB conformances, column enums, migrations, and optional App Intents |
| `@QuerySources` | Defines query source providers with local + remote data coordination |
| `@KeyValueStore` | Codable-backed async/throwing get/set with namespaced keys and migrations |
| `@DatabaseRepository` | Repository pattern with protocol + live/mock implementations |

### Schema Attributes (for @Persistable)

| Macro | Description |
|-------|-------------|
| `@PrimaryKey` | Marks custom primary key column |
| `@Indexed` | Creates database index for faster queries |
| `@Unique` | Adds unique constraint (supports composite groups) |
| `@ForeignKey` | Defines foreign key reference |
| `@CreatedAt` | Auto-set timestamp on insert |
| `@UpdatedAt` | Auto-update timestamp on save |
| `@NotPersisted` | Excludes property from database |
| `@Default` | Sets default value in schema |
| `@ColumnType` | Explicit SQLite column type |

### Networking

| Macro | Description |
|-------|-------------|
| `@APIClient` | Async/await networking with retry, caching, and error normalization |
| `@Cache` | Per-endpoint cache policy override |

### ViewModels & Views

| Macro | Description |
|-------|-------------|
| `@ObservableViewModel` | MainActor-bound ViewModels with lifecycle management and auto-cancellation |
| `@ViewModelBound` | DI-aware View binding with automatic ViewModel injection |

### Navigation & Routing

| Macro | Description |
|-------|-------------|
| `@AppShell` | Root navigation structure with TabView + NavigationStacks |
| `@Route` | Typed deep-link router with URL pattern matching |
| `@Flow` | Multi-step wizard navigation with branching |
| `@presents` | Presentation style per route (sheet, fullScreen, popover, window) |

### Entitlement Gating

| Macro | Description |
|-------|-------------|
| `@requires` | Route requires specific entitlement |
| `@requiresAny` | Route requires any of specified entitlements (OR) |
| `@requiresAll` | Route requires all specified entitlements (AND) |
| `@Entitled` | ViewModel entitlement requirement |

### Platform Scenes

| Macro | Description |
|-------|-------------|
| `@Window` | Separate window scene (macOS/iPadOS) |
| `@ImmersiveSpace` | Immersive space scene (visionOS) |
| `@Settings` | Settings scene (macOS) |

### App Intents

| Macro | Description |
|-------|-------------|
| `@IntentEnum` | Generates AppEnum conformance with display representations |

### Analytics & Feature Flags

| Macro | Description |
|-------|-------------|
| `@AnalyticsEvent` | Event schema with compile-time checking and provider adapters |
| `@FeatureFlag` | Feature flag wrapper with local overrides |

### Forms & Validation

| Macro | Description |
|-------|-------------|
| `@Form` | Form model with field definitions and validation rules |

### Design System

| Macro | Description |
|-------|-------------|
| `@DesignTokens` | Colors/typography/spacing from Figma/Style Dictionary |
| `@Localizable` | String extraction with pseudo-localization support |

## Property Wrappers

| Wrapper | Description |
|---------|-------------|
| `@Query` | Observe multiple database records with optional network coordination |
| `@QueryOne` | Observe and edit a single record with change tracking |
| `@QueryCount` | Observe record counts |

## Runtime Types

| Type | Description |
|------|-------------|
| `EnvContainer` | Lightweight DI container for registration/lookup |
| `LoadState<T>` | Shared UI state: idle, loading, success, failure |
| `AlertState` | Standardized alert presentation |
| `CancelableTask` | Task cancellation handle |
| `AppError` | Normalized error with user-facing messaging |

## Architecture Principles

### 1. Macro-First Development
- Reduce boilerplate through code generation
- Keep generated code readable and debuggable
- Support incremental adoption

### 2. Strong Typing
- Type-safe navigation and routing
- Compile-time validation of dependencies
- No stringly-typed APIs

### 3. Testing Excellence
- Mandatory snapshot tests for all macros
- Navigation graph validation
- Automated accessibility checks
- Performance budget enforcement

### 4. Security & Privacy
- Mandatory PII redaction in logs
- Secure storage for secrets
- CI-integrated secret scanning

## Project Structure

```
Archery/
├── Sources/
│   ├── Archery/              # Runtime library
│   │   ├── Analytics/        # Analytics & error tracking
│   │   ├── Auth/             # Authentication & security
│   │   ├── Background/       # Background task scheduling
│   │   ├── Benchmarking/     # Performance benchmarks
│   │   ├── Configuration/    # Hierarchical config
│   │   ├── Database/         # GRDB integration, Query, migrations
│   │   ├── Documentation/    # Doc generation
│   │   ├── E2ETesting/       # UI test utilities
│   │   ├── FeatureFlags/     # Feature flag system
│   │   ├── Forms/            # Form validation
│   │   ├── Intents/          # App Intents support
│   │   ├── Interop/          # UIKit/AppKit bridges
│   │   ├── LiveActivity/     # Live Activities
│   │   ├── Modularity/       # Module system & CI
│   │   ├── Monetization/     # StoreKit 2, paywalls
│   │   ├── Navigation/       # Navigation coordination
│   │   ├── Observability/    # Telemetry & metrics
│   │   ├── Offline/          # Offline cache & sync
│   │   ├── Performance/      # Memory & view tracking
│   │   ├── Release/          # Changelog generation
│   │   └── Security/         # Secure logging
│   └── ArcheryMacros/        # Macro implementations
├── Tests/                    # Test suites
└── ArcheryShowcase/          # Sample application
```

## Performance Targets

- **Cold Start**: <300ms on baseline A-series chips
- **Frame Rate**: Consistent 60fps (<16ms per frame)
- **Memory**: <150MB for typical CRUD applications
- **Build Time**: Incremental builds with macro caching

## Implementation Status

### Complete

| Section | Status |
|---------|--------|
| KeyValueStore | Done |
| APIClient + Query | Done |
| ObservableViewModel | Done |
| ViewModelBound | Done |
| AppShell | Done |
| Tooling & DX | Done |
| Runtime Glue (EnvContainer + DI) | Done |
| Networking & Errors | Done |
| Persistence (GRDB) | Done |
| Navigation & Deep Links | Done |
| Design System & Theming | Done |
| Accessibility & Localization | Done |
| Widgets, Intents, Background | Done |
| Analytics & Feature Flags | Done |
| Testing & CI | Done |
| Performance & Stability | Done |
| Documentation & Examples | Done |
| Auth & Security | Done |
| Offline & Sync | Done |
| Forms & Validation | Done |
| Modularity & Build | Done |
| Interop | Done |
| Observability Ops | Done |
| Configuration & Environments | Done |
| Monetization | Done |
| End-to-End & Fuzz Testing | Done |
| Benchmarking | Done |

### In Progress

| Section | Status |
|---------|--------|
| Release & Migration | Planned |
| Full App Generation | Planned |
| Branding & White-Label | Planned |
| Compliance & Privacy | Planned |
| Developer Portal | Planned |

## Documentation

- [Architecture Overview](ARCHITECTURE.md)
- [Upgrade Plan](UPGRADE_PLAN.md)

## Contributing

We welcome contributions! Please see our [Contributing Guide](CONTRIBUTING.md) for details.

### Development Setup

```bash
# Clone the repository
git clone https://github.com/briannadoubt/Archery.git

# Run tests
swift test

# Build the package
swift build
```

## License

Apache-2.0 - See [LICENSE](LICENSE) for details.

## Support

- **Issues**: [GitHub Issues](https://github.com/briannadoubt/Archery/issues)
- **Discussions**: [GitHub Discussions](https://github.com/briannadoubt/Archery/discussions)
