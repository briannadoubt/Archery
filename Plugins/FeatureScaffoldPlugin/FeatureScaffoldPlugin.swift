import PackagePlugin
import Foundation

@main
struct FeatureScaffoldPlugin: CommandPlugin {
    func performCommand(context: PluginContext, arguments: [String]) throws {
        // Get the scaffold tool
        let tool = try context.tool(named: "feature-scaffold")

        // Default output to Sources directory
        var args = arguments
        if args.count == 1 {
            // Only feature name provided, use default path
            let defaultPath = context.package.directoryURL
                .appendingPathComponent("Sources")
                .appendingPathComponent("Features")
            args.append(defaultPath.path)
        }

        guard args.count >= 2 else {
            Diagnostics.error("""
                Usage: swift package plugin feature-scaffold <FeatureName> [OutputPath] [options]

                Example:
                  swift package plugin feature-scaffold Profile
                  swift package plugin feature-scaffold Settings ./Sources/Features --minimal
                """)
            return
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool.url.path)
        process.arguments = args
        process.currentDirectoryURL = context.package.directoryURL

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        try process.run()
        process.waitUntilExit()

        let output = String(data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let errorOutput = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""

        if !output.isEmpty {
            print(output)
        }

        if process.terminationStatus != 0 {
            Diagnostics.error("Feature scaffold failed:\n\(errorOutput)")
        }
    }
}

#if canImport(XcodeProjectPlugin)
import XcodeProjectPlugin

extension FeatureScaffoldPlugin: XcodeCommandPlugin {
    func performCommand(context: XcodePluginContext, arguments: [String]) throws {
        Diagnostics.warning("Feature scaffold is designed for SwiftPM packages. Use the command line instead.")
    }
}
#endif
