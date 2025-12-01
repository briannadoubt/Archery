import Foundation
import Observation

// MARK: - Configuration Protocol

public protocol Configuration: Codable, Sendable {
    static var defaultValues: Self { get }
    func validate() throws -> Bool
}

// MARK: - Environment

public enum ConfigurationEnvironment: String, Codable, Sendable, CaseIterable {
    case production = "prod"
    case staging = "stage"
    case development = "dev"
    case demo = "demo"
    case test = "test"
    
    public var isProduction: Bool {
        self == .production
    }
    
    public var isDevelopment: Bool {
        self == .development || self == .test
    }
    
    public static var current: ConfigurationEnvironment {
        #if DEBUG
        return .development
        #else
        if let envString = ProcessInfo.processInfo.environment["APP_ENVIRONMENT"],
           let env = ConfigurationEnvironment(rawValue: envString) {
            return env
        }
        return .production
        #endif
    }
}

// MARK: - Configuration Value

public struct ConfigValue<T: Codable & Sendable>: Codable, Sendable {
    public let value: T
    public let source: ConfigSource
    public let timestamp: Date
    
    public init(value: T, source: ConfigSource = .default, timestamp: Date = Date()) {
        self.value = value
        self.source = source
        self.timestamp = timestamp
    }
}

public enum ConfigSource: String, Codable, Sendable {
    case `default`
    case buildTime
    case environment
    case file
    case remote
    case override
}

// MARK: - Configuration Manager

@MainActor
@Observable
public final class ConfigurationManager<T: Configuration> {
    // Configuration layers (in priority order)
    private var overrides: [String: Any] = [:]
    private var remoteConfig: T?
    private var environmentConfig: T?
    private var fileConfig: T?
    private var buildTimeConfig: T
    private var defaultConfig: T
    
    // Current merged configuration
    public private(set) var current: T
    
    // Remote config
    private var remoteConfigURL: URL?
    private var remoteConfigRefreshInterval: TimeInterval = 300 // 5 minutes
    private var remoteConfigTask: Task<Void, Never>?
    
    // Observers
    private var configChangeHandlers: [(T) -> Void] = []
    
    public init(
        buildTimeConfig: T? = nil,
        environmentPrefix: String = "APP"
    ) {
        self.defaultConfig = T.defaultValues
        self.buildTimeConfig = buildTimeConfig ?? T.defaultValues
        self.current = self.buildTimeConfig
        
        // Load configurations in order
        loadFileConfig()
        loadEnvironmentConfig(prefix: environmentPrefix)
        mergeConfigurations()
    }
    
    deinit {
        remoteConfigTask?.cancel()
    }
    
    // MARK: - Configuration Loading
    
    private func loadFileConfig() {
        let configName = "config.\(ConfigurationEnvironment.current.rawValue)"
        
        // Try multiple locations
        let searchPaths = [
            Bundle.main.bundleURL,
            Bundle.main.bundleURL.appendingPathComponent("Resources"),
            FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first,
            FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        ].compactMap { $0 }
        
        for basePath in searchPaths {
            let jsonPath = basePath.appendingPathComponent("\(configName).json")
            let plistPath = basePath.appendingPathComponent("\(configName).plist")
            
            if let config = loadConfigFromFile(jsonPath) {
                fileConfig = config
                return
            }
            
            if let config = loadConfigFromFile(plistPath) {
                fileConfig = config
                return
            }
        }
    }
    
    private func loadConfigFromFile(_ url: URL) -> T? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        
        do {
            let data = try Data(contentsOf: url)
            
            if url.pathExtension == "plist" {
                let decoder = PropertyListDecoder()
                return try decoder.decode(T.self, from: data)
            } else {
                let decoder = JSONDecoder()
                return try decoder.decode(T.self, from: data)
            }
        } catch {
            print("[Config] Failed to load config from \(url): \(error)")
            return nil
        }
    }
    
    private func loadEnvironmentConfig(prefix: String) {
        let env = ProcessInfo.processInfo.environment
        let prefixWithDot = "\(prefix)_"
        
        // Collect all environment variables with the prefix
        var envDict: [String: String] = [:]
        for (key, value) in env where key.hasPrefix(prefixWithDot) {
            let configKey = String(key.dropFirst(prefixWithDot.count))
                .replacingOccurrences(of: "_", with: ".")
                .lowercased()
            envDict[configKey] = value
        }
        
        guard !envDict.isEmpty else { return }
        
        // Try to construct config from environment variables
        if let jsonData = try? JSONSerialization.data(withJSONObject: envDict),
           let config = try? JSONDecoder().decode(T.self, from: jsonData) {
            environmentConfig = config
        }
    }
    
    // MARK: - Remote Configuration
    
    public func setupRemoteConfig(
        url: URL,
        refreshInterval: TimeInterval = 300,
        headers: [String: String] = [:]
    ) {
        remoteConfigURL = url
        remoteConfigRefreshInterval = refreshInterval
        
        // Cancel existing task
        remoteConfigTask?.cancel()
        
        // Start refresh task
        remoteConfigTask = Task {
            await startRemoteConfigRefresh(headers: headers)
        }
    }
    
    private func startRemoteConfigRefresh(headers: [String: String]) async {
        while !Task.isCancelled {
            await fetchRemoteConfig(headers: headers)
            try? await Task.sleep(nanoseconds: UInt64(remoteConfigRefreshInterval * 1_000_000_000))
        }
    }
    
    private func fetchRemoteConfig(headers: [String: String]) async {
        guard let url = remoteConfigURL else { return }
        
        do {
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.allHTTPHeaderFields = headers
            request.addValue("application/json", forHTTPHeaderField: "Accept")
            
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                return
            }
            
            let decoder = JSONDecoder()
            let newConfig = try decoder.decode(T.self, from: data)
            
            // Validate before applying
            if try newConfig.validate() {
                remoteConfig = newConfig
                mergeConfigurations()
                notifyConfigChange()
            }
        } catch {
            print("[Config] Failed to fetch remote config: \(error)")
        }
    }
    
    // MARK: - Configuration Merging
    
    private func mergeConfigurations() {
        // Start with defaults
        var merged = defaultConfig
        
        // Apply layers in order (lowest to highest priority)
        let layers: [(T?, ConfigSource)] = [
            (buildTimeConfig, .buildTime),
            (fileConfig, .file),
            (environmentConfig, .environment),
            (remoteConfig, .remote)
        ]
        
        for (config, _) in layers {
            if let config = config {
                merged = merge(base: merged, overlay: config)
            }
        }
        
        // Apply overrides last
        if !overrides.isEmpty {
            merged = applyOverrides(to: merged)
        }
        
        // Validate final configuration
        do {
            if try merged.validate() {
                current = merged
            }
        } catch {
            print("[Config] Validation failed, keeping previous configuration: \(error)")
        }
    }
    
    private func merge(base: T, overlay: T) -> T {
        guard let baseData = try? JSONEncoder().encode(base),
              let overlayData = try? JSONEncoder().encode(overlay),
              var baseDict = try? JSONSerialization.jsonObject(with: baseData) as? [String: Any],
              let overlayDict = try? JSONSerialization.jsonObject(with: overlayData) as? [String: Any] else {
            return overlay
        }
        
        mergeDict(&baseDict, with: overlayDict)
        
        guard let mergedData = try? JSONSerialization.data(withJSONObject: baseDict),
              let merged = try? JSONDecoder().decode(T.self, from: mergedData) else {
            return overlay
        }
        
        return merged
    }
    
    private func mergeDict(_ base: inout [String: Any], with overlay: [String: Any]) {
        for (key, overlayValue) in overlay {
            if let overlayDict = overlayValue as? [String: Any],
               var baseDict = base[key] as? [String: Any] {
                mergeDict(&baseDict, with: overlayDict)
                base[key] = baseDict
            } else {
                base[key] = overlayValue
            }
        }
    }
    
    private func applyOverrides(to config: T) -> T {
        guard let data = try? JSONEncoder().encode(config),
              var dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return config
        }
        
        // Apply overrides
        for (key, value) in overrides {
            setNestedValue(&dict, key: key, value: value)
        }
        
        guard let mergedData = try? JSONSerialization.data(withJSONObject: dict),
              let merged = try? JSONDecoder().decode(T.self, from: mergedData) else {
            return config
        }
        
        return merged
    }
    
    private func setNestedValue(_ dict: inout [String: Any], key: String, value: Any) {
        let components = key.split(separator: ".").map(String.init)
        
        guard !components.isEmpty else { return }
        
        if components.count == 1 {
            dict[components[0]] = value
        } else {
            var current = dict[components[0]] as? [String: Any] ?? [:]
            let remainingKey = components.dropFirst().joined(separator: ".")
            setNestedValue(&current, key: remainingKey, value: value)
            dict[components[0]] = current
        }
    }
    
    // MARK: - Public API
    
    public func override(_ key: String, value: Any) {
        overrides[key] = value
        mergeConfigurations()
        notifyConfigChange()
    }
    
    public func removeOverride(_ key: String) {
        overrides.removeValue(forKey: key)
        mergeConfigurations()
        notifyConfigChange()
    }
    
    public func clearOverrides() {
        overrides.removeAll()
        mergeConfigurations()
        notifyConfigChange()
    }
    
    public func refresh() async {
        if remoteConfigURL != nil {
            await fetchRemoteConfig(headers: [:])
        }
        mergeConfigurations()
        notifyConfigChange()
    }
    
    public func onChange(_ handler: @escaping (T) -> Void) {
        configChangeHandlers.append(handler)
    }
    
    private func notifyConfigChange() {
        for handler in configChangeHandlers {
            handler(current)
        }
    }
    
    // MARK: - Diff Detection
    
    public func diff(from old: T, to new: T) -> [ConfigDiff] {
        var diffs: [ConfigDiff] = []
        
        guard let oldData = try? JSONEncoder().encode(old),
              let newData = try? JSONEncoder().encode(new),
              let oldDict = try? JSONSerialization.jsonObject(with: oldData) as? [String: Any],
              let newDict = try? JSONSerialization.jsonObject(with: newData) as? [String: Any] else {
            return diffs
        }
        
        findDifferences(oldDict, newDict, path: "", diffs: &diffs)
        
        return diffs
    }
    
    private func findDifferences(
        _ old: [String: Any],
        _ new: [String: Any],
        path: String,
        diffs: inout [ConfigDiff]
    ) {
        let allKeys = Set(old.keys).union(Set(new.keys))
        
        for key in allKeys {
            let currentPath = path.isEmpty ? key : "\(path).\(key)"
            
            if let oldValue = old[key], let newValue = new[key] {
                if let oldDict = oldValue as? [String: Any],
                   let newDict = newValue as? [String: Any] {
                    findDifferences(oldDict, newDict, path: currentPath, diffs: &diffs)
                } else if !isEqual(oldValue, newValue) {
                    diffs.append(ConfigDiff(
                        path: currentPath,
                        oldValue: String(describing: oldValue),
                        newValue: String(describing: newValue),
                        type: .changed
                    ))
                }
            } else if old[key] != nil {
                diffs.append(ConfigDiff(
                    path: currentPath,
                    oldValue: String(describing: old[key]!),
                    newValue: nil,
                    type: .removed
                ))
            } else if new[key] != nil {
                diffs.append(ConfigDiff(
                    path: currentPath,
                    oldValue: nil,
                    newValue: String(describing: new[key]!),
                    type: .added
                ))
            }
        }
    }
    
    private func isEqual(_ lhs: Any, _ rhs: Any) -> Bool {
        if let lhsString = lhs as? String, let rhsString = rhs as? String {
            return lhsString == rhsString
        } else if let lhsInt = lhs as? Int, let rhsInt = rhs as? Int {
            return lhsInt == rhsInt
        } else if let lhsBool = lhs as? Bool, let rhsBool = rhs as? Bool {
            return lhsBool == rhsBool
        } else if let lhsDouble = lhs as? Double, let rhsDouble = rhs as? Double {
            return lhsDouble == rhsDouble
        }
        return false
    }
}

// MARK: - Config Diff

public struct ConfigDiff: Equatable {
    public let path: String
    public let oldValue: String?
    public let newValue: String?
    public let type: DiffType
    
    public enum DiffType {
        case added
        case removed
        case changed
    }
}

// MARK: - Configuration Errors

public enum ConfigurationError: LocalizedError {
    case validationFailed(String)
    case missingRequired(String)
    case invalidValue(key: String, value: Any)
    case invalidEnvironment
    case secretsNotConfigured
    
    public var errorDescription: String? {
        switch self {
        case .validationFailed(let message):
            return "Configuration validation failed: \(message)"
        case .missingRequired(let key):
            return "Missing required configuration: \(key)"
        case .invalidValue(let key, let value):
            return "Invalid value for \(key): \(value)"
        case .invalidEnvironment:
            return "Invalid environment configuration"
        case .secretsNotConfigured:
            return "Secrets manager not configured"
        }
    }
}