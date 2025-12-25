import PackagePlugin
import Foundation

@main
struct ArcheryLintPlugin: CommandPlugin {
    func performCommand(context: PluginContext, arguments: [String]) throws {
        let tool = try context.tool(named: "archery-lint")

        var args = arguments
        // Default to project root if not specified
        if !args.contains("--project-root") && !args.contains("-p") {
            args.insert(contentsOf: ["--project-root", context.package.directoryURL.path], at: 0)
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
            if !errorOutput.isEmpty {
                Diagnostics.error(errorOutput)
            }
            Diagnostics.error("Archery lint found violations")
        }
    }
}

#if canImport(XcodeProjectPlugin)
import XcodeProjectPlugin

extension ArcheryLintPlugin: XcodeCommandPlugin {
    func performCommand(context: XcodePluginContext, arguments: [String]) throws {
        let tool = try context.tool(named: "archery-lint")

        var args = arguments
        if !args.contains("--project-root") && !args.contains("-p") {
            args.insert(contentsOf: ["--project-root", context.xcodeProject.directoryURL.path], at: 0)
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool.url.path)
        process.arguments = args
        process.currentDirectoryURL = context.xcodeProject.directoryURL

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        try process.run()
        process.waitUntilExit()

        let output = String(data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        print(output)

        if process.terminationStatus != 0 {
            Diagnostics.error("Archery lint found violations")
        }
    }
}
#endif
