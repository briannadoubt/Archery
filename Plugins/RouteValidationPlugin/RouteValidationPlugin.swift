import PackagePlugin
import Foundation

// MARK: - Route Validation Build Tool Plugin
//
// This plugin runs at build time to validate that no duplicate @Route paths
// exist across your codebase and its source dependencies.
//
// Usage in Package.swift:
//   .target(
//       name: "MyApp",
//       dependencies: ["Archery"],
//       plugins: [.plugin(name: "RouteValidationPlugin", package: "Archery")]
//   )
//
// Or in Xcode: Add "RouteValidationPlugin" to your target's Build Tool Plugins

@main
struct RouteValidationPlugin: BuildToolPlugin {
    func createBuildCommands(context: PluginContext, target: Target) async throws -> [Command] {
        // Only process source module targets
        guard let sourceTarget = target as? SourceModuleTarget else {
            return []
        }

        // Collect all Swift source files from target and its dependencies
        var allSourceFiles: [URL] = []

        // Add source files from the main target
        allSourceFiles += sourceTarget.sourceFiles
            .filter { $0.type == .source }
            .map(\.url)

        // Recursively collect from dependencies
        collectSourceFiles(from: target.dependencies, into: &allSourceFiles, context: context)

        // Skip if no Swift files found
        guard !allSourceFiles.isEmpty else {
            return []
        }

        // Get the route-validator tool
        let validatorTool = try context.tool(named: "route-validator")

        // Output marker file - written by validator on success
        let outputFile = context.pluginWorkDirectoryURL
            .appending(path: "RouteValidation")
            .appending(path: "\(target.name)-routes-validated.marker")

        // Create a build command that validates routes
        // Uses buildCommand so it can depend on the route-validator executable
        return [
            .buildCommand(
                displayName: "Validate @Route paths for \(target.name)",
                executable: validatorTool.url,
                arguments: ["--output", outputFile.path] + allSourceFiles.map(\.path),
                inputFiles: allSourceFiles,
                outputFiles: [outputFile]
            )
        ]
    }

    private func collectSourceFiles(
        from dependencies: [TargetDependency],
        into files: inout [URL],
        context: PluginContext
    ) {
        for dependency in dependencies {
            switch dependency {
            case .target(let target):
                // Local target dependency
                if let sourceTarget = target as? SourceModuleTarget {
                    files += sourceTarget.sourceFiles
                        .filter { $0.type == .source }
                        .map(\.url)

                    // Recurse into this target's dependencies
                    collectSourceFiles(from: target.dependencies, into: &files, context: context)
                }

            case .product(let product):
                // Product from another package - collect from its targets
                for target in product.targets {
                    if let sourceTarget = target as? SourceModuleTarget {
                        files += sourceTarget.sourceFiles
                            .filter { $0.type == .source }
                            .map(\.url)

                        collectSourceFiles(from: target.dependencies, into: &files, context: context)
                    }
                }

            @unknown default:
                break
            }
        }
    }
}

#if canImport(XcodeProjectPlugin)
import XcodeProjectPlugin

// MARK: - Xcode Build Tool Plugin

extension RouteValidationPlugin: XcodeBuildToolPlugin {
    func createBuildCommands(context: XcodePluginContext, target: XcodeTarget) throws -> [Command] {
        // Collect Swift files from the Xcode target
        let swiftFiles = target.inputFiles
            .filter { $0.type == .source && $0.url.pathExtension == "swift" }
            .map(\.url)

        guard !swiftFiles.isEmpty else {
            return []
        }

        // Get the route-validator tool
        let validatorTool = try context.tool(named: "route-validator")

        // Output marker file - written by validator on success
        let outputFile = context.pluginWorkDirectoryURL
            .appending(path: "RouteValidation")
            .appending(path: "\(target.displayName)-routes-validated.marker")

        return [
            .buildCommand(
                displayName: "Validate @Route paths for \(target.displayName)",
                executable: validatorTool.url,
                arguments: ["--output", outputFile.path] + swiftFiles.map(\.path),
                inputFiles: swiftFiles,
                outputFiles: [outputFile]
            )
        ]
    }
}
#endif
