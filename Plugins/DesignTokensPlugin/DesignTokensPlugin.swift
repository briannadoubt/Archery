import PackagePlugin
import Foundation

// MARK: - Design Tokens Build Tool Plugin
//
// This plugin generates Swift code from a design-tokens.json manifest file.
// The generated code provides type-safe access to colors, typography, and spacing.
//
// Usage in Package.swift:
//   .target(
//       name: "MyApp",
//       dependencies: ["Archery"],
//       plugins: [.plugin(name: "DesignTokensPlugin", package: "Archery")]
//   )
//
// Configuration:
//   By default, looks for `design-tokens.json` at the package root.
//   Create `design-tokens-config.json` to customize:
//   {
//     "manifestPath": "Resources/tokens.json",
//     "enumName": "AppDesignTokens",
//     "outputFileName": "AppTokens.swift",
//     "accessLevel": "public"
//   }

@main
struct DesignTokensPlugin: BuildToolPlugin {
    func createBuildCommands(context: PluginContext, target: Target) async throws -> [Command] {
        // Only process source module targets
        guard target is SourceModuleTarget else {
            return []
        }

        let packageDir = context.package.directoryURL

        // Load configuration or use defaults
        let config = loadConfiguration(from: packageDir)

        // Find the manifest file
        let manifestPath: URL
        if let customPath = config.manifestPath {
            manifestPath = packageDir.appending(path: customPath)
        } else {
            manifestPath = packageDir.appending(path: "design-tokens.json")
        }

        // Check if manifest exists
        guard FileManager.default.fileExists(atPath: manifestPath.path) else {
            // No manifest file, skip generation silently
            return []
        }

        // Determine output settings
        let enumName = config.enumName ?? "DesignTokens"
        let outputFileName = config.outputFileName ?? "\(enumName).swift"
        let accessLevel = config.accessLevel ?? "public"

        // Output file goes in plugin work directory
        let outputFile = context.pluginWorkDirectoryURL.appending(path: outputFileName)

        // Get the generator tool
        let generatorTool = try context.tool(named: "design-tokens-generator")

        // Create build command that generates source files
        // Using buildCommand allows us to use built executables from this package
        return [
            .buildCommand(
                displayName: "Generate Design Tokens for \(target.name)",
                executable: generatorTool.url,
                arguments: [
                    "--input", manifestPath.path,
                    "--output", outputFile.path,
                    "--enum-name", enumName,
                    "--access-level", accessLevel
                ],
                inputFiles: [manifestPath],
                outputFiles: [outputFile]
            )
        ]
    }

    private func loadConfiguration(from packageDir: URL) -> Configuration {
        let configPath = packageDir.appending(path: "design-tokens-config.json")
        guard FileManager.default.fileExists(atPath: configPath.path),
              let data = try? Data(contentsOf: configPath),
              let config = try? JSONDecoder().decode(Configuration.self, from: data) else {
            return Configuration()
        }
        return config
    }

    struct Configuration: Decodable {
        let manifestPath: String?
        let enumName: String?
        let outputFileName: String?
        let accessLevel: String?

        init(
            manifestPath: String? = nil,
            enumName: String? = nil,
            outputFileName: String? = nil,
            accessLevel: String? = nil
        ) {
            self.manifestPath = manifestPath
            self.enumName = enumName
            self.outputFileName = outputFileName
            self.accessLevel = accessLevel
        }
    }
}

#if canImport(XcodeProjectPlugin)
import XcodeProjectPlugin

// MARK: - Xcode Build Tool Plugin

extension DesignTokensPlugin: XcodeBuildToolPlugin {
    func createBuildCommands(context: XcodePluginContext, target: XcodeTarget) throws -> [Command] {
        let projectDir = context.xcodeProject.directoryURL

        // Load configuration or use defaults
        let config = loadConfiguration(from: projectDir)

        // Find the manifest file
        let manifestPath: URL
        if let customPath = config.manifestPath {
            manifestPath = projectDir.appending(path: customPath)
        } else {
            manifestPath = projectDir.appending(path: "design-tokens.json")
        }

        // Check if manifest exists
        guard FileManager.default.fileExists(atPath: manifestPath.path) else {
            // No manifest file, skip generation silently
            return []
        }

        // Determine output settings
        let enumName = config.enumName ?? "DesignTokens"
        let outputFileName = config.outputFileName ?? "\(enumName).swift"
        let accessLevel = config.accessLevel ?? "public"

        // Output file goes in plugin work directory
        let outputFile = context.pluginWorkDirectoryURL.appending(path: outputFileName)

        // Get the generator tool
        let generatorTool = try context.tool(named: "design-tokens-generator")

        // Create build command that generates source files
        return [
            .buildCommand(
                displayName: "Generate Design Tokens for \(target.displayName)",
                executable: generatorTool.url,
                arguments: [
                    "--input", manifestPath.path,
                    "--output", outputFile.path,
                    "--enum-name", enumName,
                    "--access-level", accessLevel
                ],
                inputFiles: [manifestPath],
                outputFiles: [outputFile]
            )
        ]
    }
}
#endif
