// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription
import CompilerPluginSupport

let warningFlags: [SwiftSetting] = [
//    .treatAllWarnings(as: .error, .when(configuration: .debug)),
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
    ],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-syntax.git", from: "602.0.0-latest"),
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.5.0"),
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
                .product(name: "SwiftParser", package: "swift-syntax")
            ], 
            swiftSettings: warningFlags
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
    ]
)
