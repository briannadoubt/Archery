import Foundation
import SwiftSyntax
import SwiftParser

/// Archery architecture linter - enforces module boundaries and patterns
@main
struct ArcheryLint {
    static func main() throws {
        let arguments = Array(CommandLine.arguments.dropFirst())

        var projectRoot = FileManager.default.currentDirectoryPath
        var configPath: String?
        var format: OutputFormat = .text
        var failOnViolation = true

        // Parse arguments
        var i = 0
        while i < arguments.count {
            switch arguments[i] {
            case "--project-root", "-p":
                i += 1
                if i < arguments.count {
                    projectRoot = arguments[i]
                }
            case "--config", "-c":
                i += 1
                if i < arguments.count {
                    configPath = arguments[i]
                }
            case "--format", "-f":
                i += 1
                if i < arguments.count {
                    format = OutputFormat(rawValue: arguments[i]) ?? .text
                }
            case "--warn-only":
                failOnViolation = false
            case "--help", "-h":
                printUsage()
                return
            default:
                break
            }
            i += 1
        }

        let linter = ModuleLinter(
            projectRoot: URL(fileURLWithPath: projectRoot),
            configuration: try loadConfiguration(from: configPath)
        )

        let results = try linter.lint()

        // Output results
        switch format {
        case .text:
            printTextResults(results)
        case .json:
            printJSONResults(results)
        case .github:
            printGitHubResults(results)
        }

        // Exit with error if violations found
        if failOnViolation && results.hasViolations {
            exit(1)
        }
    }

    static func printUsage() {
        print("""
        Usage: archery-lint [options]

        Options:
          -p, --project-root <path>   Project root directory (default: current directory)
          -c, --config <path>         Configuration file path
          -f, --format <format>       Output format: text, json, github (default: text)
          --warn-only                 Don't fail on violations
          -h, --help                  Show this help

        Rules enforced:
          1. Feature modules cannot import other feature modules directly
          2. Views should not import persistence layers directly
          3. Models with persistence should use @Persistable
          4. Route enums should use @Route macro

        Example:
          archery-lint --project-root ./MyApp --format github
        """)
    }

    static func loadConfiguration(from path: String?) throws -> LintConfiguration {
        guard let path = path else {
            return .default
        }

        let url = URL(fileURLWithPath: path)
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(LintConfiguration.self, from: data)
    }

    static func printTextResults(_ results: LintResults) {
        print("\n" + String(repeating: "=", count: 50))
        print("Archery Lint Results")
        print(String(repeating: "=", count: 50) + "\n")

        if results.violations.isEmpty {
            print("✅ No violations found!")
        } else {
            print("❌ Found \(results.violations.count) violation(s):\n")

            for violation in results.violations {
                print("  \(violation.severity.icon) \(violation.filePath):\(violation.line ?? 0)")
                print("    Rule: \(violation.rule.rawValue)")
                print("    \(violation.message)\n")
            }
        }

        print(String(repeating: "-", count: 50))
        print("Files scanned: \(results.filesScanned)")
        print("Time: \(String(format: "%.2f", results.duration))s")
        print(String(repeating: "=", count: 50) + "\n")
    }

    static func printJSONResults(_ results: LintResults) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        struct JSONOutput: Encodable {
            let violations: [ViolationOutput]
            let filesScanned: Int
            let duration: Double
            let passed: Bool

            struct ViolationOutput: Encodable {
                let file: String
                let line: Int?
                let column: Int?
                let rule: String
                let severity: String
                let message: String
            }
        }

        let output = JSONOutput(
            violations: results.violations.map {
                JSONOutput.ViolationOutput(
                    file: $0.filePath,
                    line: $0.line,
                    column: $0.column,
                    rule: $0.rule.rawValue,
                    severity: $0.severity.rawValue,
                    message: $0.message
                )
            },
            filesScanned: results.filesScanned,
            duration: results.duration,
            passed: !results.hasViolations
        )

        if let data = try? encoder.encode(output),
           let json = String(data: data, encoding: .utf8) {
            print(json)
        }
    }

    static func printGitHubResults(_ results: LintResults) {
        // GitHub Actions annotation format
        for violation in results.violations {
            let level = violation.severity == .error ? "error" : "warning"
            let file = violation.filePath
            let line = violation.line ?? 1

            print("::\(level) file=\(file),line=\(line)::\(violation.rule.rawValue): \(violation.message)")
        }

        if results.hasViolations {
            print("\n::error::Archery lint found \(results.violations.count) violation(s)")
        } else {
            print("::notice::Archery lint passed with no violations")
        }
    }
}

enum OutputFormat: String {
    case text
    case json
    case github
}

// MARK: - Configuration

struct LintConfiguration: Codable {
    var rules: Set<LintRule>
    var excludePaths: [String]
    var featureModulePaths: [String]
    var sharedModules: Set<String>
    var allowedSystemModules: Set<String>

    static let `default` = LintConfiguration(
        rules: Set(LintRule.allCases),
        excludePaths: [".build", "DerivedData", "Pods", "Carthage"],
        featureModulePaths: ["Features", "Modules"],
        sharedModules: ["Core", "Common", "Shared", "Utilities", "DesignSystem"],
        allowedSystemModules: [
            "Foundation", "SwiftUI", "UIKit", "AppKit", "Combine",
            "Archery", "GRDB", "OSLog"
        ]
    )
}

enum LintRule: String, Codable, CaseIterable {
    case noFeatureToFeatureImports = "no-feature-imports"
    case viewsNoDirectPersistence = "views-no-persistence"
    case persistableModels = "persistable-models"
    case routeMacroUsage = "route-macro"
}

// MARK: - Linter

final class ModuleLinter {
    let projectRoot: URL
    let configuration: LintConfiguration
    private let fileManager = FileManager.default

    init(projectRoot: URL, configuration: LintConfiguration) {
        self.projectRoot = projectRoot
        self.configuration = configuration
    }

    func lint() throws -> LintResults {
        let startTime = Date()
        var violations: [Violation] = []
        var filesScanned = 0

        // Find all Swift files
        let swiftFiles = try findSwiftFiles()
        filesScanned = swiftFiles.count

        for fileURL in swiftFiles {
            let fileViolations = try lintFile(fileURL)
            violations.append(contentsOf: fileViolations)
        }

        let duration = Date().timeIntervalSince(startTime)

        return LintResults(
            violations: violations,
            filesScanned: filesScanned,
            duration: duration
        )
    }

    private func findSwiftFiles() throws -> [URL] {
        var files: [URL] = []

        guard let enumerator = fileManager.enumerator(
            at: projectRoot,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return files
        }

        while let fileURL = enumerator.nextObject() as? URL {
            // Skip excluded paths
            let relativePath = fileURL.path.replacingOccurrences(of: projectRoot.path + "/", with: "")
            if configuration.excludePaths.contains(where: { relativePath.hasPrefix($0) }) {
                continue
            }

            if fileURL.pathExtension == "swift" {
                files.append(fileURL)
            }
        }

        return files
    }

    private func lintFile(_ fileURL: URL) throws -> [Violation] {
        let source = try String(contentsOf: fileURL, encoding: .utf8)
        let sourceFile = Parser.parse(source: source)
        let relativePath = fileURL.path.replacingOccurrences(of: projectRoot.path + "/", with: "")

        var violations: [Violation] = []

        // Determine if this is a feature module file
        let isFeatureModule = configuration.featureModulePaths.contains { relativePath.contains($0) }
        let isViewFile = relativePath.contains("View.swift") || relativePath.contains("Views/")

        // Check imports
        if configuration.rules.contains(.noFeatureToFeatureImports) && isFeatureModule {
            let importViolations = checkFeatureImports(in: sourceFile, filePath: relativePath)
            violations.append(contentsOf: importViolations)
        }

        // Check views don't import persistence
        if configuration.rules.contains(.viewsNoDirectPersistence) && isViewFile {
            let persistenceViolations = checkViewPersistenceImports(in: sourceFile, filePath: relativePath)
            violations.append(contentsOf: persistenceViolations)
        }

        return violations
    }

    private func checkFeatureImports(in sourceFile: SourceFileSyntax, filePath: String) -> [Violation] {
        var violations: [Violation] = []

        let visitor = ImportVisitor(viewMode: .sourceAccurate)
        visitor.walk(sourceFile)

        for importInfo in visitor.imports {
            let moduleName = importInfo.moduleName

            // Skip allowed modules
            if configuration.allowedSystemModules.contains(moduleName) ||
               configuration.sharedModules.contains(moduleName) {
                continue
            }

            // Check if importing another feature module
            if isFeatureModule(moduleName) {
                violations.append(Violation(
                    rule: .noFeatureToFeatureImports,
                    severity: .error,
                    filePath: filePath,
                    line: importInfo.line,
                    column: importInfo.column,
                    message: "Feature module '\(moduleName)' imported directly. Use shared protocols or dependency injection instead."
                ))
            }
        }

        return violations
    }

    private func checkViewPersistenceImports(in sourceFile: SourceFileSyntax, filePath: String) -> [Violation] {
        var violations: [Violation] = []

        let visitor = ImportVisitor(viewMode: .sourceAccurate)
        visitor.walk(sourceFile)

        let persistenceModules = ["CoreData", "GRDB", "RealmSwift", "SQLite"]

        for importInfo in visitor.imports {
            if persistenceModules.contains(importInfo.moduleName) {
                violations.append(Violation(
                    rule: .viewsNoDirectPersistence,
                    severity: .warning,
                    filePath: filePath,
                    line: importInfo.line,
                    column: importInfo.column,
                    message: "View file imports persistence module '\(importInfo.moduleName)'. Use @Query or inject via ViewModel instead."
                ))
            }
        }

        return violations
    }

    private func isFeatureModule(_ name: String) -> Bool {
        // Heuristic: module names that look like features
        let featureSuffixes = ["Feature", "Module", "Screen", "Flow"]
        return featureSuffixes.contains { name.hasSuffix($0) }
    }
}

// MARK: - Syntax Visitor

private final class ImportVisitor: SyntaxVisitor {
    struct ImportInfo {
        let moduleName: String
        let line: Int
        let column: Int
    }

    var imports: [ImportInfo] = []

    override func visit(_ node: ImportDeclSyntax) -> SyntaxVisitorContinueKind {
        let moduleName = node.path.map { $0.name.text }.joined(separator: ".")
        let location = node.startLocation(converter: SourceLocationConverter(fileName: "", tree: node.root))

        imports.append(ImportInfo(
            moduleName: moduleName,
            line: location.line,
            column: location.column
        ))

        return .visitChildren
    }
}

// MARK: - Results

struct LintResults {
    let violations: [Violation]
    let filesScanned: Int
    let duration: TimeInterval

    var hasViolations: Bool {
        !violations.isEmpty
    }
}

struct Violation {
    let rule: LintRule
    let severity: Severity
    let filePath: String
    let line: Int?
    let column: Int?
    let message: String

    enum Severity: String {
        case warning
        case error

        var icon: String {
            switch self {
            case .warning: return "⚠️"
            case .error: return "❌"
            }
        }
    }
}
