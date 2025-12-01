import Foundation

// MARK: - Module Template Generator

public final class ModuleTemplateGenerator {
    private let fileManager = FileManager.default
    
    public init() {}
    
    /// Generate a new feature module from template
    public func generateModule(
        name: String,
        type: ModuleType,
        outputPath: URL,
        dependencies: [ModuleDependency] = [],
        platforms: [Platform] = Platform.all
    ) throws -> GeneratedModule {
        // Create module directory structure
        let modulePath = outputPath.appendingPathComponent(name)
        try createDirectoryStructure(at: modulePath, for: type)
        
        // Generate module files
        let configuration = ModuleConfiguration(
            name: name,
            bundleIdentifier: "com.archery.modules.\(name.lowercased())",
            platforms: platforms
        )
        
        let files = try generateModuleFiles(
            name: name,
            type: type,
            configuration: configuration,
            dependencies: dependencies,
            at: modulePath
        )
        
        // Generate Package.swift if needed
        if type.requiresPackageManifest {
            try generatePackageManifest(
                name: name,
                configuration: configuration,
                dependencies: dependencies,
                at: modulePath
            )
        }
        
        // Generate tests
        try generateTests(name: name, type: type, at: modulePath)
        
        return GeneratedModule(
            name: name,
            path: modulePath,
            files: files,
            configuration: configuration
        )
    }
    
    // MARK: - Directory Structure
    
    private func createDirectoryStructure(at path: URL, for type: ModuleType) throws {
        let directories = [
            "Sources",
            "Sources/\(path.lastPathComponent)",
            "Sources/\(path.lastPathComponent)/Contract",
            "Sources/\(path.lastPathComponent)/Internal",
            "Sources/\(path.lastPathComponent)/Models",
            "Sources/\(path.lastPathComponent)/Views",
            "Tests",
            "Tests/\(path.lastPathComponent)Tests",
            "Resources"
        ]
        
        for directory in directories {
            let dirPath = path.appendingPathComponent(directory)
            try fileManager.createDirectory(
                at: dirPath,
                withIntermediateDirectories: true,
                attributes: nil
            )
        }
    }
    
    // MARK: - File Generation
    
    private func generateModuleFiles(
        name: String,
        type: ModuleType,
        configuration: ModuleConfiguration,
        dependencies: [ModuleDependency],
        at path: URL
    ) throws -> [GeneratedFile] {
        var files: [GeneratedFile] = []
        
        // Generate module definition
        let moduleFile = try generateModuleDefinition(
            name: name,
            type: type,
            configuration: configuration,
            dependencies: dependencies
        )
        files.append(moduleFile)
        try moduleFile.write(to: path.appendingPathComponent("Sources/\(name)/\(name)Module.swift"))
        
        // Generate contract
        let contractFile = try generateContract(name: name, type: type)
        files.append(contractFile)
        try contractFile.write(to: path.appendingPathComponent("Sources/\(name)/Contract/\(name)Contract.swift"))
        
        // Generate type-specific files
        switch type {
        case .feature:
            let featureFiles = try generateFeatureFiles(name: name)
            files.append(contentsOf: featureFiles)
            for file in featureFiles {
                try file.write(to: path.appendingPathComponent("Sources/\(name)/\(file.name)"))
            }
            
        case .shared:
            let sharedFiles = try generateSharedFiles(name: name)
            files.append(contentsOf: sharedFiles)
            for file in sharedFiles {
                try file.write(to: path.appendingPathComponent("Sources/\(name)/\(file.name)"))
            }
            
        case .core:
            let coreFiles = try generateCoreFiles(name: name)
            files.append(contentsOf: coreFiles)
            for file in coreFiles {
                try file.write(to: path.appendingPathComponent("Sources/\(name)/\(file.name)"))
            }
        }
        
        return files
    }
    
    private func generateModuleDefinition(
        name: String,
        type: ModuleType,
        configuration: ModuleConfiguration,
        dependencies: [ModuleDependency]
    ) -> GeneratedFile {
        let dependenciesCode = dependencies.map { dep in
            """
                ModuleDependency(
                    identifier: "\(dep.identifier)",
                    version: \(versionRequirementCode(dep.version)),
                    isOptional: \(dep.isOptional)
                )
            """
        }.joined(separator: ",\n        ")
        
        let content = """
        import Foundation
        import Archery
        
        public struct \(name)Module: FeatureModule {
            public static let identifier = "\(name)"
            public static let version = ModuleVersion(major: 1, minor: 0, patch: 0)
            
            public static let dependencies: [ModuleDependency] = [
                \(dependenciesCode)
            ]
            
            public typealias Contract = \(name)Contract
            
            public static let configuration = ModuleConfiguration(
                name: "\(name)",
                bundleIdentifier: "\(configuration.bundleIdentifier)",
                platforms: \(platformsCode(configuration.platforms))
            )
        }
        
        // MARK: - Module Initialization
        
        public extension \(name)Module {
            static func initialize() async throws {
                // Register with module registry
                try await ModuleRegistry.shared.register(self)
                
                // Module-specific initialization
                await initializeInternal()
            }
            
            private static func initializeInternal() async {
                // Add module-specific initialization here
            }
        }
        """
        
        return GeneratedFile(name: "\(name)Module.swift", content: content)
    }
    
    private func generateContract(name: String, type: ModuleType) -> GeneratedFile {
        let content = """
        import Foundation
        import Archery
        
        /// Public contract for \(name) module
        public struct \(name)Contract: ModuleContract {
            public let version = "1.0.0"
            
            // MARK: - Public API
            
            /// Public types exposed by this module
            public struct Types {
                // Add public types here
            }
            
            /// Public protocols exposed by this module
            public struct Protocols {
                // Add public protocols here
            }
            
            /// Public functions exposed by this module
            public struct Functions {
                // Add public functions here
            }
        }
        
        // MARK: - Contract Extensions
        
        public extension \(name)Contract {
            /// Validate contract compatibility
            func validate() throws {
                // Add contract validation logic
            }
        }
        """
        
        return GeneratedFile(name: "\(name)Contract.swift", content: content)
    }
    
    private func generateFeatureFiles(name: String) -> [GeneratedFile] {
        var files: [GeneratedFile] = []
        
        // View Model
        let viewModel = GeneratedFile(
            name: "Views/\(name)ViewModel.swift",
            content: """
            import SwiftUI
            import Archery
            
            @MainActor
            @Observable
            public final class \(name)ViewModel: ObservableObject {
                // MARK: - State
                
                public enum State {
                    case idle
                    case loading
                    case loaded
                    case error(Error)
                }
                
                public var state: State = .idle
                
                // MARK: - Dependencies
                
                private let repository: \(name)Repository
                
                // MARK: - Initialization
                
                public init(repository: \(name)Repository) {
                    self.repository = repository
                }
                
                // MARK: - Actions
                
                public func load() async {
                    state = .loading
                    
                    do {
                        // Load data
                        state = .loaded
                    } catch {
                        state = .error(error)
                    }
                }
            }
            """
        )
        files.append(viewModel)
        
        // View
        let view = GeneratedFile(
            name: "Views/\(name)View.swift",
            content: """
            import SwiftUI
            import Archery
            
            public struct \(name)View: View {
                @StateObject private var viewModel: \(name)ViewModel
                
                public init(viewModel: \(name)ViewModel) {
                    self._viewModel = StateObject(wrappedValue: viewModel)
                }
                
                public var body: some View {
                    Group {
                        switch viewModel.state {
                        case .idle:
                            ContentUnavailableView(
                                "Ready",
                                systemImage: "checkmark.circle"
                            )
                            
                        case .loading:
                            ProgressView()
                            
                        case .loaded:
                            contentView
                            
                        case .error(let error):
                            ContentUnavailableView(
                                "Error",
                                systemImage: "exclamationmark.triangle",
                                description: Text(error.localizedDescription)
                            )
                        }
                    }
                    .task {
                        await viewModel.load()
                    }
                }
                
                private var contentView: some View {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            Text("\(name) Feature")
                                .font(.largeTitle)
                                .bold()
                            
                            Text("Add your content here")
                                .foregroundColor(.secondary)
                        }
                        .padding()
                    }
                }
            }
            
            // MARK: - Previews
            
            struct \(name)View_Previews: PreviewProvider {
                static var previews: some View {
                    \(name)View(
                        viewModel: \(name)ViewModel(
                            repository: Mock\(name)Repository()
                        )
                    )
                }
            }
            """
        )
        files.append(view)
        
        // Repository
        let repository = GeneratedFile(
            name: "Models/\(name)Repository.swift",
            content: """
            import Foundation
            import Archery
            
            public protocol \(name)Repository: Sendable {
                func fetchData() async throws -> [\(name)Model]
            }
            
            public final class Live\(name)Repository: \(name)Repository {
                public init() {}
                
                public func fetchData() async throws -> [\(name)Model] {
                    // Implement actual data fetching
                    return []
                }
            }
            
            public final class Mock\(name)Repository: \(name)Repository {
                public init() {}
                
                public func fetchData() async throws -> [\(name)Model] {
                    // Return mock data
                    return [\(name)Model.mock()]
                }
            }
            """
        )
        files.append(repository)
        
        // Model
        let model = GeneratedFile(
            name: "Models/\(name)Model.swift",
            content: """
            import Foundation
            
            public struct \(name)Model: Codable, Identifiable, Sendable {
                public let id: String
                public let title: String
                public let description: String?
                public let createdAt: Date
                
                public init(
                    id: String = UUID().uuidString,
                    title: String,
                    description: String? = nil,
                    createdAt: Date = Date()
                ) {
                    self.id = id
                    self.title = title
                    self.description = description
                    self.createdAt = createdAt
                }
                
                public static func mock() -> \(name)Model {
                    \(name)Model(
                        title: "Mock \(name)",
                        description: "This is a mock model for testing"
                    )
                }
            }
            """
        )
        files.append(model)
        
        return files
    }
    
    private func generateSharedFiles(name: String) -> [GeneratedFile] {
        // Generate files for shared modules (utilities, extensions, etc.)
        return [
            GeneratedFile(
                name: "Internal/\(name)Utilities.swift",
                content: """
                import Foundation
                
                internal enum \(name)Utilities {
                    // Add shared utilities here
                }
                """
            )
        ]
    }
    
    private func generateCoreFiles(name: String) -> [GeneratedFile] {
        // Generate files for core modules (fundamental functionality)
        return [
            GeneratedFile(
                name: "Internal/\(name)Core.swift",
                content: """
                import Foundation
                
                public enum \(name)Core {
                    // Add core functionality here
                }
                """
            )
        ]
    }
    
    // MARK: - Package Manifest
    
    private func generatePackageManifest(
        name: String,
        configuration: ModuleConfiguration,
        dependencies: [ModuleDependency],
        at path: URL
    ) throws {
        let platforms = configuration.platforms.map { platform in
            ".\(platform.name.lowercased())(.v\(platform.minimumVersion.replacingOccurrences(of: ".", with: "_")))"
        }.joined(separator: ",\n        ")
        
        let deps = dependencies.map { dep in
            """
                .package(
                    name: "\(dep.identifier)",
                    path: "../\(dep.identifier)"
                )
            """
        }.joined(separator: ",\n        ")
        
        let targetDeps = dependencies.map { dep in
            "\".product(name: \\\"\(dep.identifier)\\\", package: \\\"\(dep.identifier)\\\")\""
        }.joined(separator: ",\n                ")
        
        let content = """
        // swift-tools-version:6.0
        import PackageDescription
        
        let package = Package(
            name: "\(name)",
            platforms: [
                \(platforms)
            ],
            products: [
                .library(
                    name: "\(name)",
                    targets: ["\(name)"]
                )
            ],
            dependencies: [
                .package(path: "../../"),
                \(deps)
            ],
            targets: [
                .target(
                    name: "\(name)",
                    dependencies: [
                        .product(name: "Archery", package: "Archery"),
                        \(targetDeps)
                    ],
                    resources: [
                        .process("Resources")
                    ]
                ),
                .testTarget(
                    name: "\(name)Tests",
                    dependencies: ["\(name)"]
                )
            ]
        )
        """
        
        let file = GeneratedFile(name: "Package.swift", content: content)
        try file.write(to: path.appendingPathComponent("Package.swift"))
    }
    
    // MARK: - Test Generation
    
    private func generateTests(name: String, type: ModuleType, at path: URL) throws {
        let testContent = """
        import XCTest
        @testable import \(name)
        @testable import Archery
        
        final class \(name)ModuleTests: XCTestCase {
            
            func testModuleRegistration() async throws {
                // Test module can be registered
                let registry = ModuleRegistry.shared
                try await \(name)Module.initialize()
                
                // Verify module is registered
                let contract: \(name)Contract? = registry.contract(for: \(name)Module.identifier)
                XCTAssertNotNil(contract)
            }
            
            func testModuleDependencies() {
                // Test dependencies are properly defined
                let dependencies = \(name)Module.dependencies
                
                // Add specific dependency tests
                for dependency in dependencies {
                    if !dependency.isOptional {
                        // Verify required dependencies
                        XCTAssertFalse(dependency.identifier.isEmpty)
                    }
                }
            }
            
            func testModuleContract() throws {
                // Test contract validation
                let contract = \(name)Contract()
                XCTAssertNoThrow(try contract.validate())
            }
        }
        """
        
        let testFile = GeneratedFile(name: "\(name)ModuleTests.swift", content: testContent)
        try testFile.write(to: path.appendingPathComponent("Tests/\(name)Tests/\(name)ModuleTests.swift"))
    }
    
    // MARK: - Helper Methods
    
    private func versionRequirementCode(_ requirement: VersionRequirement) -> String {
        switch requirement {
        case .any:
            return ".any"
        case .exact(let v):
            return ".exact(\"\(v)\")"
        case .minimum(let v):
            return ".minimum(\"\(v)\")"
        case .range(let min, let max):
            return ".range(min: \"\(min)\", max: \"\(max)\")"
        case .compatible(let v):
            return ".compatible(\"\(v)\")"
        }
    }
    
    private func platformsCode(_ platforms: [Platform]) -> String {
        let platformList = platforms.map { "Platform.\($0.name.lowercased())" }
            .joined(separator: ", ")
        return "[\(platformList)]"
    }
}

// MARK: - Supporting Types

public enum ModuleType {
    case feature    // UI feature module
    case shared     // Shared utilities/extensions
    case core       // Core business logic
    
    var requiresPackageManifest: Bool {
        return true // All modules get their own Package.swift for true isolation
    }
}

public struct GeneratedModule {
    public let name: String
    public let path: URL
    public let files: [GeneratedFile]
    public let configuration: ModuleConfiguration
}

public struct GeneratedFile {
    public let name: String
    public let content: String
    
    func write(to url: URL) throws {
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: nil
        )
        try content.write(to: url, atomically: true, encoding: .utf8)
    }
}