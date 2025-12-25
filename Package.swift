// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription
import CompilerPluginSupport

let warningFlags: [SwiftSetting] = [
    .treatAllWarnings(as: .error),
]

let package = Package(
    name: "Archery",
    platforms: [
        .macOS(.v26),
        .iOS(.v26),
        .tvOS(.v26),
        .watchOS(.v26),
        .macCatalyst(.v26),
        .visionOS(.v26),
    ],
    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .library(
            name: "Archery",
            targets: ["Archery"]
        ),
        .library(
            name: "ArcheryClient",
            targets: ["ArcheryClient"]
        ),
        // Build tool plugin for validating @Route paths at compile time
        .plugin(
            name: "RouteValidationPlugin",
            targets: ["RouteValidationPlugin"]
        ),
        // Build tool plugin for generating design tokens from JSON
        .plugin(
            name: "DesignTokensPlugin",
            targets: ["DesignTokensPlugin"]
        ),
        // Command plugin for scaffolding new features
        .plugin(
            name: "FeatureScaffoldPlugin",
            targets: ["FeatureScaffoldPlugin"]
        ),
        // Command plugin for architecture linting
        .plugin(
            name: "ArcheryLintPlugin",
            targets: ["ArcheryLintPlugin"]
        ),
        // Command plugin for performance budget checking
        .plugin(
            name: "ArcheryBudgetPlugin",
            targets: ["ArcheryBudgetPlugin"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-syntax.git", from: "603.0.0-prerelease-2025-10-30"),
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.5.0"),
        .package(url: "https://github.com/groue/GRDB.swift", from: "7.0.0"),
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        // Macro implementation that performs the source transformation of a macro.
        .macro(
            name: "ArcheryMacros",
            dependencies: [
                .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
                .product(name: "SwiftCompilerPlugin", package: "swift-syntax")
            ],
            swiftSettings: warningFlags
        ),

        // Library that exposes a macro as part of its API, which is used in client programs.
        .target(
            name: "Archery",
            dependencies: [
                "ArcheryMacros",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "SwiftSyntax", package: "swift-syntax"),
                .product(name: "SwiftParser", package: "swift-syntax"),
                .product(name: "GRDB", package: "GRDB.swift")
            ],
            exclude: [
                "Testing/ShellUITests.swift",
                "Testing/CompatibilityTests.swift",
                "E2ETesting/UITestRunner.swift",
                "Performance/PerformanceSuite.swift",
                "Documentation/DocGeneratorCLI.swift"
            ],
            swiftSettings: warningFlags,
            plugins: [
                .plugin(name: "DesignTokensPlugin")
            ]
        ),

        // A client of the library, which is able to use the macro in its own code.
        .target(
            name: "ArcheryClient",
            dependencies: ["Archery"],
            swiftSettings: warningFlags
        ),

        // A test target used to develop the macro implementation.
        .testTarget(
            name: "ArcheryTests",
            dependencies: [
                "Archery",
                "ArcheryMacros",
                .product(name: "SwiftSyntaxMacrosTestSupport", package: "swift-syntax"),
                .product(name: "SwiftParser", package: "swift-syntax"),
                .product(name: "SwiftSyntaxMacroExpansion", package: "swift-syntax"),
                .product(name: "SwiftSyntax", package: "swift-syntax"),
                .product(name: "SwiftSyntaxMacros", package: "swift-syntax")
            ],
            resources: [
                .process("__Snapshots__")
            ],
            swiftSettings: warningFlags
        ),

        .plugin(
            name: "ArcherySnapshotsPlugin",
            capability: .command(
                intent: .custom(verb: "archery-snapshots", description: "Regenerate Archery macro snapshots and run tests"),
                permissions: [
                    .writeToPackageDirectory(reason: "Update snapshot fixtures")
                ]
            ),
            dependencies: []
        ),

        // Route validation CLI tool (used by RouteValidationPlugin)
        .executableTarget(
            name: "route-validator",
            dependencies: [
                .product(name: "SwiftSyntax", package: "swift-syntax"),
                .product(name: "SwiftParser", package: "swift-syntax"),
            ],
            path: "Sources/RouteValidator",
            swiftSettings: warningFlags
        ),

        // Build tool plugin for validating @Route paths at compile time
        .plugin(
            name: "RouteValidationPlugin",
            capability: .buildTool(),
            dependencies: [
                .target(name: "route-validator")
            ],
            path: "Plugins/RouteValidationPlugin"
        ),

        // Design tokens generator CLI tool (used by DesignTokensPlugin)
        .executableTarget(
            name: "design-tokens-generator",
            dependencies: [],
            path: "Sources/DesignTokensGenerator",
            swiftSettings: warningFlags
        ),

        // Build tool plugin for generating design tokens from JSON
        .plugin(
            name: "DesignTokensPlugin",
            capability: .buildTool(),
            dependencies: [
                .target(name: "design-tokens-generator")
            ],
            path: "Plugins/DesignTokensPlugin"
        ),

        // Feature scaffold CLI tool
        .executableTarget(
            name: "feature-scaffold",
            dependencies: [],
            path: "Sources/FeatureScaffold",
            swiftSettings: warningFlags
        ),

        // Feature scaffold command plugin
        .plugin(
            name: "FeatureScaffoldPlugin",
            capability: .command(
                intent: .custom(verb: "feature-scaffold", description: "Scaffold a new feature with Archery macros"),
                permissions: [
                    .writeToPackageDirectory(reason: "Create feature files")
                ]
            ),
            dependencies: [
                .target(name: "feature-scaffold")
            ],
            path: "Plugins/FeatureScaffoldPlugin"
        ),

        // Architecture linter CLI tool
        .executableTarget(
            name: "archery-lint",
            dependencies: [
                .product(name: "SwiftSyntax", package: "swift-syntax"),
                .product(name: "SwiftParser", package: "swift-syntax"),
            ],
            path: "Sources/ArcheryLint",
            swiftSettings: warningFlags
        ),

        // Architecture linter command plugin
        .plugin(
            name: "ArcheryLintPlugin",
            capability: .command(
                intent: .custom(verb: "archery-lint", description: "Lint for architectural violations"),
                permissions: []
            ),
            dependencies: [
                .target(name: "archery-lint")
            ],
            path: "Plugins/ArcheryLintPlugin"
        ),

        // Performance budget CLI tool
        .executableTarget(
            name: "archery-budget",
            dependencies: [],
            path: "Sources/ArcheryBudget",
            swiftSettings: warningFlags
        ),

        // Performance budget command plugin
        .plugin(
            name: "ArcheryBudgetPlugin",
            capability: .command(
                intent: .custom(verb: "archery-budget", description: "Check performance budgets"),
                permissions: []
            ),
            dependencies: [
                .target(name: "archery-budget")
            ],
            path: "Plugins/ArcheryBudgetPlugin"
        ),
    ],
    swiftLanguageModes: [.v6]
)
