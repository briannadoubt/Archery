// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ArcheryShowcase",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
        .watchOS(.v10),
        .tvOS(.v17),
        .visionOS(.v1)
    ],
    products: [
        .library(
            name: "ArcheryShowcaseCore",
            targets: ["ArcheryShowcaseCore"]
        ),
        .library(
            name: "ArcheryShowcaseFeatures",
            targets: ["ArcheryShowcaseFeatures"]
        )
    ],
    dependencies: [
        // Local Archery package
        .package(path: "../"),
        
        // Third-party dependencies for showcase
        .package(url: "https://github.com/pointfreeco/swift-snapshot-testing", from: "1.15.0"),
        .package(url: "https://github.com/apple/swift-collections", from: "1.0.0")
    ],
    targets: [
        // Core shared code
        .target(
            name: "ArcheryShowcaseCore",
            dependencies: [
                .product(name: "Archery", package: "Archery"),
                .product(name: "Collections", package: "swift-collections")
            ],
            path: "Sources/Core"
        ),
        
        // Feature modules
        .target(
            name: "ArcheryShowcaseFeatures",
            dependencies: [
                "ArcheryShowcaseCore",
                .product(name: "Archery", package: "Archery")
            ],
            path: "Sources/Features"
        ),
        
        // Tests
        .testTarget(
            name: "ArcheryShowcaseTests",
            dependencies: [
                "ArcheryShowcaseCore",
                "ArcheryShowcaseFeatures",
                .product(name: "SnapshotTesting", package: "swift-snapshot-testing")
            ],
            path: "Tests"
        )
    ]
)