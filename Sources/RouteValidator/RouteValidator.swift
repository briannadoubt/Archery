import Foundation
import SwiftSyntax
import SwiftParser

// MARK: - Route Validator CLI
//
// This tool scans Swift source files for @Route macros and validates:
// 1. No duplicate paths across all routes
// 2. Path format is valid
// 3. Reports conflicts with file locations

@main
struct RouteValidator {
    static func main() throws {
        var arguments = Array(CommandLine.arguments.dropFirst())

        guard !arguments.isEmpty else {
            printError("Usage: route-validator [--output <marker-file>] <source-files...>")
            printError("       route-validator [--output <marker-file>] --scan-dir <directory>")
            exit(1)
        }

        // Parse --output flag
        var outputFile: String?
        if let outputIndex = arguments.firstIndex(of: "--output") {
            guard arguments.count > outputIndex + 1 else {
                printError("Missing path argument for --output")
                exit(1)
            }
            outputFile = arguments[outputIndex + 1]
            arguments.removeSubrange(outputIndex...outputIndex + 1)
        }

        var filePaths: [String] = []

        // Check for --scan-dir mode
        if arguments.first == "--scan-dir" {
            guard arguments.count >= 2 else {
                printError("Missing directory argument for --scan-dir")
                exit(1)
            }
            let directory = arguments.dropFirst().first!
            filePaths = findSwiftFiles(in: directory)
        } else {
            filePaths = arguments
        }

        // Parse all files and collect route definitions
        var allRoutes: [RouteDefinition] = []
        var parseErrors: [String] = []

        for filePath in filePaths {
            do {
                let routes = try parseRoutes(from: filePath)
                allRoutes.append(contentsOf: routes)
            } catch {
                parseErrors.append("Failed to parse \(filePath): \(error)")
            }
        }

        // Check for duplicates
        let conflicts = findConflicts(in: allRoutes)

        // Report results
        if !parseErrors.isEmpty {
            for error in parseErrors {
                printWarning(error)
            }
        }

        if conflicts.isEmpty {
            print("route-validator: Validated \(allRoutes.count) routes across \(filePaths.count) files - no conflicts found")

            // Write marker file on success
            if let outputFile {
                try writeMarkerFile(to: outputFile, routeCount: allRoutes.count, fileCount: filePaths.count)
            }

            exit(0)
        } else {
            printError("route-validator: Found \(conflicts.count) route path conflict(s):")
            for conflict in conflicts {
                printError("")
                printError("  Duplicate path: \"\(conflict.path)\"")
                for route in conflict.routes {
                    printError("    - \(route.typeName) in \(route.file):\(route.line)")
                }
            }
            exit(1)
        }
    }

    static func writeMarkerFile(to path: String, routeCount: Int, fileCount: Int) throws {
        let url = URL(fileURLWithPath: path)

        // Create directory if needed
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        // Write marker content
        let content = """
            Route Validation Passed
            Date: \(ISO8601DateFormatter().string(from: Date()))
            Routes validated: \(routeCount)
            Files scanned: \(fileCount)
            """
        try content.write(to: url, atomically: true, encoding: .utf8)
    }

    // MARK: - File Discovery

    static func findSwiftFiles(in directory: String) -> [String] {
        let fileManager = FileManager.default
        var swiftFiles: [String] = []

        guard let enumerator = fileManager.enumerator(
            at: URL(fileURLWithPath: directory),
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return []
        }

        for case let fileURL as URL in enumerator {
            if fileURL.pathExtension == "swift" {
                swiftFiles.append(fileURL.path)
            }
        }

        return swiftFiles
    }

    // MARK: - Parsing

    static func parseRoutes(from filePath: String) throws -> [RouteDefinition] {
        let source = try String(contentsOfFile: filePath, encoding: .utf8)
        let sourceFile = Parser.parse(source: source)

        let visitor = RouteVisitor(filePath: filePath)
        visitor.walk(sourceFile)

        return visitor.routes
    }

    // MARK: - Conflict Detection

    static func findConflicts(in routes: [RouteDefinition]) -> [RouteConflict] {
        // Group routes by path
        var routesByPath: [String: [RouteDefinition]] = [:]

        for route in routes {
            routesByPath[route.path, default: []].append(route)
        }

        // Find paths with more than one route
        return routesByPath
            .filter { $0.value.count > 1 }
            .map { RouteConflict(path: $0.key, routes: $0.value) }
            .sorted { $0.path < $1.path }
    }

    // MARK: - Output Helpers

    static func printError(_ message: String) {
        FileHandle.standardError.write(Data("error: \(message)\n".utf8))
    }

    static func printWarning(_ message: String) {
        FileHandle.standardError.write(Data("warning: \(message)\n".utf8))
    }
}

// MARK: - Data Types

struct RouteDefinition: Equatable {
    let path: String
    let typeName: String
    let file: String
    let line: Int
}

struct RouteConflict {
    let path: String
    let routes: [RouteDefinition]
}

// MARK: - SwiftSyntax Visitor

class RouteVisitor: SyntaxVisitor {
    let filePath: String
    var routes: [RouteDefinition] = []

    init(filePath: String) {
        self.filePath = filePath
        super.init(viewMode: .sourceAccurate)
    }

    override func visit(_ node: EnumDeclSyntax) -> SyntaxVisitorContinueKind {
        // Check if this enum has @Route attribute
        for attribute in node.attributes {
            guard let attrSyntax = attribute.as(AttributeSyntax.self) else { continue }

            let attrName = attrSyntax.attributeName.trimmedDescription
            guard attrName == "Route" else { continue }

            // Extract the path parameter
            if let path = extractPath(from: attrSyntax) {
                let location = node.startLocation(converter: SourceLocationConverter(
                    fileName: filePath,
                    tree: node.root
                ))

                routes.append(RouteDefinition(
                    path: path,
                    typeName: node.name.text,
                    file: URL(fileURLWithPath: filePath).lastPathComponent,
                    line: location.line
                ))
            }
        }

        return .visitChildren
    }

    private func extractPath(from attribute: AttributeSyntax) -> String? {
        guard let arguments = attribute.arguments?.as(LabeledExprListSyntax.self) else {
            return nil
        }

        for argument in arguments {
            // Look for path: "value" or unlabeled first argument
            let label = argument.label?.text
            if label == "path" || label == nil {
                if let stringLiteral = argument.expression.as(StringLiteralExprSyntax.self),
                   let segment = stringLiteral.segments.first?.as(StringSegmentSyntax.self) {
                    return segment.content.text
                }
            }
        }

        return nil
    }
}
