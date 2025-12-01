import Foundation
import SwiftSyntax
import SwiftSyntaxParser

// MARK: - Module Boundary Linter

/// Linter that enforces module boundaries and prevents illegal cross-module imports
public final class ModuleBoundaryLinter {
    private let moduleRegistry: ModuleRegistry
    private var violations: [BoundaryViolation] = []
    private let configuration: LinterConfiguration
    
    public init(
        moduleRegistry: ModuleRegistry = .shared,
        configuration: LinterConfiguration = .default
    ) {
        self.moduleRegistry = moduleRegistry
        self.configuration = configuration
    }
    
    // MARK: - Public API
    
    /// Lint a module for boundary violations
    public func lint(
        module: String,
        sourceFiles: [URL]
    ) async throws -> LintResult {
        violations.removeAll()
        
        // Process files in parallel
        await withTaskGroup(of: [BoundaryViolation].self) { group in
            for file in sourceFiles {
                group.addTask { [self] in
                    (try? self.lintFile(file, module: module)) ?? []
                }
            }
            
            for await fileViolations in group {
                violations.append(contentsOf: fileViolations)
            }
        }
        
        return LintResult(
            module: module,
            violations: violations,
            passed: violations.isEmpty
        )
    }
    
    /// Lint all modules
    public func lintAll(projectRoot: URL) async throws -> [LintResult] {
        let modules = try findModules(at: projectRoot)
        var results: [LintResult] = []
        
        for module in modules {
            let sourceFiles = try findSourceFiles(in: module.path)
            let result = try await lint(
                module: module.name,
                sourceFiles: sourceFiles
            )
            results.append(result)
        }
        
        return results
    }
    
    // MARK: - File Processing
    
    private func lintFile(_ fileURL: URL, module: String) throws -> [BoundaryViolation] {
        let source = try String(contentsOf: fileURL)
        let sourceFile = Parser.parse(source: source)
        
        let visitor = ImportVisitor(
            currentModule: module,
            filePath: fileURL.path,
            configuration: configuration
        )
        
        visitor.walk(sourceFile)
        
        return visitor.violations
    }
    
    // MARK: - Module Discovery
    
    private func findModules(at projectRoot: URL) throws -> [ModuleInfo] {
        let fileManager = FileManager.default
        var modules: [ModuleInfo] = []
        
        let modulesDirectory = projectRoot.appendingPathComponent("Modules")
        
        if fileManager.fileExists(atPath: modulesDirectory.path) {
            let contents = try fileManager.contentsOfDirectory(
                at: modulesDirectory,
                includingPropertiesForKeys: [.isDirectoryKey]
            )
            
            for item in contents {
                var isDirectory: ObjCBool = false
                if fileManager.fileExists(atPath: item.path, isDirectory: &isDirectory),
                   isDirectory.boolValue {
                    modules.append(ModuleInfo(
                        name: item.lastPathComponent,
                        path: item
                    ))
                }
            }
        }
        
        return modules
    }
    
    private func findSourceFiles(in directory: URL) throws -> [URL] {
        let fileManager = FileManager.default
        var sourceFiles: [URL] = []
        
        let enumerator = fileManager.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )
        
        while let fileURL = enumerator?.nextObject() as? URL {
            if fileURL.pathExtension == "swift" {
                sourceFiles.append(fileURL)
            }
        }
        
        return sourceFiles
    }
}

// MARK: - Import Visitor

private class ImportVisitor: SyntaxVisitor {
    let currentModule: String
    let filePath: String
    let configuration: LinterConfiguration
    var violations: [BoundaryViolation] = []
    
    init(
        currentModule: String,
        filePath: String,
        configuration: LinterConfiguration
    ) {
        self.currentModule = currentModule
        self.filePath = filePath
        self.configuration = configuration
        super.init(viewMode: .sourceAccurate)
    }
    
    override func visit(_ node: ImportDeclSyntax) -> SyntaxVisitorContinueKind {
        let importedModule = node.path.map { $0.name.text }.joined(separator: ".")
        
        // Check if this import is allowed
        if !isImportAllowed(importedModule) {
            violations.append(BoundaryViolation(
                type: .illegalImport,
                sourceModule: currentModule,
                targetModule: importedModule,
                filePath: filePath,
                line: node.startLocation(converter: .init()).line,
                column: node.startLocation(converter: .init()).column,
                message: "Module '\(currentModule)' cannot import '\(importedModule)' - only contracts are allowed"
            ))
        }
        
        return .visitChildren
    }
    
    private func isImportAllowed(_ importedModule: String) -> Bool {
        // System modules are always allowed
        if configuration.allowedSystemModules.contains(importedModule) {
            return true
        }
        
        // Check if it's a contract import
        if importedModule.hasSuffix("Contract") {
            return true
        }
        
        // Check if it's importing from the same module
        if importedModule == currentModule {
            return true
        }
        
        // Check if it's in the allowed imports list
        if let allowedImports = configuration.allowedImports[currentModule] {
            return allowedImports.contains(importedModule)
        }
        
        // Check if it's a shared/core module
        if configuration.sharedModules.contains(importedModule) {
            return true
        }
        
        // Default to disallow
        return false
    }
}

// MARK: - Linter Configuration

public struct LinterConfiguration: Codable {
    public var allowedSystemModules: Set<String>
    public var sharedModules: Set<String>
    public var allowedImports: [String: Set<String>]
    public var excludePaths: [String]
    public var enableStrictMode: Bool
    
    public init(
        allowedSystemModules: Set<String> = Self.defaultSystemModules,
        sharedModules: Set<String> = [],
        allowedImports: [String: Set<String>] = [:],
        excludePaths: [String] = [],
        enableStrictMode: Bool = false
    ) {
        self.allowedSystemModules = allowedSystemModules
        self.sharedModules = sharedModules
        self.allowedImports = allowedImports
        self.excludePaths = excludePaths
        self.enableStrictMode = enableStrictMode
    }
    
    public static let `default` = LinterConfiguration()
    
    public static let defaultSystemModules: Set<String> = [
        "Foundation", "SwiftUI", "UIKit", "AppKit", "Combine",
        "CoreData", "CoreGraphics", "CoreLocation", "CoreMotion",
        "AVFoundation", "Photos", "PhotosUI", "MapKit", "WebKit",
        "StoreKit", "CloudKit", "HealthKit", "HomeKit", "SiriKit",
        "UserNotifications", "BackgroundTasks", "Network", "OSLog",
        "Compression", "CryptoKit", "Security", "LocalAuthentication"
    ]
    
    public static let strict = LinterConfiguration(
        enableStrictMode: true,
        sharedModules: ["Core", "Common", "Shared", "Utilities"]
    )
    
    /// Load configuration from file
    public static func load(from url: URL) throws -> LinterConfiguration {
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(LinterConfiguration.self, from: data)
    }
    
    /// Save configuration to file
    public func save(to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(self)
        try data.write(to: url)
    }
}

// MARK: - Lint Results

public struct LintResult {
    public let module: String
    public let violations: [BoundaryViolation]
    public let passed: Bool
    
    public var summary: String {
        if passed {
            return "✅ \(module): No violations found"
        } else {
            return "❌ \(module): \(violations.count) violation(s) found"
        }
    }
    
    public var detailedReport: String {
        guard !violations.isEmpty else {
            return summary
        }
        
        var report = summary + "\n"
        for violation in violations {
            report += "\n  \(violation.description)"
        }
        return report
    }
}

public struct BoundaryViolation: CustomStringConvertible {
    public enum ViolationType {
        case illegalImport
        case circularDependency
        case missingContract
        case contractViolation
        case internalAPIUsage
    }
    
    public let type: ViolationType
    public let sourceModule: String
    public let targetModule: String
    public let filePath: String
    public let line: Int?
    public let column: Int?
    public let message: String
    
    public var description: String {
        let location = if let line = line, let column = column {
            "\(filePath):\(line):\(column)"
        } else {
            filePath
        }
        
        return "[\(type)] \(location): \(message)"
    }
}

// MARK: - Module Analyzer

public final class ModuleAnalyzer {
    private let projectRoot: URL
    
    public init(projectRoot: URL) {
        self.projectRoot = projectRoot
    }
    
    /// Analyze module dependencies
    public func analyzeDependencies() throws -> DependencyAnalysis {
        let modules = try findAllModules()
        var dependencies: [String: Set<String>] = [:]
        var contracts: [String: ContractInfo] = [:]
        
        for module in modules {
            let deps = try analyzeModule(module)
            dependencies[module.name] = deps.dependencies
            if let contract = deps.contract {
                contracts[module.name] = contract
            }
        }
        
        return DependencyAnalysis(
            modules: modules.map { $0.name },
            dependencies: dependencies,
            contracts: contracts
        )
    }
    
    private func findAllModules() throws -> [ModuleInfo] {
        // Implementation similar to ModuleBoundaryLinter.findModules
        return []
    }
    
    private func analyzeModule(_ module: ModuleInfo) throws -> ModuleAnalysisResult {
        // Parse module files and extract dependencies
        return ModuleAnalysisResult(
            dependencies: [],
            contract: nil
        )
    }
}

// MARK: - Supporting Types

struct ModuleInfo {
    let name: String
    let path: URL
}

struct ModuleAnalysisResult {
    let dependencies: Set<String>
    let contract: ContractInfo?
}

public struct ContractInfo {
    public let version: String
    public let publicTypes: [String]
    public let publicProtocols: [String]
    public let publicFunctions: [String]
}

public struct DependencyAnalysis {
    public let modules: [String]
    public let dependencies: [String: Set<String>]
    public let contracts: [String: ContractInfo]
    
    public func visualizeDependencies() -> String {
        var graph = "Module Dependency Graph:\n"
        graph += "========================\n\n"
        
        for module in modules {
            if let deps = dependencies[module], !deps.isEmpty {
                graph += "\(module) -> \(deps.joined(separator: ", "))\n"
            } else {
                graph += "\(module) -> (no dependencies)\n"
            }
        }
        
        return graph
    }
}

// MARK: - Xcode Integration

public struct XcodeLinterPlugin {
    public static func generateBuildPhaseScript() -> String {
        """
        #!/bin/bash
        
        # Archery Module Boundary Linter
        
        if which archery-lint > /dev/null; then
            archery-lint \\
                --project-root "$SRCROOT" \\
                --config "$SRCROOT/.archery-lint.json" \\
                --format xcode
        else
            echo "warning: Archery linter not installed. Run 'brew install archery-tools'"
        fi
        """
    }
    
    public static func generateSwiftLintIntegration() -> String {
        """
        custom_rules:
          archery_module_boundaries:
            name: "Module Boundary Violation"
            regex: "import\\s+(?!Foundation|SwiftUI|UIKit|Combine)([A-Z][a-zA-Z0-9]*(?!Contract))"
            message: "Direct module imports are not allowed. Import contracts instead."
            severity: error
        """
    }
}