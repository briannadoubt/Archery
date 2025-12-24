import Foundation
import CryptoKit

// MARK: - Incremental Code Generation System

/// Manages incremental and sharded code generation
public actor IncrementalCodeGenerator {
    private let fileManager = FileManager.default
    private let cacheDirectory: URL
    private let manifestPath: URL
    private var manifest: CodegenManifest
    private let shardSize: Int

    public init(
        cacheDirectory: URL? = nil,
        shardSize: Int = 100 // Files per shard
    ) throws {
        let cacheDir = cacheDirectory ?? Self.defaultCacheDirectory()
        self.cacheDirectory = cacheDir
        self.manifestPath = cacheDir.appendingPathComponent("codegen-manifest.json")
        self.shardSize = shardSize

        // Create cache directory if needed
        try fileManager.createDirectory(
            at: cacheDir,
            withIntermediateDirectories: true,
            attributes: nil
        )

        // Load or create manifest
        if fileManager.fileExists(atPath: manifestPath.path) {
            let data = try Data(contentsOf: manifestPath)
            self.manifest = try JSONDecoder().decode(CodegenManifest.self, from: data)
        } else {
            self.manifest = CodegenManifest()
        }
    }
    
    // MARK: - Public API
    
    /// Generate code incrementally
    public func generate(
        inputs: [CodegenInput],
        outputDirectory: URL,
        configuration: BuildConfiguration
    ) async throws -> CodegenResult {
        var results = CodegenResult()
        
        // Determine what needs regeneration
        let changes = try detectChanges(inputs: inputs)
        
        // Shard the work
        let shards = createShards(from: changes.needsGeneration)
        
        // Process shards in parallel
        // Capture immutable copies to satisfy Sendable requirements
        let shardsCopy = shards
        let outputDir = outputDirectory
        let config = configuration

        for (index, shard) in shardsCopy.enumerated() {
            let shardResult = try? await processShard(
                shard,
                index: index,
                outputDirectory: outputDir,
                configuration: config
            )
            if let result = shardResult {
                results.merge(result.result)
            }
        }
        
        // Update manifest
        try updateManifest(with: results)
        
        // Clean up removed files
        try cleanupRemovedFiles(changes.removed, outputDirectory: outputDirectory)
        
        return results
    }
    
    /// Clear cache and force full regeneration
    public func clearCache() throws {
        try fileManager.removeItem(at: cacheDirectory)
        try fileManager.createDirectory(
            at: cacheDirectory,
            withIntermediateDirectories: true,
            attributes: nil
        )
        manifest = CodegenManifest()
    }
    
    // MARK: - Change Detection
    
    private func detectChanges(inputs: [CodegenInput]) throws -> ChangeSet {
        var needsGeneration: [CodegenInput] = []
        var unchanged: [CodegenInput] = []
        var removed: [String] = []
        
        // Check existing entries
        var currentInputIds = Set<String>()
        
        for input in inputs {
            currentInputIds.insert(input.identifier)
            
            if let entry = manifest.entries[input.identifier] {
                // Check if input has changed
                let currentHash = try computeHash(for: input)
                if currentHash != entry.inputHash {
                    needsGeneration.append(input)
                } else if !fileExists(entry.outputPath) {
                    // Output file missing, regenerate
                    needsGeneration.append(input)
                } else {
                    unchanged.append(input)
                }
            } else {
                // New input
                needsGeneration.append(input)
            }
        }
        
        // Find removed inputs
        for identifier in manifest.entries.keys {
            if !currentInputIds.contains(identifier) {
                removed.append(identifier)
            }
        }
        
        return ChangeSet(
            needsGeneration: needsGeneration,
            unchanged: unchanged,
            removed: removed
        )
    }
    
    private func computeHash(for input: CodegenInput) throws -> String {
        let hasher = SHA256()
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let data = try encoder.encode(input)
        let hash = hasher.finalize(data: data)
        return hash.compactMap { String(format: "%02x", $0) }.joined()
    }
    
    private func fileExists(_ path: String) -> Bool {
        return fileManager.fileExists(atPath: path)
    }
    
    // MARK: - Sharding
    
    private func createShards(from inputs: [CodegenInput]) -> [[CodegenInput]] {
        guard !inputs.isEmpty else { return [] }
        
        var shards: [[CodegenInput]] = []
        var currentShard: [CodegenInput] = []
        
        for input in inputs {
            currentShard.append(input)
            
            if currentShard.count >= shardSize {
                shards.append(currentShard)
                currentShard = []
            }
        }
        
        if !currentShard.isEmpty {
            shards.append(currentShard)
        }
        
        return shards
    }
    
    private func processShard(
        _ inputs: [CodegenInput],
        index: Int,
        outputDirectory: URL,
        configuration: BuildConfiguration
    ) async throws -> ShardResult {
        let shardId = "shard_\(index)"
        var result = CodegenResult()
        
        for input in inputs {
            // Check if macro is enabled
            guard configuration.macroOutputs.isEnabled(input.macroType) else {
                result.skipped.append(input.identifier)
                continue
            }
            
            do {
                // Generate code
                let output = try await generateCode(
                    for: input,
                    configuration: configuration
                )
                
                // Write output
                let outputPath = outputDirectory
                    .appendingPathComponent(output.relativePath)
                    .appendingPathComponent(output.filename)
                
                try writeOutput(output, to: outputPath)
                
                // Update manifest entry
                let entry = ManifestEntry(
                    inputHash: try computeHash(for: input),
                    outputPath: outputPath.path,
                    timestamp: Date(),
                    macroType: input.macroType,
                    contentHash: output.contentHash
                )
                
                result.generated.append(GeneratedOutput(
                    identifier: input.identifier,
                    path: outputPath,
                    entry: entry
                ))
                
            } catch {
                result.errors.append(CodegenError(
                    identifier: input.identifier,
                    error: error
                ))
            }
        }
        
        return ShardResult(id: shardId, result: result)
    }
    
    private func generateCode(
        for input: CodegenInput,
        configuration: BuildConfiguration
    ) async throws -> CodeOutput {
        // Simulate code generation based on macro type
        let settings = configuration.macroOutputs.settings(for: input.macroType)
        
        var content = """
        // Generated by Archery - \(input.macroType)
        // Input: \(input.identifier)
        // Timestamp: \(Date())
        
        import Foundation
        import Archery
        
        """
        
        // Add generated code based on macro type and settings
        content += generateMacroSpecificCode(
            input: input,
            settings: settings
        )
        
        // Add mocks if enabled
        if settings.generateMocks {
            content += "\n\n// MARK: - Mocks\n\n"
            content += generateMockCode(for: input)
        }
        
        // Add previews if enabled
        if settings.generatePreviews {
            content += "\n\n// MARK: - Previews\n\n"
            content += generatePreviewCode(for: input)
        }
        
        // Add tests if enabled
        if settings.generateTests {
            content += "\n\n// MARK: - Tests\n\n"
            content += generateTestCode(for: input)
        }
        
        // Compute content hash
        let contentHash = SHA256.hash(data: content.data(using: .utf8)!)
            .compactMap { String(format: "%02x", $0) }
            .joined()
        
        return CodeOutput(
            filename: "\(input.name).generated.swift",
            relativePath: input.module ?? "",
            content: content,
            contentHash: contentHash
        )
    }
    
    private func generateMacroSpecificCode(
        input: CodegenInput,
        settings: MacroSettings
    ) -> String {
        // Generate based on macro type
        switch input.macroType {
        case "Repository":
            return """
            public protocol \(input.name)Repository {
                func fetch() async throws -> [\(input.name)Model]
            }
            
            public final class Live\(input.name)Repository: \(input.name)Repository {
                public func fetch() async throws -> [\(input.name)Model] {
                    // Implementation
                    return []
                }
            }
            """
            
        case "ObservableViewModel":
            return """
            @MainActor
            @Observable
            public final class \(input.name)ViewModel {
                public var state: LoadState<[\(input.name)Model]> = .idle
                
                public func load() async {
                    state = .loading
                    // Implementation
                }
            }
            """
            
        default:
            return "// Generated code for \(input.macroType)"
        }
    }
    
    private func generateMockCode(for input: CodegenInput) -> String {
        return """
        #if DEBUG
        public final class Mock\(input.name): \(input.name)Protocol {
            // Mock implementation
        }
        #endif
        """
    }
    
    private func generatePreviewCode(for input: CodegenInput) -> String {
        return """
        #if DEBUG
        struct \(input.name)_Previews: PreviewProvider {
            static var previews: some View {
                \(input.name)View()
            }
        }
        #endif
        """
    }
    
    private func generateTestCode(for input: CodegenInput) -> String {
        return """
        #if DEBUG
        extension \(input.name)Tests {
            static func makeTestInstance() -> \(input.name) {
                // Test instance
                return \(input.name)()
            }
        }
        #endif
        """
    }
    
    private func writeOutput(_ output: CodeOutput, to url: URL) throws {
        let directory = url.deletingLastPathComponent()
        try fileManager.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: nil
        )
        try output.content.write(to: url, atomically: true, encoding: .utf8)
    }
    
    // MARK: - Manifest Management
    
    private func updateManifest(with result: CodegenResult) throws {
        for generated in result.generated {
            manifest.entries[generated.identifier] = generated.entry
        }
        manifest.lastUpdated = Date()
        
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(manifest)
        try data.write(to: manifestPath)
    }
    
    private func cleanupRemovedFiles(_ removed: [String], outputDirectory: URL) throws {
        for identifier in removed {
            if let entry = manifest.entries[identifier] {
                let path = URL(fileURLWithPath: entry.outputPath)
                if fileManager.fileExists(atPath: path.path) {
                    try fileManager.removeItem(at: path)
                }
                manifest.entries.removeValue(forKey: identifier)
            }
        }
    }
    
    private static func defaultCacheDirectory() -> URL {
        let cacheDir = FileManager.default.urls(
            for: .cachesDirectory,
            in: .userDomainMask
        ).first!
        return cacheDir.appendingPathComponent("com.archery.codegen")
    }
}

// MARK: - Supporting Types

public struct CodegenInput: Codable, Sendable {
    public let identifier: String
    public let name: String
    public let macroType: String
    public let module: String?
    public let sourceFile: String
    public let configuration: [String: String]
    
    public init(
        identifier: String,
        name: String,
        macroType: String,
        module: String? = nil,
        sourceFile: String,
        configuration: [String: String] = [:]
    ) {
        self.identifier = identifier
        self.name = name
        self.macroType = macroType
        self.module = module
        self.sourceFile = sourceFile
        self.configuration = configuration
    }
}

struct CodeOutput {
    let filename: String
    let relativePath: String
    let content: String
    let contentHash: String
}

struct CodegenManifest: Codable {
    var entries: [String: ManifestEntry] = [:]
    var lastUpdated: Date = Date()
    var version: String = "1.0.0"
}

struct ManifestEntry: Codable, Sendable {
    let inputHash: String
    let outputPath: String
    let timestamp: Date
    let macroType: String
    let contentHash: String
}

struct ChangeSet {
    let needsGeneration: [CodegenInput]
    let unchanged: [CodegenInput]
    let removed: [String]
}

public struct CodegenResult: Sendable {
    public var generated: [GeneratedOutput] = []
    public var skipped: [String] = []
    public var errors: [CodegenError] = []
    
    mutating func merge(_ other: CodegenResult) {
        generated.append(contentsOf: other.generated)
        skipped.append(contentsOf: other.skipped)
        errors.append(contentsOf: other.errors)
    }
    
    public var summary: String {
        """
        Code Generation Summary:
        ✅ Generated: \(generated.count) files
        ⏭️ Skipped: \(skipped.count) files
        ❌ Errors: \(errors.count)
        """
    }
}

public struct GeneratedOutput: Sendable {
    public let identifier: String
    public let path: URL
    let entry: ManifestEntry
}

public struct CodegenError: Sendable {
    public let identifier: String
    public let error: Error
    
    public var description: String {
        "[\(identifier)] \(error.localizedDescription)"
    }
}

struct ShardResult: Sendable {
    let id: String
    let result: CodegenResult
}

// MARK: - SHA256 Extension

extension SHA256 {
    func finalize(data: Data) -> [UInt8] {
        var hasher = self
        hasher.update(data: data)
        let digest = hasher.finalize()
        return Array(digest)
    }
}