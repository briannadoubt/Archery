# Archery Macro & Property Wrapper Coverage

This document tracks which macros and property wrappers are actively used in the ArcheryShowcase app.

## Summary

| Status | Count |
|--------|-------|
| ✅ Used in Showcase | 29 |
| ⚠️ Defined but Not Used | 3 |
| 🗑️ Deleted | 2 |

---

## Macros

### ✅ Actively Used

| Macro | Location in Showcase | Purpose |
|-------|---------------------|---------|
| `@KeyValueStore` | `Stores.swift` | Generates typed key-value storage with Codable persistence |
| `@ObservableViewModel` | - | (Used indirectly via ViewModelBound pattern) |
| `@ViewModelBound` | `ViewModelBoundDemo.swift` | DI-aware View binding with automatic ViewModel injection |
| `@AppShell` | `ArcheryShowcaseApp.swift` | Generates TabView navigation shell with deep linking |
| `@Persistable` | `AppDatabase.swift`, `DatabaseShowcase.swift` | Generates GRDB Columns enum and table name |
| `@DatabaseRepository` | `DatabaseShowcase.swift` | Generates repository protocol + live/mock implementations |
| `@APIClient` | `NetworkingShowcase.swift` | Generates async networking client with retry/caching |
| `@Cache` | `NetworkingShowcase.swift` | Marks API methods for response caching |
| `@DesignTokens` | `DesignTokensShowcase.swift` | Generates design system tokens from JSON |
| `@Localizable` | `AdvancedMacroShowcase.swift` | Generates localization key helpers |
| `@AnalyticsEvent` | `AdvancedMacroShowcase.swift` | Generates type-safe analytics with PII redaction |
| `@Route` | `Routes.swift` | Generates URL pattern matching for navigation |
| `@requires` | `Routes.swift` | Gates route access by entitlement |
| `@requiresAny` | `Routes.swift` | Gates access requiring ANY of listed entitlements |
| `@requiresAll` | `Routes.swift` | Gates access requiring ALL listed entitlements |
| `@presents` | `Routes.swift` | Specifies route presentation style (sheet/fullScreen) |
| `@Flow` | `ArcheryShowcaseApp.swift`, `FlowDemo.swift` | Defines multi-step wizard navigation flows |
| `@branch` | `FlowDemo.swift` | Conditional flow step replacement |
| `@skip` | `FlowDemo.swift` | Conditional flow step skipping |
| `@IntentEnum` | `Models.swift` | Generates AppEnum conformance for App Intents |
| `@QuerySources` | `AppDatabase.swift` | Marks a struct as a query source provider |
| `@SharedModel` | `AppDatabase.swift` | Generates complete App Intents ecosystem (EntityQuery, CRUD intents, Shortcuts) |
| `@Entitled` | `EntitledShowcase.swift` | Gates ViewModel by single entitlement |
| `@EntitledAny` | `EntitledShowcase.swift` | Gates ViewModel (OR logic - any entitlement) |
| `@EntitledAll` | `EntitledShowcase.swift` | Gates ViewModel (AND logic - all entitlements) |
| `@FeatureFlag` | `FeatureFlagShowcase.swift` | Generates nested flag types from enum cases |

### ⚠️ Defined but Not Used in Showcase

| Macro | Purpose | Notes |
|-------|---------|-------|
| `@Window` | Marks enum as window scene (macOS/iPadOS) | Platform-specific |
| `@ImmersiveSpace` | Marks enum as immersive space (visionOS) | Platform-specific |
| `@Settings` | Marks enum as settings scene (macOS) | Platform-specific |

### 🗑️ Deleted Macros

| Macro | Replacement | Notes |
|-------|-------------|-------|
| `@IntentEntity` | `@SharedModel` | Superseded - `@SharedModel` generates full App Intents ecosystem |
| `@GRDBRepository` | `@DatabaseRepository` | Renamed for clarity |

---

## Property Wrappers

### ✅ Actively Used

| Wrapper | Location in Showcase | Purpose |
|---------|---------------------|---------|
| `@Query` | `DashboardView.swift`, `TaskListView.swift`, `DatabaseShowcase.swift` | Reactive observation of database arrays |
| `@QueryOne` | `TaskEditView.swift` | Single record observation with editing support |
| `@QueryCount` | `DatabaseShowcase.swift` | Reactive count observation |
| `@Editable` | - | Edit existing record (no fetch) |

### 🗑️ Deleted

| Wrapper | Replacement | Notes |
|---------|-------------|-------|
| `@EditableQuery` | `@QueryOne` | Redundant - `@QueryOne` now includes editing support |

---

## Property Wrapper API Reference

### `@Query` - Array Observation
```swift
@Query(TaskItem.all()) var tasks: [TaskItem]
@Query(\.all) var tasks: [TaskItem]  // Keypath syntax with @QuerySources
```

### `@QueryOne` - Single Record with Editing
```swift
@QueryOne var task: TaskItem?

init(taskId: String) {
    _task = QueryOne(TaskItem.find(taskId))
}

// Read
task?.title

// Edit via bindings
$task.title      // Binding<String>?
$task.status     // Binding<TaskStatus>?

// Operations
$task.save()     // persist changes
$task.reset()    // discard edits
$task.delete()   // remove record
$task.isDirty    // has unsaved changes
```

### `@QueryCount` - Count Observation
```swift
@QueryCount(Player.count()) var playerCount: Int
```

### `@Editable` - Edit Existing Record
```swift
@Editable var task: TaskItem = existingTask

$task.title      // Binding<String>
$task.save()     // persist
$task.isDirty    // has changes
```

---

## Macro API Reference

### `@SharedModel` - Complete App Intents Ecosystem

Generates EntityQuery, CRUD intents, and optionally AppShortcutsProvider for a Persistable model.

```swift
@SharedModel(displayName: "Task", titleProperty: "title", shortcuts: false)
@Persistable(table: "tasks")
struct TaskItem: Codable, Identifiable, Hashable, Sendable, FetchableRecord, PersistableRecord {
    var id: String
    var title: String
    var status: TaskStatus
    // ...
}
```

**Parameters:**
- `displayName`: Human-readable name for Siri/Shortcuts (default: derived from type name)
- `titleProperty`: Property to use for display representation (default: `"title"`)
- `intents`: Generate CRUD intents (default: `true`)
- `shortcuts`: Generate AppShortcutsProvider (default: `true`, set `false` if app has existing shortcuts)

**Generated:**
- `TaskItem.EntityQuery` - Fetches entities from database for App Intents
- `TaskItem.CreateIntent` - Creates new records via Siri/Shortcuts
- `TaskItem.ListIntent` - Lists records via Siri/Shortcuts
- `TaskItem.DeleteIntent` - Deletes records via Siri/Shortcuts
- `TaskItem.Shortcuts` - AppShortcutsProvider with Siri phrases (if `shortcuts: true`)

**Requirements:**
- Model must have `PersistenceContainer.current` set at app startup
- Model must conform to `FetchableRecord` and `PersistableRecord`

---

## Files by Feature

### Navigation & Routing
- `Routes.swift` - `@Route`, `@requires`, `@presents`
- `FlowDemo.swift` - `@Flow`, `@branch`, `@skip`
- `ArcheryShowcaseApp.swift` - `@AppShell`, `@Flow`

### Database & Persistence
- `AppDatabase.swift` - `@Persistable`, `@QuerySources`, `@SharedModel`
- `DatabaseShowcase.swift` - `@Persistable`, `@DatabaseRepository`
- `TaskEditView.swift` - `@QueryOne`
- `TaskListView.swift` - `@Query`
- `DashboardView.swift` - `@Query`

### Networking
- `NetworkingShowcase.swift` - `@APIClient`, `@Cache`
- `NetworkCoordinatedQueryShowcase.swift` - `@Query` with cache policies

### App Infrastructure
- `Stores.swift` - `@KeyValueStore`
- `DesignTokensShowcase.swift` - `@DesignTokens`
- `AdvancedMacroShowcase.swift` - `@Localizable`, `@AnalyticsEvent`
- `FeatureFlagShowcase.swift` - `@FeatureFlag`

### Entitlements & Access Control
- `EntitledShowcase.swift` - `@Entitled`, `@EntitledAny`, `@EntitledAll`
- `Routes.swift` - `@requires`, `@requiresAny`, `@requiresAll` (route-level)

### Models
- `Models.swift` - `@IntentEnum`

### ViewModel Pattern
- `ViewModelBoundDemo.swift` - `@ViewModelBound`, `@ObservableViewModel`

---

*Last updated: 2025-12-12*
