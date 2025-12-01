import Foundation

// MARK: - Build Configuration System

/// Build configuration with compile-time flags and macro controls
public struct BuildConfiguration: Codable {
    public let name: String
    public let flags: BuildConfigurationFlags
    public let macroOutputs: MacroOutputConfiguration
    public let optimizations: OptimizationSettings
    public let budgets: PerformanceBudgets
    
    public init(
        name: String,
        flags: BuildConfigurationFlags = .default,
        macroOutputs: MacroOutputConfiguration = .default,
        optimizations: OptimizationSettings = .default,
        budgets: PerformanceBudgets = .default
    ) {
        self.name = name
        self.flags = flags
        self.macroOutputs = macroOutputs
        self.optimizations = optimizations
        self.budgets = budgets
    }
    
    public static let debug = BuildConfiguration(
        name: "Debug",
        flags: .debug,
        macroOutputs: .all,
        optimizations: .none,
        budgets: .relaxed
    )
    
    public static let release = BuildConfiguration(
        name: "Release",
        flags: .release,
        macroOutputs: .production,
        optimizations: .aggressive,
        budgets: .strict
    )
}

// MARK: - Build Flags

public struct BuildConfigurationFlags: Codable {
    public var swiftFlags: [String]
    public var linkerFlags: [String]
    public var preprocessorMacros: [String: String]
    public var activeCompilationConditions: [String]
    public var customFlags: [String: Any]
    
    public init(
        swiftFlags: [String] = [],
        linkerFlags: [String] = [],
        preprocessorMacros: [String: String] = [:],
        activeCompilationConditions: [String] = [],
        customFlags: [String: Any] = [:]
    ) {
        self.swiftFlags = swiftFlags
        self.linkerFlags = linkerFlags
        self.preprocessorMacros = preprocessorMacros
        self.activeCompilationConditions = activeCompilationConditions
        self.customFlags = customFlags
    }
    
    public static let `default` = BuildConfigurationFlags()
    
    public static let debug = BuildConfigurationFlags(
        swiftFlags: ["-Onone", "-DDEBUG"],
        activeCompilationConditions: ["DEBUG", "TESTING"],
        preprocessorMacros: ["DEBUG": "1"]
    )
    
    public static let release = BuildConfigurationFlags(
        swiftFlags: ["-O", "-whole-module-optimization"],
        activeCompilationConditions: ["RELEASE"],
        preprocessorMacros: ["RELEASE": "1", "NDEBUG": "1"]
    )
    
    // Custom Codable implementation
    enum CodingKeys: String, CodingKey {
        case swiftFlags, linkerFlags, preprocessorMacros, activeCompilationConditions, customFlags
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.swiftFlags = try container.decode([String].self, forKey: .swiftFlags)
        self.linkerFlags = try container.decode([String].self, forKey: .linkerFlags)
        self.preprocessorMacros = try container.decode([String: String].self, forKey: .preprocessorMacros)
        self.activeCompilationConditions = try container.decode([String].self, forKey: .activeCompilationConditions)
        
        let customData = try container.decode([String: String].self, forKey: .customFlags)
        self.customFlags = customData.mapValues { $0 as Any }
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(swiftFlags, forKey: .swiftFlags)
        try container.encode(linkerFlags, forKey: .linkerFlags)
        try container.encode(preprocessorMacros, forKey: .preprocessorMacros)
        try container.encode(activeCompilationConditions, forKey: .activeCompilationConditions)
        
        let customData = customFlags.compactMapValues { $0 as? String }
        try container.encode(customData, forKey: .customFlags)
    }
}

// MARK: - Macro Output Configuration

public struct MacroOutputConfiguration: Codable {
    public var enabledMacros: Set<String>
    public var disabledMacros: Set<String>
    public var macroSettings: [String: MacroSettings]
    
    public init(
        enabledMacros: Set<String> = [],
        disabledMacros: Set<String> = [],
        macroSettings: [String: MacroSettings] = [:]
    ) {
        self.enabledMacros = enabledMacros
        self.disabledMacros = disabledMacros
        self.macroSettings = macroSettings
    }
    
    public static let `default` = MacroOutputConfiguration()
    
    public static let all = MacroOutputConfiguration(
        enabledMacros: Set(MacroType.allCases.map { $0.rawValue })
    )
    
    public static let production = MacroOutputConfiguration(
        enabledMacros: Set(MacroType.production.map { $0.rawValue }),
        disabledMacros: Set(MacroType.debugOnly.map { $0.rawValue })
    )
    
    /// Check if a macro is enabled
    public func isEnabled(_ macro: String) -> Bool {
        if disabledMacros.contains(macro) {
            return false
        }
        return enabledMacros.isEmpty || enabledMacros.contains(macro)
    }
    
    /// Get settings for a specific macro
    public func settings(for macro: String) -> MacroSettings {
        return macroSettings[macro] ?? .default
    }
}

public struct MacroSettings: Codable {
    public var generateMocks: Bool
    public var generatePreviews: Bool
    public var generateTests: Bool
    public var generateDocumentation: Bool
    public var verboseOutput: Bool
    public var customSettings: [String: String]
    
    public init(
        generateMocks: Bool = true,
        generatePreviews: Bool = true,
        generateTests: Bool = true,
        generateDocumentation: Bool = true,
        verboseOutput: Bool = false,
        customSettings: [String: String] = [:]
    ) {
        self.generateMocks = generateMocks
        self.generatePreviews = generatePreviews
        self.generateTests = generateTests
        self.generateDocumentation = generateDocumentation
        self.verboseOutput = verboseOutput
        self.customSettings = customSettings
    }
    
    public static let `default` = MacroSettings()
    
    public static let minimal = MacroSettings(
        generateMocks: false,
        generatePreviews: false,
        generateTests: false,
        generateDocumentation: false
    )
}

public enum MacroType: String, CaseIterable {
    case keyValueStore = "KeyValueStore"
    case repository = "Repository"
    case observableViewModel = "ObservableViewModel"
    case viewModelBound = "ViewModelBound"
    case appShell = "AppShell"
    case apiClient = "APIClient"
    case cache = "Cache"
    case designTokens = "DesignTokens"
    case persistenceGateway = "PersistenceGateway"
    case localizable = "Localizable"
    case sharedModel = "SharedModel"
    case analyticsEvent = "AnalyticsEvent"
    case featureFlag = "FeatureFlag"
    case authenticated = "Authenticated"
    case form = "Form"
    case configuration = "Configuration"
    
    static let production: [MacroType] = allCases.filter { $0 != .analyticsEvent }
    static let debugOnly: [MacroType] = []
}

// MARK: - Optimization Settings

public struct OptimizationSettings: Codable {
    public var level: OptimizationLevel
    public var wholeModuleOptimization: Bool
    public var linkTimeOptimization: Bool
    public var deadCodeStripping: Bool
    public var inlining: InliningStrategy
    
    public init(
        level: OptimizationLevel = .none,
        wholeModuleOptimization: Bool = false,
        linkTimeOptimization: Bool = false,
        deadCodeStripping: Bool = true,
        inlining: InliningStrategy = .automatic
    ) {
        self.level = level
        self.wholeModuleOptimization = wholeModuleOptimization
        self.linkTimeOptimization = linkTimeOptimization
        self.deadCodeStripping = deadCodeStripping
        self.inlining = inlining
    }
    
    public static let `default` = OptimizationSettings()
    
    public static let none = OptimizationSettings(
        level: .none,
        wholeModuleOptimization: false,
        linkTimeOptimization: false
    )
    
    public static let aggressive = OptimizationSettings(
        level: .aggressive,
        wholeModuleOptimization: true,
        linkTimeOptimization: true,
        deadCodeStripping: true,
        inlining: .aggressive
    )
}

public enum OptimizationLevel: String, Codable {
    case none = "-Onone"
    case speed = "-O"
    case size = "-Osize"
    case aggressive = "-Ounchecked"
}

public enum InliningStrategy: String, Codable {
    case never = "never"
    case automatic = "auto"
    case always = "always"
    case aggressive = "aggressive"
}

// MARK: - Performance Budgets

public struct PerformanceBudgets: Codable {
    public var buildTime: TimeInterval
    public var binarySize: Int // bytes
    public var symbolCount: Int
    public var startupTime: TimeInterval
    public var memoryUsage: Int // bytes
    public var frameTime: TimeInterval // Target frame time (e.g., 16.67ms for 60fps)
    
    public init(
        buildTime: TimeInterval = 60,
        binarySize: Int = 50_000_000, // 50 MB
        symbolCount: Int = 100_000,
        startupTime: TimeInterval = 0.3,
        memoryUsage: Int = 150_000_000, // 150 MB
        frameTime: TimeInterval = 0.01667 // 60 fps
    ) {
        self.buildTime = buildTime
        self.binarySize = binarySize
        self.symbolCount = symbolCount
        self.startupTime = startupTime
        self.memoryUsage = memoryUsage
        self.frameTime = frameTime
    }
    
    public static let `default` = PerformanceBudgets()
    
    public static let strict = PerformanceBudgets(
        buildTime: 30,
        binarySize: 30_000_000, // 30 MB
        symbolCount: 50_000,
        startupTime: 0.2,
        memoryUsage: 100_000_000, // 100 MB
        frameTime: 0.01667
    )
    
    public static let relaxed = PerformanceBudgets(
        buildTime: 120,
        binarySize: 100_000_000, // 100 MB
        symbolCount: 200_000,
        startupTime: 0.5,
        memoryUsage: 300_000_000, // 300 MB
        frameTime: 0.03333 // 30 fps
    )
}

// MARK: - Build Configuration Manager

@MainActor
public final class BuildConfigurationManager {
    public static let shared = BuildConfigurationManager()
    
    private var currentConfiguration: BuildConfiguration
    private var configurationOverrides: [String: Any] = [:]
    
    private init() {
        #if DEBUG
        self.currentConfiguration = .debug
        #else
        self.currentConfiguration = .release
        #endif
    }
    
    /// Load configuration from file
    public func loadConfiguration(from url: URL) throws {
        let data = try Data(contentsOf: url)
        currentConfiguration = try JSONDecoder().decode(BuildConfiguration.self, from: data)
    }
    
    /// Save configuration to file
    public func saveConfiguration(to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(currentConfiguration)
        try data.write(to: url)
    }
    
    /// Check if a macro is enabled
    public func isMacroEnabled(_ macro: String) -> Bool {
        return currentConfiguration.macroOutputs.isEnabled(macro)
    }
    
    /// Get macro settings
    public func macroSettings(for macro: String) -> MacroSettings {
        return currentConfiguration.macroOutputs.settings(for: macro)
    }
    
    /// Check if budget is exceeded
    public func checkBudget(_ metric: PerformanceMetric, value: Double) -> BudgetCheckResult {
        let budgets = currentConfiguration.budgets
        
        switch metric {
        case .buildTime:
            return value <= budgets.buildTime ? .passed : .failed(limit: budgets.buildTime, actual: value)
        case .binarySize:
            return value <= Double(budgets.binarySize) ? .passed : .failed(limit: Double(budgets.binarySize), actual: value)
        case .symbolCount:
            return value <= Double(budgets.symbolCount) ? .passed : .failed(limit: Double(budgets.symbolCount), actual: value)
        case .startupTime:
            return value <= budgets.startupTime ? .passed : .failed(limit: budgets.startupTime, actual: value)
        case .memoryUsage:
            return value <= Double(budgets.memoryUsage) ? .passed : .failed(limit: Double(budgets.memoryUsage), actual: value)
        case .frameTime:
            return value <= budgets.frameTime ? .passed : .failed(limit: budgets.frameTime, actual: value)
        }
    }
    
    /// Generate compiler flags
    public func compilerFlags() -> [String] {
        var flags: [String] = []
        
        // Add swift flags
        flags.append(contentsOf: currentConfiguration.flags.swiftFlags)
        
        // Add optimization flags
        flags.append(currentConfiguration.optimizations.level.rawValue)
        
        if currentConfiguration.optimizations.wholeModuleOptimization {
            flags.append("-whole-module-optimization")
        }
        
        // Add conditional compilation flags
        for condition in currentConfiguration.flags.activeCompilationConditions {
            flags.append("-D\(condition)")
        }
        
        return flags
    }
}

public enum PerformanceMetric {
    case buildTime
    case binarySize
    case symbolCount
    case startupTime
    case memoryUsage
    case frameTime
}

public enum BudgetCheckResult {
    case passed
    case failed(limit: Double, actual: Double)
    case skipped(reason: String)
    
    public var isSuccess: Bool {
        switch self {
        case .passed:
            return true
        default:
            return false
        }
    }
    
    public var message: String {
        switch self {
        case .passed:
            return "✅ Budget check passed"
        case .failed(let limit, let actual):
            return "❌ Budget exceeded: limit=\(limit), actual=\(actual)"
        case .skipped(let reason):
            return "⚠️ Budget check skipped: \(reason)"
        }
    }
}