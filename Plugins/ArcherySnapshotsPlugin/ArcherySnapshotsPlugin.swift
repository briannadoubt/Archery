import PackagePlugin
import Foundation

@main
struct ArcherySnapshotsPlugin: CommandPlugin {
    func performCommand(context: PluginContext, arguments: [String]) throws {
        try run(toolPath: "/usr/bin/swift", arguments: ["test", "-e", "ARCHERY_RECORD_SNAPSHOTS=1"])
        try run(toolPath: "/usr/bin/swift", arguments: ["test"])
    }

    private func run(toolPath: String, arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: toolPath)
        process.arguments = arguments
        process.currentDirectoryURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        try process.run()
        process.waitUntilExit()

        if process.terminationStatus != 0 {
            let output = String(data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            let err = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            Diagnostics.error("Command failed: \(toolPath) \(arguments.joined(separator: " "))\n\(output)\n\(err)")
            throw CommandError(message: "Command failed with exit code \(process.terminationStatus)")
        }
    }
}

struct CommandError: Error, CustomStringConvertible {
    let message: String
    var description: String { message }
}

#if canImport(XcodeProjectPlugin)
import XcodeProjectPlugin
extension ArcherySnapshotsPlugin: XcodeCommandPlugin {
    func performCommand(context: XcodePluginContext, arguments: [String]) throws {
        try performCommand(context: context.pluginContext, arguments: arguments)
    }
}
#endif
