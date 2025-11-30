import Foundation
import SwiftUI

// MARK: - Feature Flag Protocol

public protocol FeatureFlag {
    associatedtype Value
    
    static var key: String { get }
    static var defaultValue: Value { get }
    static var description: String { get }
}

// MARK: - Feature Flag Manager

@MainActor
public final class FeatureFlagManager: ObservableObject {
    public static let shared = FeatureFlagManager()
    
    @Published public private(set) var flags: [String: Any] = [:]
    @Published public private(set) var overrides: [String: Any] = [:]
    
    private var providers: [FeatureFlagProvider] = []
    private let storage = UserDefaults.standard
    private let overrideKey = "com.archery.featureflags.overrides"
    
    private init() {
        loadOverrides()
    }
    
    public func configure(providers: [FeatureFlagProvider]) {
        self.providers = providers
        Task {
            await refresh()
        }
    }
    
    public func value<Flag: FeatureFlag>(for flag: Flag.Type) -> Flag.Value {
        let key = Flag.key
        
        // Check for local override first
        if let override = overrides[key] as? Flag.Value {
            return override
        }
        
        // Check remote value
        if let value = flags[key] as? Flag.Value {
            return value
        }
        
        // Fall back to default
        return Flag.defaultValue
    }
    
    public func isEnabled<Flag: FeatureFlag>(for flag: Flag.Type) -> Bool where Flag.Value == Bool {
        value(for: flag)
    }
    
    public func override<Flag: FeatureFlag>(_ flag: Flag.Type, with value: Flag.Value?) {
        let key = Flag.key
        
        if let value = value {
            overrides[key] = value
        } else {
            overrides.removeValue(forKey: key)
        }
        
        saveOverrides()
        objectWillChange.send()
    }
    
    public func clearOverrides() {
        overrides.removeAll()
        saveOverrides()
        objectWillChange.send()
    }
    
    public func refresh() async {
        var combinedFlags: [String: Any] = [:]
        
        // Create a copy of providers to avoid actor isolation issues
        let providersCopy = providers
        
        for provider in providersCopy {
            if let flags = try? await provider.fetchFlags() {
                combinedFlags.merge(flags) { $1 }
            }
        }
        
        self.flags = combinedFlags
    }
    
    private func loadOverrides() {
        if let data = storage.data(forKey: overrideKey),
           let overrides = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            self.overrides = overrides
        }
    }
    
    private func saveOverrides() {
        if let data = try? JSONSerialization.data(withJSONObject: overrides) {
            storage.set(data, forKey: overrideKey)
        }
    }
}

// MARK: - Feature Flag Provider Protocol

public protocol FeatureFlagProvider: Sendable {
    func fetchFlags() async throws -> [String: Any]
}

// MARK: - Provider Implementations

public final class RemoteConfigProvider: FeatureFlagProvider, @unchecked Sendable {
    private let endpoint: URL
    private let apiKey: String
    private let cacheDuration: TimeInterval
    private var cachedFlags: [String: Any]?
    private var cacheTimestamp: Date?
    
    public init(endpoint: URL, apiKey: String, cacheDuration: TimeInterval = 300) {
        self.endpoint = endpoint
        self.apiKey = apiKey
        self.cacheDuration = cacheDuration
    }
    
    public func fetchFlags() async throws -> [String: Any] {
        // Check cache
        if let cached = cachedFlags,
           let timestamp = cacheTimestamp,
           Date().timeIntervalSince(timestamp) < cacheDuration {
            return cached
        }
        
        var request = URLRequest(url: endpoint)
        request.setValue(apiKey, forHTTPHeaderField: "X-API-Key")
        
        let (data, _) = try await URLSession.shared.data(for: request)
        let flags = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        
        cachedFlags = flags
        cacheTimestamp = Date()
        
        return flags
    }
}

public final class LocalConfigProvider: FeatureFlagProvider, @unchecked Sendable {
    private let flags: [String: Any]
    
    public init(flags: [String: Any]) {
        self.flags = flags
    }
    
    public func fetchFlags() async throws -> [String: Any] {
        flags
    }
}

public final class PlistProvider: FeatureFlagProvider, @unchecked Sendable {
    private let plistName: String
    private let bundle: Bundle
    
    public init(plistName: String, bundle: Bundle = .main) {
        self.plistName = plistName
        self.bundle = bundle
    }
    
    public func fetchFlags() async throws -> [String: Any] {
        guard let url = bundle.url(forResource: plistName, withExtension: "plist"),
              let data = try? Data(contentsOf: url),
              let flags = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
            return [:]
        }
        
        return flags
    }
}

// MARK: - SwiftUI Integration

public struct FeatureFlagModifier<Flag: FeatureFlag>: ViewModifier where Flag.Value == Bool {
    let flag: Flag.Type
    @ObservedObject private var manager = FeatureFlagManager.shared
    
    public func body(content: Content) -> some View {
        if manager.isEnabled(for: flag) {
            content
        }
    }
}

public extension View {
    func featureFlag<Flag: FeatureFlag>(_ flag: Flag.Type) -> some View where Flag.Value == Bool {
        modifier(FeatureFlagModifier(flag: flag))
    }
    
    @ViewBuilder
    func featureFlag<Flag: FeatureFlag, TrueContent: View, FalseContent: View>(
        _ flag: Flag.Type,
        @ViewBuilder whenEnabled: () -> TrueContent,
        @ViewBuilder whenDisabled: () -> FalseContent
    ) -> some View where Flag.Value == Bool {
        if FeatureFlagManager.shared.isEnabled(for: flag) {
            whenEnabled()
        } else {
            whenDisabled()
        }
    }
}

// MARK: - Property Wrapper

@propertyWrapper
@MainActor
public struct FlagValue<Flag: FeatureFlag> {
    private let flag: Flag.Type
    
    public init(_ flag: Flag.Type) {
        self.flag = flag
    }
    
    public var wrappedValue: Flag.Value {
        FeatureFlagManager.shared.value(for: flag)
    }
}

// MARK: - Testing Support

public final class TestFeatureFlagProvider: FeatureFlagProvider, @unchecked Sendable {
    public var flags: [String: Any]
    
    public init(flags: [String: Any] = [:]) {
        self.flags = flags
    }
    
    public func fetchFlags() async throws -> [String: Any] {
        flags
    }
    
    public func set<Flag: FeatureFlag>(_ flag: Flag.Type, to value: Flag.Value) {
        flags[Flag.key] = value
    }
    
    public func reset() {
        flags.removeAll()
    }
}

// MARK: - Debug UI

#if DEBUG
public struct FeatureFlagDebugView: View {
    @ObservedObject private var manager = FeatureFlagManager.shared
    @State private var showingOverrides = false
    
    public init() {}
    
    public var body: some View {
        NavigationView {
            List {
                Section("Active Flags") {
                    ForEach(Array(manager.flags.keys.sorted()), id: \.self) { key in
                        HStack {
                            Text(key)
                                .font(.system(.body, design: .monospaced))
                            Spacer()
                            Text(String(describing: manager.flags[key] ?? "nil"))
                                .foregroundColor(.secondary)
                        }
                    }
                }
                
                if !manager.overrides.isEmpty {
                    Section("Overrides") {
                        ForEach(Array(manager.overrides.keys.sorted()), id: \.self) { key in
                            HStack {
                                Text(key)
                                    .font(.system(.body, design: .monospaced))
                                Spacer()
                                Text(String(describing: manager.overrides[key] ?? "nil"))
                                    .foregroundColor(.blue)
                            }
                        }
                    }
                }
                
                Section {
                    Button("Refresh Flags") {
                        Task {
                            await manager.refresh()
                        }
                    }
                    
                    Button("Clear Overrides") {
                        manager.clearOverrides()
                    }
                    .foregroundColor(.red)
                }
            }
            .navigationTitle("Feature Flags")
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    Button("Add Override") {
                        showingOverrides = true
                    }
                }
            }
        }
    }
}
#endif