import PackagePlugin
import Foundation

@main
struct ArcherySnapshotsPlugin: CommandPlugin {
    func performCommand(context: PluginContext, arguments: [String]) throws {
        let workdir = context.package.directory.string
        try run(toolPath: "/usr/bin/swift", arguments: ["test", "-e", "ARCHERY_RECORD_SNAPSHOTS=1"], workingDirectory: workdir)
        try run(toolPath: "/usr/bin/swift", arguments: ["test"], workingDirectory: workdir)
    }

    private func run(toolPath: String, arguments: [String], workingDirectory: String? = nil) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: toolPath)
        process.arguments = arguments
        if let workingDirectory {
            process.currentDirectoryURL = URL(fileURLWithPath: workingDirectory)
        } else {
            process.currentDirectoryURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        }

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
        let workdir = context.xcodeProject.directory.string
        try run(toolPath: "/usr/bin/swift", arguments: ["test", "-e", "ARCHERY_RECORD_SNAPSHOTS=1"], workingDirectory: workdir)
        try run(toolPath: "/usr/bin/swift", arguments: ["test"], workingDirectory: workdir)
    }
}
#endif
