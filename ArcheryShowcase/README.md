# Archery Showcase

A complete Xcode project demonstrating all features of the Archery SwiftUI macro architecture framework.

## Overview

This showcase app demonstrates:
- All Archery macros in real-world usage
- Complete app architecture with authentication, navigation, and data flow
- Cross-platform support (iOS, macOS, watchOS, tvOS, visionOS)
- Widget and App Intents integration
- Design system with tokens
- Repository pattern with mock/live implementations
- Comprehensive testing examples

## Project Structure

```
ArcheryShowcase/
├── ArcheryShowcase/          # Main app target
│   ├── App/                 # App entry point and configuration
│   ├── Features/            # Feature modules (Auth, Dashboard, Tasks, etc.)
│   ├── Core/                # Shared models, repositories, services
│   └── Resources/           # Assets and configuration files
├── ArcheryShowcaseWidget/   # Widget extension
├── ArcheryShowcaseIntents/  # App Intents extension
├── ArcheryShowcaseTests/    # Unit tests
└── ArcheryShowcaseUITests/  # UI tests
```

## Featured Macros

### @AppShell
Generates the root navigation structure with tabs, sheets, and full-screen covers.

### @ViewModelBound
Automatically binds Views to ViewModels with dependency injection.

### @ObservableViewModel
Creates ViewModels with lifecycle management and MainActor enforcement.

### @Repository
Generates repository protocols with live/mock implementations.

### @KeyValueStore
Type-safe key-value storage with namespacing and defaults.

### @DesignTokens
Design system tokens from Figma or local definitions.

### @APIClient
Network layer with retry, caching, and error handling.

### @FormValidation
Form handling with validation rules and error presentation.

### @WidgetDefinition
Widget timeline and configuration generation.

### @AppIntent
Shortcuts and Siri integration.

## Running the Project

1. Open `ArcheryShowcase.xcodeproj` in Xcode
2. Select your target device/simulator
3. Build and run (⌘R)

## Key Features Demonstrated

### Authentication Flow
- Login/signup with email
- Social login (Apple, Google)
- Token management with Keychain
- Auth state persistence

### Dashboard
- Real-time stats and charts
- Activity tracking
- Quick actions
- Pull-to-refresh

### Task Management
- CRUD operations
- Filtering and sorting
- Swipe actions
- Context menus
- Pagination

### Design System
- Semantic colors
- Typography scales
- Spacing tokens
- Adaptive layouts

### Data Flow
- Repository pattern
- Mock/live data switching
- Caching strategies
- Error handling

### Testing
- Macro snapshot tests
- Repository mock tests
- ViewModel tests
- UI tests

## Architecture Patterns

### MVVM with ViewModelBound
```swift
@ViewModelBound(viewModel: TaskListViewModel.self)
struct TaskListView: View {
    @StateObject var vm: TaskListViewModel
    // View implementation
}
```

### Repository with DI
```swift
@Repository(endpoints: [...], mockData: true)
protocol TaskRepository {
    func getTasks() async throws -> [Task]
}
```

### Type-Safe Storage
```swift
@KeyValueStore(namespace: "preferences")
enum UserPreferencesStore {
    case theme(AppTheme)
    case notifications(Bool)
}
```

## Platform Adaptations

The app demonstrates platform-specific UI:
- iOS: Tab-based navigation
- macOS: Sidebar navigation
- watchOS: List-based navigation
- tvOS: Focus-based navigation
- visionOS: Spatial design

## Testing

Run tests with:
```bash
swift test
```

Or in Xcode:
- Unit tests: ⌘U
- UI tests: ⌘⌥U

## Contributing

This is a showcase project for the Archery framework. For framework contributions, see the main Archery repository.

## License

Apache-2.0