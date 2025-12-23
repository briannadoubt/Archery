# Archery 🏹

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

#### 1. Define a View Model

```swift
@ObservableViewModel
class ProductListViewModel {
    @Published var products: [Product] = []
    @Published var loadState: LoadState<[Product]> = .idle
    
    let repository: ProductRepository
    
    init(repository: ProductRepository) {
        self.repository = repository
    }
    
    func load() async {
        loadState = .loading
        do {
            products = try await repository.fetchProducts()
            loadState = .success(products)
        } catch {
            loadState = .error(error)
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
@ViewModelBound
struct ProductListView: View {
    @StateObject var viewModel: ProductListViewModel
    
    var body: some View {
        List(viewModel.products) { product in
            ProductRow(product: product)
        }
        .task {
            await viewModel.load()
        }
    }
}
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

### @APIClient
Provides async/await networking with retry logic, caching, and error handling.

### @DesignTokens
Imports design tokens from Figma/Style Dictionary for consistent theming.

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
│   ├── ArcheryMacros/        # Macro implementations
│   ├── ArcheryRuntime/       # Runtime support
│   ├── ArcheryDI/           # Dependency injection
│   ├── ArcheryNavigation/   # Navigation & routing
│   └── ArcheryTesting/      # Testing utilities
├── Tests/                    # Test suites
├── Examples/                # Sample applications
└── Documentation/           # Guides and API docs
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

See [UPGRADE_PLAN.md](UPGRADE_PLAN.md) for the detailed implementation roadmap. Key upcoming features:

- [ ] Persistence layer (SwiftData/Core Data/SQLite)
- [ ] Accessibility & Localization tooling
- [ ] Widget & App Intent generation
- [ ] Analytics & Feature Flag system
- [ ] Full app generation from schema

## License

Apache-2.0 - See [LICENSE](LICENSE) for details.

## Support

- **Issues**: [GitHub Issues](https://github.com/briannadoubt/Archery/issues)
- **Discussions**: [GitHub Discussions](https://github.com/briannadoubt/Archery/discussions)

## Acknowledgments

Built with ❤️ for the Swift community. Special thanks to all contributors and early adopters who helped shape this framework.