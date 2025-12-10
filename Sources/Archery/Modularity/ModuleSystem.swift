import Foundation

// MARK: - Module System Core

/// Defines a feature module with its boundaries and contracts
public protocol FeatureModule {
    /// Unique identifier for this module
    static var identifier: String { get }
    
    /// Module version for compatibility checking
    static var version: ModuleVersion { get }
    
    /// Dependencies on other modules (contracts only)
    static var dependencies: [ModuleDependency] { get }
    
    /// Public contract exposed by this module
    associatedtype Contract: ModuleContract
    
    /// Module configuration
    static var configuration: ModuleConfiguration { get }
}

/// Public contract that modules expose to others
public protocol ModuleContract {
    /// Contract version for compatibility
    var version: String { get }
}

/// Module dependency specification
public struct ModuleDependency: Hashable, Codable, Sendable {
    public let identifier: String
    public let version: VersionRequirement
    public let isOptional: Bool
    
    public init(
        identifier: String,
        version: VersionRequirement = .any,
        isOptional: Bool = false
    ) {
        self.identifier = identifier
        self.version = version
        self.isOptional = isOptional
    }
}

/// Version requirement for dependencies
public enum VersionRequirement: Hashable, Codable, Sendable {
    case any
    case exact(String)
    case minimum(String)
    case range(min: String, max: String)
    case compatible(String) // ~> 1.0.0 (compatible with)
    
    public func isSatisfied(by version: String) -> Bool {
        switch self {
        case .any:
            return true
        case .exact(let required):
            return version == required
        case .minimum(let min):
            return ModuleVersion(version) >= ModuleVersion(min)
        case .range(let min, let max):
            let v = ModuleVersion(version)
            return v >= ModuleVersion(min) && v <= ModuleVersion(max)
        case .compatible(let base):
            let baseVersion = ModuleVersion(base)
            let currentVersion = ModuleVersion(version)
            return currentVersion.major == baseVersion.major &&
                   currentVersion >= baseVersion
        }
    }
}

/// Module version with semantic versioning
public struct ModuleVersion: Comparable, Hashable, Codable, CustomStringConvertible, Sendable {
    public let major: Int
    public let minor: Int
    public let patch: Int
    public let prerelease: String?
    public let build: String?
    
    public init(_ string: String) {
        let components = string.split(separator: ".")
        self.major = Int(components[safe: 0] ?? "0") ?? 0
        self.minor = Int(components[safe: 1] ?? "0") ?? 0
        self.patch = Int(components[safe: 2] ?? "0") ?? 0
        
        // Parse prerelease and build metadata
        if let patchAndMore = components[safe: 2] {
            let parts = patchAndMore.split(separator: "-", maxSplits: 1)
            if parts.count > 1 {
                let prereleaseAndBuild = parts[1].split(separator: "+", maxSplits: 1)
                self.prerelease = String(prereleaseAndBuild[0])
                self.build = prereleaseAndBuild.count > 1 ? String(prereleaseAndBuild[1]) : nil
            } else {
                let patchParts = parts[0].split(separator: "+", maxSplits: 1)
                self.prerelease = nil
                self.build = patchParts.count > 1 ? String(patchParts[1]) : nil
            }
        } else {
            self.prerelease = nil
            self.build = nil
        }
    }
    
    public init(
        major: Int,
        minor: Int = 0,
        patch: Int = 0,
        prerelease: String? = nil,
        build: String? = nil
    ) {
        self.major = major
        self.minor = minor
        self.patch = patch
        self.prerelease = prerelease
        self.build = build
    }
    
    public static func < (lhs: ModuleVersion, rhs: ModuleVersion) -> Bool {
        if lhs.major != rhs.major { return lhs.major < rhs.major }
        if lhs.minor != rhs.minor { return lhs.minor < rhs.minor }
        if lhs.patch != rhs.patch { return lhs.patch < rhs.patch }
        
        // Handle prerelease versions
        if lhs.prerelease == nil && rhs.prerelease != nil { return false }
        if lhs.prerelease != nil && rhs.prerelease == nil { return true }
        if let lhsPre = lhs.prerelease, let rhsPre = rhs.prerelease {
            return lhsPre < rhsPre
        }
        
        return false
    }
    
    public var description: String {
        var result = "\(major).\(minor).\(patch)"
        if let prerelease = prerelease {
            result += "-\(prerelease)"
        }
        if let build = build {
            result += "+\(build)"
        }
        return result
    }
}

/// Module configuration
public struct ModuleConfiguration: Codable, Sendable {
    public let name: String
    public let bundleIdentifier: String
    public let platforms: [Platform]
    public let buildFlags: BuildFlags
    public let resources: [ResourceBundle]
    public let testable: Bool
    public let exportedSymbols: [String]
    
    public init(
        name: String,
        bundleIdentifier: String,
        platforms: [Platform] = Platform.all,
        buildFlags: BuildFlags = .init(),
        resources: [ResourceBundle] = [],
        testable: Bool = true,
        exportedSymbols: [String] = []
    ) {
        self.name = name
        self.bundleIdentifier = bundleIdentifier
        self.platforms = platforms
        self.buildFlags = buildFlags
        self.resources = resources
        self.testable = testable
        self.exportedSymbols = exportedSymbols
    }
}

/// Platform specification
public struct Platform: Codable, Hashable, Sendable {
    public let name: String
    public let minimumVersion: String
    
    public init(name: String, minimumVersion: String) {
        self.name = name
        self.minimumVersion = minimumVersion
    }
    
    public static let iOS = Platform(name: "iOS", minimumVersion: "17.0")
    public static let macOS = Platform(name: "macOS", minimumVersion: "14.0")
    public static let watchOS = Platform(name: "watchOS", minimumVersion: "10.0")
    public static let tvOS = Platform(name: "tvOS", minimumVersion: "17.0")
    public static let visionOS = Platform(name: "visionOS", minimumVersion: "1.0")
    
    public static let all = [iOS, macOS, watchOS, tvOS, visionOS]
}

/// Build flags for conditional compilation
public struct BuildFlags: Codable, @unchecked Sendable {
    public var debug: [String: Any]
    public var release: [String: Any]
    public var custom: [String: [String: Any]]
    
    public init(
        debug: [String: Any] = [:],
        release: [String: Any] = [:],
        custom: [String: [String: Any]] = [:]
    ) {
        self.debug = debug
        self.release = release
        self.custom = custom
    }
    
    // Codable implementation for Any types
    enum CodingKeys: String, CodingKey {
        case debug, release, custom
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        let debugData = try container.decode([String: String].self, forKey: .debug)
        self.debug = debugData.mapValues { $0 as Any }
        
        let releaseData = try container.decode([String: String].self, forKey: .release)
        self.release = releaseData.mapValues { $0 as Any }
        
        let customData = try container.decode([String: [String: String]].self, forKey: .custom)
        self.custom = customData.mapValues { dict in
            dict.mapValues { $0 as Any }
        }
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        let debugData = debug.compactMapValues { $0 as? String }
        try container.encode(debugData, forKey: .debug)
        
        let releaseData = release.compactMapValues { $0 as? String }
        try container.encode(releaseData, forKey: .release)
        
        let customData = custom.mapValues { dict in
            dict.compactMapValues { $0 as? String }
        }
        try container.encode(customData, forKey: .custom)
    }
}

/// Resource bundle specification
public struct ResourceBundle: Codable, Sendable {
    public let name: String
    public let path: String
    public let resources: [String]
    
    public init(name: String, path: String, resources: [String]) {
        self.name = name
        self.path = path
        self.resources = resources
    }
}

// MARK: - Module Registry

@MainActor
public final class ModuleRegistry {
    public static let shared = ModuleRegistry()
    
    private var modules: [String: any FeatureModule.Type] = [:]
    private var contracts: [String: any ModuleContract] = [:]
    private var dependencyGraph: DependencyGraph = DependencyGraph()
    
    private init() {}
    
    /// Register a feature module
    public func register<T: FeatureModule>(_ moduleType: T.Type) throws {
        let identifier = moduleType.identifier
        
        // Check for duplicates
        guard modules[identifier] == nil else {
            throw ModuleError.duplicateModule(identifier)
        }
        
        // Validate dependencies
        try validateDependencies(for: moduleType)
        
        modules[identifier] = moduleType
        dependencyGraph.addModule(moduleType)
    }
    
    /// Get a module's contract
    public func contract<T: ModuleContract>(for identifier: String) -> T? {
        return contracts[identifier] as? T
    }
    
    /// Validate module dependencies
    private func validateDependencies<T: FeatureModule>(for moduleType: T.Type) throws {
        for dependency in moduleType.dependencies {
            if !dependency.isOptional {
                guard modules[dependency.identifier] != nil else {
                    throw ModuleError.missingDependency(
                        module: moduleType.identifier,
                        dependency: dependency.identifier
                    )
                }
            }
        }
        
        // Check for circular dependencies
        if dependencyGraph.hasCircularDependency(moduleType) {
            throw ModuleError.circularDependency(moduleType.identifier)
        }
    }
    
    /// Get initialization order based on dependencies
    public func initializationOrder() -> [String] {
        return dependencyGraph.topologicalSort()
    }
}

// MARK: - Dependency Graph

private class DependencyGraph {
    private var adjacencyList: [String: Set<String>] = [:]
    
    func addModule<T: FeatureModule>(_ moduleType: T.Type) {
        let identifier = moduleType.identifier
        if adjacencyList[identifier] == nil {
            adjacencyList[identifier] = []
        }
        
        for dependency in moduleType.dependencies {
            adjacencyList[identifier]?.insert(dependency.identifier)
        }
    }
    
    func hasCircularDependency<T: FeatureModule>(_ moduleType: T.Type) -> Bool {
        let identifier = moduleType.identifier
        var visited = Set<String>()
        var recursionStack = Set<String>()
        
        return hasCycle(identifier, &visited, &recursionStack)
    }
    
    private func hasCycle(
        _ node: String,
        _ visited: inout Set<String>,
        _ recursionStack: inout Set<String>
    ) -> Bool {
        visited.insert(node)
        recursionStack.insert(node)
        
        if let neighbors = adjacencyList[node] {
            for neighbor in neighbors {
                if !visited.contains(neighbor) {
                    if hasCycle(neighbor, &visited, &recursionStack) {
                        return true
                    }
                } else if recursionStack.contains(neighbor) {
                    return true
                }
            }
        }
        
        recursionStack.remove(node)
        return false
    }
    
    func topologicalSort() -> [String] {
        var visited = Set<String>()
        var stack: [String] = []
        
        for node in adjacencyList.keys {
            if !visited.contains(node) {
                topologicalSortUtil(node, &visited, &stack)
            }
        }
        
        return stack.reversed()
    }
    
    private func topologicalSortUtil(
        _ node: String,
        _ visited: inout Set<String>,
        _ stack: inout [String]
    ) {
        visited.insert(node)
        
        if let neighbors = adjacencyList[node] {
            for neighbor in neighbors {
                if !visited.contains(neighbor) {
                    topologicalSortUtil(neighbor, &visited, &stack)
                }
            }
        }
        
        stack.append(node)
    }
}

// MARK: - Module Errors

public enum ModuleError: LocalizedError {
    case duplicateModule(String)
    case missingDependency(module: String, dependency: String)
    case circularDependency(String)
    case incompatibleVersion(module: String, required: String, found: String)
    case contractViolation(from: String, to: String, violation: String)
    
    public var errorDescription: String? {
        switch self {
        case .duplicateModule(let id):
            return "Module '\(id)' is already registered"
        case .missingDependency(let module, let dependency):
            return "Module '\(module)' requires '\(dependency)' which is not found"
        case .circularDependency(let module):
            return "Circular dependency detected involving module '\(module)'"
        case .incompatibleVersion(let module, let required, let found):
            return "Module '\(module)' requires version '\(required)' but found '\(found)'"
        case .contractViolation(let from, let to, let violation):
            return "Module '\(from)' violates contract with '\(to)': \(violation)"
        }
    }
}

// MARK: - Helpers

private extension Collection {
    subscript(safe index: Index) -> Element? {
        return indices.contains(index) ? self[index] : nil
    }
}