import SwiftUI
import Archery

// MARK: - Example Modular Application

/// Example showing how to structure a modular SwiftUI application using Archery's modularity system
struct ModularityExampleApp: App {
    @StateObject private var moduleCoordinator = ModuleCoordinator()
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(moduleCoordinator)
                .task {
                    await moduleCoordinator.initialize()
                }
        }
    }
}

// MARK: - Module Coordinator

@MainActor
class ModuleCoordinator: ObservableObject {
    @Published var isInitialized = false
    @Published var loadedModules: [String] = []
    @Published var initializationErrors: [String] = []
    
    func initialize() async {
        do {
            // Register core modules first
            try await CoreModule.initialize()
            loadedModules.append("Core")
            
            // Register shared modules
            try await SharedModule.initialize()
            loadedModules.append("Shared")
            
            // Register feature modules in dependency order
            let featureModules = [
                AuthModule.self,
                UserProfileModule.self,
                FeedModule.self,
                SettingsModule.self
            ]
            
            for moduleType in featureModules {
                try await moduleType.initialize()
                loadedModules.append(moduleType.identifier)
            }
            
            isInitialized = true
            
        } catch {
            initializationErrors.append(error.localizedDescription)
        }
    }
}

// MARK: - Core Module

struct CoreModule: FeatureModule {
    static let identifier = "Core"
    static let version = ModuleVersion(major: 1, minor: 0)
    static let dependencies: [ModuleDependency] = []
    
    typealias Contract = CoreContract
    
    static let configuration = ModuleConfiguration(
        name: "Core",
        bundleIdentifier: "com.archery.example.core",
        platforms: Platform.all
    )
    
    static func initialize() async throws {
        try await ModuleRegistry.shared.register(self)
        
        // Initialize core services
        await NetworkManager.shared.configure()
        await CacheManager.shared.configure()
    }
}

struct CoreContract: ModuleContract {
    let version = "1.0.0"
    
    // Expose core services
    struct Services {
        static let networkManager = NetworkManager.shared
        static let cacheManager = CacheManager.shared
        static let logger = Logger.shared
    }
}

// MARK: - Shared Module

struct SharedModule: FeatureModule {
    static let identifier = "Shared"
    static let version = ModuleVersion(major: 1, minor: 0)
    static let dependencies = [
        ModuleDependency(identifier: "Core")
    ]
    
    typealias Contract = SharedContract
    
    static let configuration = ModuleConfiguration(
        name: "Shared",
        bundleIdentifier: "com.archery.example.shared"
    )
}

struct SharedContract: ModuleContract {
    let version = "1.0.0"
    
    // Expose shared UI components
    struct Components {
        // Shared UI components would go here
    }
    
    // Expose shared utilities
    struct Utilities {
        // Shared utilities would go here
    }
}

// MARK: - Auth Module

struct AuthModule: FeatureModule {
    static let identifier = "Auth"
    static let version = ModuleVersion(major: 1, minor: 0)
    static let dependencies = [
        ModuleDependency(identifier: "Core"),
        ModuleDependency(identifier: "Shared")
    ]
    
    typealias Contract = AuthContract
    
    static let configuration = ModuleConfiguration(
        name: "Auth",
        bundleIdentifier: "com.archery.example.auth",
        buildFlags: BuildFlags(
            debug: ["ENABLE_AUTH_LOGGING": "1"],
            release: ["ENABLE_AUTH_LOGGING": "0"]
        )
    )
}

struct AuthContract: ModuleContract {
    let version = "1.0.0"
    
    struct API {
        static func login(username: String, password: String) async throws -> AuthToken {
            // Implementation
            return AuthToken(value: "mock-token")
        }
        
        static func logout() async {
            // Implementation
        }
        
        static var isAuthenticated: Bool {
            // Implementation
            return false
        }
    }
}

struct AuthToken {
    let value: String
}

// MARK: - User Profile Module

struct UserProfileModule: FeatureModule {
    static let identifier = "UserProfile"
    static let version = ModuleVersion(major: 1, minor: 0)
    static let dependencies = [
        ModuleDependency(identifier: "Core"),
        ModuleDependency(identifier: "Shared"),
        ModuleDependency(identifier: "Auth")
    ]
    
    typealias Contract = UserProfileContract
    
    static let configuration = ModuleConfiguration(
        name: "UserProfile",
        bundleIdentifier: "com.archery.example.userprofile"
    )
}

struct UserProfileContract: ModuleContract {
    let version = "1.0.0"
    
    struct Views {
        static func profileView(userId: String) -> some View {
            UserProfileView(userId: userId)
        }
    }
}

// MARK: - Feed Module

struct FeedModule: FeatureModule {
    static let identifier = "Feed"
    static let version = ModuleVersion(major: 1, minor: 0)
    static let dependencies = [
        ModuleDependency(identifier: "Core"),
        ModuleDependency(identifier: "Shared"),
        ModuleDependency(identifier: "Auth"),
        ModuleDependency(identifier: "UserProfile", isOptional: true)
    ]
    
    typealias Contract = FeedContract
    
    static let configuration = ModuleConfiguration(
        name: "Feed",
        bundleIdentifier: "com.archery.example.feed",
        testable: true,
        exportedSymbols: ["FeedView", "FeedViewModel"]
    )
}

struct FeedContract: ModuleContract {
    let version = "1.0.0"
    
    struct Views {
        static var feedView: some View {
            FeedView()
        }
    }
}

// MARK: - Settings Module

struct SettingsModule: FeatureModule {
    static let identifier = "Settings"
    static let version = ModuleVersion(major: 1, minor: 0)
    static let dependencies = [
        ModuleDependency(identifier: "Core"),
        ModuleDependency(identifier: "Shared"),
        ModuleDependency(identifier: "Auth")
    ]
    
    typealias Contract = SettingsContract
    
    static let configuration = ModuleConfiguration(
        name: "Settings",
        bundleIdentifier: "com.archery.example.settings",
        resources: [
            ResourceBundle(
                name: "SettingsAssets",
                path: "Resources/Assets",
                resources: ["settings.json", "preferences.plist"]
            )
        ]
    )
}

struct SettingsContract: ModuleContract {
    let version = "1.0.0"
    
    struct Views {
        static var settingsView: some View {
            SettingsView()
        }
    }
}

// MARK: - Main Content View

struct ContentView: View {
    @EnvironmentObject var coordinator: ModuleCoordinator
    @State private var selectedTab = 0
    
    var body: some View {
        if coordinator.isInitialized {
            TabView(selection: $selectedTab) {
                FeedContract.Views.feedView
                    .tabItem {
                        Label("Feed", systemImage: "house")
                    }
                    .tag(0)
                
                UserProfileContract.Views.profileView(userId: "current")
                    .tabItem {
                        Label("Profile", systemImage: "person")
                    }
                    .tag(1)
                
                SettingsContract.Views.settingsView
                    .tabItem {
                        Label("Settings", systemImage: "gear")
                    }
                    .tag(2)
            }
        } else {
            LoadingView(
                loadedModules: coordinator.loadedModules,
                errors: coordinator.initializationErrors
            )
        }
    }
}

// MARK: - Loading View

struct LoadingView: View {
    let loadedModules: [String]
    let errors: [String]
    
    var body: some View {
        VStack(spacing: 20) {
            ProgressView()
                .scaleEffect(1.5)
            
            Text("Initializing Modules")
                .font(.title2)
                .bold()
            
            if !loadedModules.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(loadedModules, id: \.self) { module in
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                            Text(module)
                                .font(.caption)
                        }
                    }
                }
                .padding()
                .background(Color.gray.opacity(0.1))
                .cornerRadius(8)
            }
            
            if !errors.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(errors, id: \.self) { error in
                        HStack {
                            Image(systemName: "exclamationmark.triangle")
                                .foregroundColor(.red)
                            Text(error)
                                .font(.caption)
                        }
                    }
                }
                .padding()
                .background(Color.red.opacity(0.1))
                .cornerRadius(8)
            }
        }
        .padding()
    }
}

// MARK: - Feature Views

struct FeedView: View {
    var body: some View {
        NavigationView {
            List {
                ForEach(0..<20) { index in
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Post \(index + 1)")
                            .font(.headline)
                        Text("This is a sample post in the feed module")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 8)
                }
            }
            .navigationTitle("Feed")
        }
    }
}

struct UserProfileView: View {
    let userId: String
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                Image(systemName: "person.circle.fill")
                    .font(.system(size: 100))
                    .foregroundColor(.blue)
                
                Text("User Profile")
                    .font(.title)
                    .bold()
                
                Text("ID: \(userId)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Spacer()
            }
            .padding()
            .navigationTitle("Profile")
        }
    }
}

struct SettingsView: View {
    @AppStorage("debugMode") private var debugMode = false
    @AppStorage("enableNotifications") private var enableNotifications = true
    
    var body: some View {
        NavigationView {
            Form {
                Section("General") {
                    Toggle("Debug Mode", isOn: $debugMode)
                    Toggle("Enable Notifications", isOn: $enableNotifications)
                }
                
                Section("Build Information") {
                    HStack {
                        Text("Configuration")
                        Spacer()
                        #if DEBUG
                        Text("Debug")
                        #else
                        Text("Release")
                        #endif
                    }
                    
                    HStack {
                        Text("Modules")
                        Spacer()
                        Text("5 loaded")
                    }
                }
                
                Section("About") {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text("1.0.0")
                    }
                }
            }
            .navigationTitle("Settings")
        }
    }
}

// MARK: - Mock Services

@MainActor
class NetworkManager {
    static let shared = NetworkManager()
    
    func configure() async {
        // Mock configuration
    }
}

@MainActor
class CacheManager {
    static let shared = CacheManager()
    
    func configure() async {
        // Mock configuration
    }
}

@MainActor
class Logger {
    static let shared = Logger()
    
    func log(_ message: String) {
        print("[LOG] \(message)")
    }
}

// MARK: - Build Configuration Demo

struct BuildConfigurationDemo: View {
    @State private var currentConfig = BuildConfiguration.debug
    @State private var budgetResults: [BudgetCheckResult] = []
    
    var body: some View {
        NavigationView {
            Form {
                Section("Active Configuration") {
                    Text(currentConfig.name)
                        .font(.headline)
                }
                
                Section("Macro Outputs") {
                    ForEach(MacroType.allCases, id: \.rawValue) { macro in
                        HStack {
                            Text(macro.rawValue)
                            Spacer()
                            if currentConfig.macroOutputs.isEnabled(macro.rawValue) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                            } else {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.red)
                            }
                        }
                    }
                }
                
                Section("Performance Budgets") {
                    BudgetRow(metric: "Build Time", limit: currentConfig.budgets.buildTime, unit: "s")
                    BudgetRow(metric: "Binary Size", limit: Double(currentConfig.budgets.binarySize) / 1_000_000, unit: "MB")
                    BudgetRow(metric: "Symbol Count", limit: Double(currentConfig.budgets.symbolCount), unit: "")
                    BudgetRow(metric: "Startup Time", limit: currentConfig.budgets.startupTime, unit: "s")
                    BudgetRow(metric: "Memory Usage", limit: Double(currentConfig.budgets.memoryUsage) / 1_000_000, unit: "MB")
                }
                
                Section("Actions") {
                    Button("Switch to Debug") {
                        currentConfig = .debug
                    }
                    
                    Button("Switch to Release") {
                        currentConfig = .release
                    }
                }
            }
            .navigationTitle("Build Configuration")
        }
    }
}

struct BudgetRow: View {
    let metric: String
    let limit: Double
    let unit: String
    
    var body: some View {
        HStack {
            Text(metric)
            Spacer()
            Text(String(format: "%.1f%@", limit, unit))
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - Previews

struct ModularityExample_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            ContentView()
                .environmentObject(ModuleCoordinator())
                .previewDisplayName("Main App")
            
            BuildConfigurationDemo()
                .previewDisplayName("Build Config")
            
            LoadingView(
                loadedModules: ["Core", "Shared", "Auth"],
                errors: []
            )
            .previewDisplayName("Loading State")
        }
    }
}