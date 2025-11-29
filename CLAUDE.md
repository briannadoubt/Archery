# Archery - SwiftUI Macro Architecture Project

## Project Overview
This is a production-ready, macro-first SwiftUI architecture framework that uses Swift macros to generate boilerplate code while maintaining strong typing, dependency injection, and testability across Apple platforms.

## Key Architecture Files
- **ARCHITECTURE.md**: Contains the high-level architectural decisions and patterns
- **UPGRADE_PLAN.md**: Detailed implementation plan with 35 major components/phases

## Current Implementation Status
Based on UPGRADE_PLAN.md, the following components are DONE:
- KeyValueStore (Section 1)
- Repository (Section 2)
- ObservableViewModel (Section 3)
- ViewModelBound (Section 4)
- AppShell (Section 5)
- Tooling & DX (Section 6)
- Runtime Glue - EnvContainer + DI wiring (Section 7)
- Networking & Errors (Section 8)
- Navigation & Deep Links (Section 10)
- Design System & Theming (Section 11)

## Project Goals
- Ship a macro-first SwiftUI architecture that is production-ready, strongly typed, and DI-friendly
- Keep generated code readable, testable, snapshot-covered, and portable across Apple platforms
- Support iOS, iPadOS, macOS, Mac Catalyst, watchOS, visionOS
- Target CRUD/content SaaS applications (v1 scope)

## Technical Stack
- Minimum SDK: v26
- Swift: 6.2
- Xcode: 26
- Package Structure: Single SwiftPM package with multiple products (runtime, macros, tooling/CLI)
- Distribution: SwiftPM plugin + Homebrew tap

## Core Macros
1. **@KeyValueStore**: Codable-backed async/throwing get/set with default values
2. **@Repository**: Generate protocol + live/mock implementations with DI
3. **@ObservableViewModel**: MainActor-bound ViewModels with lifecycle management
4. **@ViewModelBound**: DI-aware View binding with automatic repository injection
5. **@AppShell**: Root navigation structure with TabView + NavigationStacks
6. **@APIClient**: Async/await networking with retry/backoff and caching
7. **@DesignTokens**: Design system token generation from Figma/Style Dictionary

## Development Workflow

### Running Tests
```bash
swift test
```

### Building the Package
```bash
swift build
```

### Generating Snapshots
Use the SwiftPM plugin/CLI task to regenerate macro snapshots.

## Important Conventions
1. **DI Pattern**: AppShell auto-registers annotated types; optional container merge + patch hooks; @DIManual for opt-outs
2. **Testing**: Mandatory macro snapshots, nav-graph validity, MainActor/a11y lint, smoke UITest of shell
3. **Performance**: Cold start <300ms, <16ms/frame @60fps, memory <150MB for sample app
4. **Security**: Mandatory PII redaction, secrets only from secure storage, CI secret scanning
5. **Error Handling**: Normalized errors into domain-specific types with user-facing messaging

## Next Implementation Priorities
According to UPGRADE_PLAN.md, the next items to implement are:
1. Persistence (Section 9) - SwiftData/Core Data/SQLite gateway
2. Accessibility & Localization (Section 12)
3. Widgets, Intents, Background (Section 13)
4. Analytics & Feature Flags (Section 14)
5. Testing & CI (Section 15)

## Code Quality Requirements
- All macros must have snapshot tests
- Generated code must be readable and maintainable
- Support for previews with mock data
- Proper error normalization and handling
- Mandatory redaction for PII in logs/analytics

## Platform Support
The architecture supports all Apple platforms with conditional compilation:
- iOS/iPadOS
- macOS
- Mac Catalyst
- watchOS
- visionOS

Use `#if os(...)` for platform-specific code.

## License
Apache-2.0

## Contributing
- Breaking macro/schema changes require lightweight RFC + approver signoff
- Minors can add non-breaking features
- All contributions must include appropriate tests and documentation