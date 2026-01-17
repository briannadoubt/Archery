# Archery 🏹

A production-ready, macro-first SwiftUI architecture framework that eliminates boilerplate while maintaining strong typing, dependency injection, and comprehensive testing across all Apple platforms.

## Features

### Core Architecture
- **Swift Macros**: Generate boilerplate code automatically while keeping it readable and debuggable
- **Dependency Injection**: Built-in DI container with auto-registration and manual opt-outs
- **Type Safety**: Strongly typed navigation, routes, and data flow throughout
- **Testing First**: Mandatory snapshot tests, navigation validation, and UI smoke tests

### Platform Support
- iOS, iPadOS, tvOS
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

#### 1. Define a View Model

```swift
@ObservableViewModel
@MainActor
class ProductListViewModel {
    var products: [Product] = []
    var loadState: LoadState<[Product]> = .idle

    let repository: ProductRepository

    init(repository: ProductRepository) {
        self.repository = repository
    }

    func load() async {
        beginLoading(\.loadState)
        do {
            products = try await repository.fetchProducts()
            endSuccess(\.loadState, value: products)
        } catch {
            endFailure(\.loadState, error: error)
        }
    }
}
```

#### 2. Create an API Client

```swift
@APIClient
class ProductsAPI {
    func fetchProducts() async throws -> [Product] { ... }
    func getProduct(id: String) async throws -> Product { ... }
}
```

#### 3. Bind to a View

```swift
@ViewModelBound<ProductListViewModel>
struct ProductListView: View {
    // vm is injected by the macro via DI container

    var body: some View {
        List(vm.products) { product in
            ProductRow(product: product)
        }
    }
}
// The macro auto-calls load() on appear if the VM conforms to ArcheryLoadable
```

#### 4. Setup App Shell

```swift
@AppShell
struct MyApp: App {
    @Route(.tab) var products: ProductListView
    @Route(.tab) var settings: SettingsView
    @Route(.sheet) var login: LoginView
    @Route(.fullScreen) var onboarding: OnboardingView
}
```

## Core Macros

### @KeyValueStore
Generates a type-safe, Codable-backed storage system with async/await support.

### @APIClient
Creates protocol + live/mock implementations with retry, caching, and error normalization.

### @ObservableViewModel
Enforces @MainActor, provides lifecycle hooks, and manages task cancellation.

### @ViewModelBound
Handles dependency injection and generates previews with mock data.

### @AppShell
Generates root navigation structure with typed routes and automatic DI registration.

### @Persistable
GRDB-backed persistence with automatic schema generation, migrations, and App Intents support.

### @DatabaseRepository
Generates async repository pattern with CRUD operations, custom queries, and transaction support.

### @DesignTokens
Imports design tokens from Figma/Style Dictionary for consistent theming.

### @Route
Type-safe navigation with compile-time path validation and deep link support.

### @Localizable
Generates localized string keys with compile-time validation.

## Developer Tools

Archery includes command-line plugins to help with development workflows.

### Feature Scaffold

Generate new features with all Archery macros pre-configured:

```bash
swift package plugin feature-scaffold Profile ./Features
```

Creates a complete feature structure:
- `ProfileView.swift` - SwiftUI view with ViewModel binding
- `ProfileViewModel.swift` - `@Observable` ViewModel with lifecycle hooks
- `ProfileItem.swift` - `@Persistable` model with GRDB support
- `ProfileRoute.swift` - `@Route` navigation enum
- `ProfileTests.swift` - Unit test scaffolding

Options:
```bash
swift package plugin feature-scaffold Settings ./Features --minimal  # View only
swift package plugin feature-scaffold Admin ./Features --with-tests  # Include tests
```

### Architecture Linter

Enforce architectural boundaries and best practices:

```bash
swift package plugin archery-lint
```

Rules enforced:
- **No feature-to-feature imports** - Features should communicate through shared modules or DI
- **Views shouldn't import persistence** - Use `@Query` or inject via ViewModel
- **Shared module patterns** - Core, Common, Utilities modules are allowed everywhere

CI Integration (GitHub Actions):
```bash
swift run archery-lint --format github --project-root .
```

### Performance Budget

Check binary size and build time against defined budgets:

```bash
swift package plugin archery-budget \
  --binary .build/release/MyApp \
  --build-time 45.2
```

Default thresholds:
- Binary size: 50 MB
- Build time: 2 minutes
- Configurable via `budgets.json`

Output formats: `text`, `json`, `github` (for CI annotations)

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
- Opt-out flags for test environments only

## Project Structure

```
Archery/
├── Sources/
│   ├── Archery/              # Core runtime library
│   ├── ArcheryMacros/        # Swift macro implementations
│   ├── ArcheryClient/        # Example client usage
│   ├── ArcheryLint/          # Architecture linter CLI
│   ├── ArcheryBudget/        # Performance budget CLI
│   ├── FeatureScaffold/      # Feature scaffolding CLI
│   ├── DesignTokensGenerator/ # Design tokens CLI
│   └── RouteValidator/       # Route validation CLI
├── Plugins/                  # SwiftPM build & command plugins
├── Tests/                    # Test suites with snapshots
├── ArcheryShowcase/          # Full demo app for all platforms
└── Documentation/            # Guides and API docs
```

## Performance Targets

- **Cold Start**: <300ms on baseline A-series chips
- **Frame Rate**: Consistent 60fps (<16ms per frame)
- **Memory**: <150MB for typical CRUD applications
- **Build Time**: Incremental builds with macro caching

## Testing Strategy

### Mandatory Tests
- Macro output snapshots
- Navigation graph validation
- MainActor compliance
- Accessibility linting
- Shell smoke UI tests

### Optional (Recommended)
- Property-based testing
- Fuzz testing for navigation
- Performance benchmarks
- Record/replay API testing

## Documentation

- [Architecture Overview](ARCHITECTURE.md)
- [Upgrade Plan](UPGRADE_PLAN.md)
- [API Reference](docs/api/index.md)
- [Migration Guide](docs/migration.md)

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

# Regenerate snapshots
swift package plugin regenerate-snapshots
```

## Roadmap

See [UPGRADE_PLAN.md](UPGRADE_PLAN.md) for the detailed implementation roadmap. Current status:

- [x] Persistence layer (GRDB with @Persistable and @DatabaseRepository)
- [x] Widget & App Intent generation
- [x] Analytics & Feature Flag system
- [x] Localization tooling (@Localizable macro)
- [ ] Accessibility tooling improvements
- [ ] Full app generation from schema

## License

Apache-2.0 - See [LICENSE](LICENSE) for details.

## Support

- **Issues**: [GitHub Issues](https://github.com/briannadoubt/Archery/issues)
- **Discussions**: [GitHub Discussions](https://github.com/briannadoubt/Archery/discussions)

## Acknowledgments

Built with ❤️ for the Swift community. Special thanks to all contributors and early adopters who helped shape this framework.