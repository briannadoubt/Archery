import XCTest
@testable import Archery

final class ModularityTests: XCTestCase {
    
    // MARK: - Module System Tests
    
    @MainActor
    func testModuleRegistration() async throws {
        let registry = ModuleRegistry.shared
        registry.reset()

        struct TestContract: ModuleContract {
            let version = "1.0.0"
        }

        // Define a test module
        struct TestModule: FeatureModule {
            static let identifier = "TestModule"
            static let version = ModuleVersion(major: 1, minor: 0)
            static let dependencies: [ModuleDependency] = []
            typealias Contract = TestContract
            static let contract = TestContract()
            static let configuration = ModuleConfiguration(
                name: "TestModule",
                bundleIdentifier: "com.test.module"
            )
        }

        // Register module
        try registry.register(TestModule.self)

        // Verify registration
        let contract: TestContract? = registry.contract(for: "TestModule")
        XCTAssertNotNil(contract)
    }
    
    @MainActor
    func testCircularDependencyDetection() async throws {
        struct EmptyContract: ModuleContract {
            let version = "1.0.0"
        }

        // ModuleA has no dependencies - it registers first
        struct ModuleA: FeatureModule {
            static let identifier = "ModuleA"
            static let version = ModuleVersion(major: 1, minor: 0)
            static let dependencies: [ModuleDependency] = []
            typealias Contract = EmptyContract
            static let contract = EmptyContract()
            static let configuration = ModuleConfiguration(name: "ModuleA", bundleIdentifier: "com.test.a")
        }

        // ModuleB depends on ModuleA (valid)
        struct ModuleB: FeatureModule {
            static let identifier = "ModuleB"
            static let version = ModuleVersion(major: 1, minor: 0)
            static let dependencies = [
                ModuleDependency(identifier: "ModuleA")
            ]
            typealias Contract = EmptyContract
            static let contract = EmptyContract()
            static let configuration = ModuleConfiguration(name: "ModuleB", bundleIdentifier: "com.test.b")
        }

        // ModuleC depends on ModuleB, creating a chain A -> B -> C
        struct ModuleC: FeatureModule {
            static let identifier = "ModuleC"
            static let version = ModuleVersion(major: 1, minor: 0)
            static let dependencies = [
                ModuleDependency(identifier: "ModuleB")
            ]
            typealias Contract = EmptyContract
            static let contract = EmptyContract()
            static let configuration = ModuleConfiguration(name: "ModuleC", bundleIdentifier: "com.test.c")
        }

        let registry = ModuleRegistry.shared
        registry.reset()

        // Register modules in order - should all succeed
        try registry.register(ModuleA.self)
        try registry.register(ModuleB.self)
        try registry.register(ModuleC.self)

        // Verify all registered successfully
        let contractA: EmptyContract? = registry.contract(for: "ModuleA")
        let contractB: EmptyContract? = registry.contract(for: "ModuleB")
        let contractC: EmptyContract? = registry.contract(for: "ModuleC")
        XCTAssertNotNil(contractA)
        XCTAssertNotNil(contractB)
        XCTAssertNotNil(contractC)
    }
    
    func testVersionRequirements() {
        _ = ModuleVersion("1.2.3")

        // Test exact match
        XCTAssertTrue(VersionRequirement.exact("1.2.3").isSatisfied(by: "1.2.3"))
        XCTAssertFalse(VersionRequirement.exact("1.2.3").isSatisfied(by: "1.2.4"))
        
        // Test minimum
        XCTAssertTrue(VersionRequirement.minimum("1.0.0").isSatisfied(by: "1.2.3"))
        XCTAssertFalse(VersionRequirement.minimum("2.0.0").isSatisfied(by: "1.2.3"))
        
        // Test range
        XCTAssertTrue(VersionRequirement.range(min: "1.0.0", max: "2.0.0").isSatisfied(by: "1.5.0"))
        XCTAssertFalse(VersionRequirement.range(min: "1.0.0", max: "2.0.0").isSatisfied(by: "2.1.0"))
        
        // Test compatible
        XCTAssertTrue(VersionRequirement.compatible("1.2.0").isSatisfied(by: "1.2.3"))
        XCTAssertTrue(VersionRequirement.compatible("1.2.0").isSatisfied(by: "1.9.0"))
        XCTAssertFalse(VersionRequirement.compatible("1.2.0").isSatisfied(by: "2.0.0"))
    }
    
    func testModuleVersionParsing() {
        let v1 = ModuleVersion("1.2.3")
        XCTAssertEqual(v1.major, 1)
        XCTAssertEqual(v1.minor, 2)
        XCTAssertEqual(v1.patch, 3)
        
        let v2 = ModuleVersion("2.0.0-beta.1")
        XCTAssertEqual(v2.major, 2)
        XCTAssertEqual(v2.minor, 0)
        XCTAssertEqual(v2.patch, 0)
        XCTAssertEqual(v2.prerelease, "beta.1")
        
        let v3 = ModuleVersion("1.0.0+build.123")
        XCTAssertEqual(v3.build, "build.123")
    }
    
    func testModuleVersionComparison() {
        XCTAssertTrue(ModuleVersion("1.0.0") < ModuleVersion("2.0.0"))
        XCTAssertTrue(ModuleVersion("1.0.0") < ModuleVersion("1.1.0"))
        XCTAssertTrue(ModuleVersion("1.0.0") < ModuleVersion("1.0.1"))
        XCTAssertTrue(ModuleVersion("1.0.0-alpha") < ModuleVersion("1.0.0"))
        XCTAssertFalse(ModuleVersion("2.0.0") < ModuleVersion("1.9.9"))
    }
    
    // MARK: - Module Template Tests
    
    func testModuleTemplateGeneration() async throws {
        let generator = ModuleTemplateGenerator()
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        
        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }
        
        let module = try generator.generateModule(
            name: "TestFeature",
            type: .feature,
            outputPath: tempDir,
            dependencies: [
                ModuleDependency(identifier: "Core"),
                ModuleDependency(identifier: "Shared")
            ]
        )
        
        XCTAssertEqual(module.name, "TestFeature")
        XCTAssertTrue(module.files.count > 0)
        
        // Verify directory structure
        let sourcesPath = module.path.appendingPathComponent("Sources/TestFeature")
        XCTAssertTrue(FileManager.default.fileExists(atPath: sourcesPath.path))
        
        let testsPath = module.path.appendingPathComponent("Tests/TestFeatureTests")
        XCTAssertTrue(FileManager.default.fileExists(atPath: testsPath.path))
    }
    
    // MARK: - Build Configuration Tests
    
    @MainActor
    func testBuildConfigurationManager() {
        let manager = BuildConfigurationManager.shared
        
        // Test macro enablement
        XCTAssertTrue(manager.isMacroEnabled("Repository"))
        
        // Test macro settings
        let settings = manager.macroSettings(for: "Repository")
        XCTAssertTrue(settings.generateMocks)
        XCTAssertTrue(settings.generatePreviews)
        
        // Test compiler flags
        let flags = manager.compilerFlags()
        #if DEBUG
        XCTAssertTrue(flags.contains("-Onone"))
        XCTAssertTrue(flags.contains("-DDEBUG"))
        #else
        XCTAssertTrue(flags.contains("-O"))
        #endif
    }
    
    @MainActor
    func testPerformanceBudgets() {
        let manager = BuildConfigurationManager.shared
        
        // Test budget checks
        let buildTimeResult = manager.checkBudget(.buildTime, value: 30)
        XCTAssertTrue(buildTimeResult.isSuccess)
        
        let exceededResult = manager.checkBudget(.buildTime, value: 300)
        XCTAssertFalse(exceededResult.isSuccess)
        
        // Test binary size budget
        let binarySizeResult = manager.checkBudget(.binarySize, value: 30_000_000)
        XCTAssertTrue(binarySizeResult.isSuccess)
    }
    
    func testMacroOutputConfiguration() {
        let config = MacroOutputConfiguration.production
        
        // Production should disable debug-only macros
        XCTAssertTrue(config.isEnabled("Repository"))
        XCTAssertTrue(config.isEnabled("ObservableViewModel"))
        
        // Test custom settings
        var customConfig = MacroOutputConfiguration()
        customConfig.disabledMacros = ["TestMacro"]
        XCTAssertFalse(customConfig.isEnabled("TestMacro"))
        
        customConfig.enabledMacros = ["SpecificMacro"]
        XCTAssertTrue(customConfig.isEnabled("SpecificMacro"))
        XCTAssertFalse(customConfig.isEnabled("OtherMacro"))
    }
    
    // MARK: - Incremental Codegen Tests
    
    func testIncrementalCodeGeneration() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }
        
        let generator = try IncrementalCodeGenerator(cacheDirectory: tempDir)
        
        let inputs = [
            CodegenInput(
                identifier: "UserRepository",
                name: "UserRepository",
                macroType: "Repository",
                sourceFile: "User.swift"
            ),
            CodegenInput(
                identifier: "PostViewModel",
                name: "PostViewModel",
                macroType: "ObservableViewModel",
                sourceFile: "Post.swift"
            )
        ]
        
        let outputDir = tempDir.appendingPathComponent("output")
        
        // First generation - should generate all
        let result1 = try await generator.generate(
            inputs: inputs,
            outputDirectory: outputDir,
            configuration: .debug
        )
        
        XCTAssertEqual(result1.generated.count, 2)
        XCTAssertEqual(result1.skipped.count, 0)
        
        // Second generation with same inputs - should skip all
        let result2 = try await generator.generate(
            inputs: inputs,
            outputDirectory: outputDir,
            configuration: .debug
        )
        
        XCTAssertEqual(result2.generated.count, 0) // Nothing regenerated
    }
    
    func testCodegenSharding() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }
        
        let generator = try IncrementalCodeGenerator(
            cacheDirectory: tempDir,
            shardSize: 2 // Small shard size for testing
        )
        
        // Create many inputs
        let inputs = (0..<10).map { i in
            CodegenInput(
                identifier: "Module\(i)",
                name: "Module\(i)",
                macroType: "Repository",
                sourceFile: "Module\(i).swift"
            )
        }
        
        let outputDir = tempDir.appendingPathComponent("output")
        
        let result = try await generator.generate(
            inputs: inputs,
            outputDirectory: outputDir,
            configuration: .debug
        )
        
        XCTAssertEqual(result.generated.count, 10)
        // With shard size of 2, should create 5 shards
    }
    
    // MARK: - Module Linter Tests

    @MainActor
    func testModuleBoundaryLinter() async throws {
        let linter = ModuleBoundaryLinter()
        
        // Create test files
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }
        
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        
        // Valid import (contract)
        let validFile = tempDir.appendingPathComponent("Valid.swift")
        try """
        import Foundation
        import CoreContract
        
        struct MyFeature {}
        """.write(to: validFile, atomically: true, encoding: .utf8)
        
        // Invalid import (direct module)
        let invalidFile = tempDir.appendingPathComponent("Invalid.swift")
        try """
        import Foundation
        import OtherModule // This is not allowed!
        
        struct MyFeature {}
        """.write(to: invalidFile, atomically: true, encoding: .utf8)
        
        let result = try await linter.lint(
            module: "TestModule",
            sourceFiles: [validFile, invalidFile]
        )
        
        XCTAssertFalse(result.passed)
        XCTAssertEqual(result.violations.count, 1)
        XCTAssertEqual(result.violations.first?.type, .illegalImport)
    }
    
    func testLinterConfiguration() throws {
        var config = LinterConfiguration()
        config.sharedModules = ["Core", "Common"]
        config.allowedImports = [
            "FeatureA": ["FeatureBContract", "Core"]
        ]
        
        // Test configuration serialization
        let tempFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString).json")
        defer {
            try? FileManager.default.removeItem(at: tempFile)
        }
        
        try config.save(to: tempFile)
        let loaded = try LinterConfiguration.load(from: tempFile)
        
        XCTAssertEqual(loaded.sharedModules, config.sharedModules)
        XCTAssertEqual(loaded.allowedImports["FeatureA"], config.allowedImports["FeatureA"])
    }
    
    // MARK: - CI Integration Tests
    
    func testCIBuildExecution() async throws {
        let config = CIConfiguration.default
        _ = CIIntegration(configuration: config)

        // This would run actual build in real scenario
        // For testing, we'll verify configuration
        XCTAssertNotNil(config.budgets)
        XCTAssertTrue(config.cache.enabled)
    }
    
    func testPerformanceMonitoring() {
        let monitor = PerformanceMonitor(budgets: .default)

        var metrics = BuildMetrics()
        metrics.buildTime = 120 // 120 seconds - exceeds default 60s
        metrics.binarySize = 80_000_000 // 80 MB - exceeds default 50 MB
        metrics.symbolCount = 150_000 // exceeds default 100,000

        let results = monitor.checkBudgets(metrics)
        XCTAssertFalse(results.violations.isEmpty) // Should have violations with default budgets
    }
    
    func testGitHubActionsGeneration() {
        let workflow = GitHubActionsGenerator.generateWorkflow(
            configuration: .default
        )
        
        XCTAssertTrue(workflow.contains("name: Archery CI"))
        XCTAssertTrue(workflow.contains("Run Module Linter"))
        XCTAssertTrue(workflow.contains("Check Performance Budgets"))
        XCTAssertTrue(workflow.contains("cache"))
    }
    
    // MARK: - Integration Tests
    
    @MainActor
    func testFullModuleWorkflow() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }
        
        // 1. Generate module
        let generator = ModuleTemplateGenerator()
        let module = try generator.generateModule(
            name: "UserFeature",
            type: .feature,
            outputPath: tempDir
        )
        
        // 2. Generate code incrementally
        let codegen = try IncrementalCodeGenerator(cacheDirectory: tempDir)
        let inputs = [
            CodegenInput(
                identifier: "UserRepository",
                name: "UserRepository",
                macroType: "Repository",
                module: "UserFeature",
                sourceFile: module.path.appendingPathComponent("Sources/UserFeature/Models/UserRepository.swift").path
            )
        ]
        
        let outputDir = module.path.appendingPathComponent("Generated")
        let result = try await codegen.generate(
            inputs: inputs,
            outputDirectory: outputDir,
            configuration: .debug
        )
        
        XCTAssertEqual(result.generated.count, 1)
        
        // 3. Lint module
        let linter = ModuleBoundaryLinter()
        let lintResult = try await linter.lint(
            module: "UserFeature",
            sourceFiles: module.files.map { URL(fileURLWithPath: $0.name) }
        )
        
        XCTAssertTrue(lintResult.passed)
    }
}

// MARK: - Test Helpers

extension ModularityTests {
    struct EmptyContract: ModuleContract {
        let version = "1.0.0"
    }
}