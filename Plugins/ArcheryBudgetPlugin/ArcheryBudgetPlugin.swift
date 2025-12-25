import PackagePlugin
import Foundation

@main
struct ArcheryBudgetPlugin: CommandPlugin {
    func performCommand(context: PluginContext, arguments: [String]) throws {
        let tool = try context.tool(named: "archery-budget")

        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool.url.path)
        process.arguments = arguments
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
            Diagnostics.error("Performance budget check failed")
        }
    }
}

#if canImport(XcodeProjectPlugin)
import XcodeProjectPlugin

extension ArcheryBudgetPlugin: XcodeCommandPlugin {
    func performCommand(context: XcodePluginContext, arguments: [String]) throws {
        let tool = try context.tool(named: "archery-budget")

        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool.url.path)
        process.arguments = arguments
        process.currentDirectoryURL = context.xcodeProject.directoryURL

        try process.run()
        process.waitUntilExit()

        if process.terminationStatus != 0 {
            Diagnostics.error("Performance budget check failed")
        }
    }
}
#endif
