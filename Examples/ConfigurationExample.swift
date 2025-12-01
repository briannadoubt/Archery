import SwiftUI
import Archery

// MARK: - Example App Configuration

@Configuration(
    environmentPrefix: "MYAPP",
    validateOnChange: true,
    enableRemoteConfig: true
)
struct AppConfiguration {
    // API Configuration
    @Required
    @Validate(pattern: "^https://.*")
    @Description("API base URL")
    var apiUrl: String = "https://api.example.com"
    
    @DefaultValue("30")
    @Validate(range: "1...300")
    @Description("API request timeout in seconds")
    var apiTimeout: Int = 30
    
    @DefaultValue("10")
    @Validate(range: "1...100")
    @Description("Maximum number of API retries")
    var maxRetries: Int = 10
    
    // Database Configuration
    @Required
    @Description("Database connection string")
    var databaseUrl: String = "sqlite:///app.db"
    
    @DefaultValue("10")
    @Validate(range: "1...100")
    @Description("Database connection pool size")
    var connectionPoolSize: Int = 10
    
    @EnvironmentSpecific
    @Description("Enable SSL for database connections")
    var databaseSSL: Bool = false
    
    // Feature Flags
    @EnvironmentSpecific
    @Description("Enable debug mode")
    var debugMode: Bool = false
    
    @DefaultValue("false")
    @Description("Enable experimental features")
    var experimentalFeatures: Bool = false
    
    // Logging Configuration
    @DefaultValue("info")
    @Validate(values: "trace,debug,info,warning,error,critical")
    @Description("Log level")
    var logLevel: String = "info"
    
    @DefaultValue("100")
    @Validate(range: "1...1000")
    @Description("Maximum log file size in MB")
    var maxLogFileSize: Int = 100
    
    // Security
    @Secret
    @Required
    @Description("JWT signing secret")
    var jwtSecret: String = ""
    
    @Secret
    @Required  
    @Description("API key for external services")
    var apiKey: String = ""
    
    @DefaultValue("3600")
    @Validate(range: "300...86400")
    @Description("Token expiration time in seconds")
    var tokenExpirationTime: Int = 3600
    
    // Cache Configuration
    @DefaultValue("redis://localhost:6379")
    @Description("Redis connection URL")
    var redisUrl: String = "redis://localhost:6379"
    
    @DefaultValue("300")
    @Validate(range: "30...3600")
    @Description("Default cache TTL in seconds")
    var cacheDefaultTTL: Int = 300
    
    // Monitoring
    @DefaultValue("false")
    @EnvironmentSpecific
    @Description("Enable performance monitoring")
    var enableMonitoring: Bool = false
    
    @Description("Monitoring endpoint URL")
    var monitoringUrl: String?
}

// MARK: - Example Usage

struct ConfigurationExampleApp: App {
    @StateObject private var configManager = AppConfiguration.manager
    
    var body: some Scene {
        WindowGroup {
            ConfigurationDemoView()
                .environmentObject(configManager)
                .task {
                    await setupConfiguration()
                }
        }
    }
    
    private func setupConfiguration() async {
        // Setup remote configuration
        if let url = URL(string: "https://config.example.com/app-config") {
            configManager.setupRemoteConfig(
                url: url,
                refreshInterval: 300, // 5 minutes
                headers: ["Authorization": "Bearer \(configManager.current.resolvedApiKey ?? "")"]
            )
        }
        
        // Setup secrets
        await setupSecrets()
    }
    
    private func setupSecrets() async {
        do {
            let secrets = [
                Secret(
                    key: "jwtSecret",
                    value: "super-secret-jwt-key",
                    environment: ConfigurationEnvironment.current,
                    tags: ["auth", "security"]
                ),
                Secret(
                    key: "apiKey", 
                    value: "api-key-12345",
                    environment: ConfigurationEnvironment.current,
                    tags: ["external", "api"]
                )
            ]
            
            try SecretsManager.shared.storeMultiple(secrets)
        } catch {
            print("Failed to store secrets: \(error)")
        }
    }
}

// MARK: - Configuration Demo View

struct ConfigurationDemoView: View {
    @EnvironmentObject var configManager: ConfigurationManager<AppConfiguration>
    @State private var showingOverrides = false
    @State private var overrideKey = ""
    @State private var overrideValue = ""
    @State private var validationResult: ValidationResult?
    
    var body: some View {
        NavigationView {
            List {
                Section("Environment") {
                    HStack {
                        Text("Current Environment")
                        Spacer()
                        Text(ConfigurationEnvironment.current.rawValue)
                            .foregroundColor(.secondary)
                    }
                    
                    HStack {
                        Text("Is Production")
                        Spacer()
                        Text(ConfigurationEnvironment.current.isProduction ? "Yes" : "No")
                            .foregroundColor(.secondary)
                    }
                }
                
                Section("API Configuration") {
                    ConfigRowView(
                        label: "API URL",
                        value: configManager.current.apiUrl
                    )
                    
                    ConfigRowView(
                        label: "Timeout",
                        value: "\(configManager.current.apiTimeout)s"
                    )
                    
                    ConfigRowView(
                        label: "Max Retries", 
                        value: "\(configManager.current.maxRetries)"
                    )
                }
                
                Section("Database") {
                    ConfigRowView(
                        label: "URL",
                        value: configManager.current.databaseUrl,
                        sensitive: true
                    )
                    
                    ConfigRowView(
                        label: "Pool Size",
                        value: "\(configManager.current.connectionPoolSize)"
                    )
                    
                    ConfigRowView(
                        label: "SSL Enabled",
                        value: configManager.current.databaseSSL ? "Yes" : "No"
                    )
                }
                
                Section("Features") {
                    ConfigRowView(
                        label: "Debug Mode",
                        value: configManager.current.debugMode ? "Enabled" : "Disabled"
                    )
                    
                    ConfigRowView(
                        label: "Experimental",
                        value: configManager.current.experimentalFeatures ? "Enabled" : "Disabled"
                    )
                    
                    ConfigRowView(
                        label: "Log Level",
                        value: configManager.current.logLevel
                    )
                }
                
                Section("Secrets") {
                    SecretRowView(secretKey: "jwtSecret", label: "JWT Secret")
                    SecretRowView(secretKey: "apiKey", label: "API Key")
                }
                
                Section("Actions") {
                    Button("Validate Configuration") {
                        validateConfiguration()
                    }
                    
                    Button("Refresh Remote Config") {
                        Task {
                            await configManager.refresh()
                        }
                    }
                    
                    Button("Show Overrides") {
                        showingOverrides = true
                    }
                }
                
                if let result = validationResult {
                    Section("Validation Result") {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Image(systemName: result.isValid ? "checkmark.circle.fill" : "xmark.circle.fill")
                                    .foregroundColor(result.isValid ? .green : .red)
                                Text(result.isValid ? "Valid" : "Invalid")
                                    .font(.headline)
                            }
                            
                            if !result.errors.isEmpty {
                                ForEach(result.errors.indices, id: \.self) { index in
                                    Text("❌ \(result.errors[index].path): \(result.errors[index].message)")
                                        .font(.caption)
                                        .foregroundColor(.red)
                                }
                            }
                            
                            if !result.warnings.isEmpty {
                                ForEach(result.warnings.indices, id: \.self) { index in
                                    Text("⚠️ \(result.warnings[index].path): \(result.warnings[index].message)")
                                        .font(.caption)
                                        .foregroundColor(.orange)
                                }
                            }
                        }
                        .padding()
                    }
                }
            }
            .navigationTitle("Configuration")
            .sheet(isPresented: $showingOverrides) {
                OverridesSheet(configManager: configManager)
            }
        }
    }
    
    private func validateConfiguration() {
        do {
            let validator = ConfigValidator.createDefault()
            validationResult = try validator.validate(configManager.current)
        } catch {
            validationResult = ValidationResult(
                isValid: false,
                errors: [ValidationError(path: "root", message: error.localizedDescription)],
                warnings: []
            )
        }
    }
}

// MARK: - Supporting Views

struct ConfigRowView: View {
    let label: String
    let value: String
    let sensitive: Bool
    
    init(label: String, value: String, sensitive: Bool = false) {
        self.label = label
        self.value = value
        self.sensitive = sensitive
    }
    
    var body: some View {
        HStack {
            Text(label)
            Spacer()
            if sensitive {
                Text("••••••••")
                    .foregroundColor(.secondary)
                    .font(.system(.body, design: .monospaced))
            } else {
                Text(value)
                    .foregroundColor(.secondary)
            }
        }
    }
}

struct SecretRowView: View {
    let secretKey: String
    let label: String
    @State private var isRevealed = false
    @State private var secretValue: String?
    
    var body: some View {
        HStack {
            Text(label)
            Spacer()
            
            if isRevealed, let value = secretValue {
                Text(value)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(.secondary)
            } else {
                Text("••••••••")
                    .foregroundColor(.secondary)
                    .font(.system(.body, design: .monospaced))
            }
            
            Button(isRevealed ? "Hide" : "Show") {
                toggleReveal()
            }
            .font(.caption)
        }
        .onAppear {
            loadSecret()
        }
    }
    
    private func loadSecret() {
        Task { @MainActor in
            do {
                if let secret = try SecretsManager.shared.retrieve(secretKey) {
                    secretValue = secret.value
                }
            } catch {
                secretValue = nil
            }
        }
    }
    
    private func toggleReveal() {
        isRevealed.toggle()
        if !isRevealed {
            // Clear from memory when hiding
            secretValue = nil
            loadSecret()
        }
    }
}

struct OverridesSheet: View {
    let configManager: ConfigurationManager<AppConfiguration>
    @State private var overrideKey = ""
    @State private var overrideValue = ""
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                Text("Configuration Overrides")
                    .font(.title2)
                    .bold()
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("Add Override")
                        .font(.headline)
                    
                    TextField("Configuration Key", text: $overrideKey)
                        .textFieldStyle(.roundedBorder)
                        .placeholder("e.g., apiUrl")
                    
                    TextField("Value", text: $overrideValue)
                        .textFieldStyle(.roundedBorder)
                        .placeholder("e.g., https://staging.example.com")
                    
                    Button("Add Override") {
                        addOverride()
                    }
                    .disabled(overrideKey.isEmpty || overrideValue.isEmpty)
                }
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(10)
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("Available Keys")
                        .font(.headline)
                    
                    let keys = [
                        "apiUrl", "apiTimeout", "maxRetries",
                        "databaseUrl", "connectionPoolSize", "databaseSSL",
                        "debugMode", "experimentalFeatures", "logLevel"
                    ]
                    
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 2), spacing: 8) {
                        ForEach(keys, id: \.self) { key in
                            Button(key) {
                                overrideKey = key
                            }
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.blue.opacity(0.1))
                            .cornerRadius(6)
                        }
                    }
                }
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(10)
                
                Spacer()
            }
            .padding()
            .navigationBarItems(trailing: Button("Done") {
                dismiss()
            })
        }
    }
    
    private func addOverride() {
        // Determine the type and convert value appropriately
        let value: Any
        if overrideValue.lowercased() == "true" {
            value = true
        } else if overrideValue.lowercased() == "false" {
            value = false
        } else if let intValue = Int(overrideValue) {
            value = intValue
        } else if let doubleValue = Double(overrideValue) {
            value = doubleValue
        } else {
            value = overrideValue
        }
        
        configManager.override(overrideKey, value: value)
        
        // Clear fields
        overrideKey = ""
        overrideValue = ""
    }
}

// MARK: - Extensions

extension View {
    func placeholder<Content: View>(
        when shouldShow: Bool,
        alignment: Alignment = .leading,
        @ViewBuilder placeholder: () -> Content
    ) -> some View {
        ZStack(alignment: alignment) {
            placeholder().opacity(shouldShow ? 1 : 0)
            self
        }
    }
    
    func placeholder(
        _ text: String,
        when shouldShow: Bool,
        alignment: Alignment = .leading
    ) -> some View {
        placeholder(when: shouldShow, alignment: alignment) {
            Text(text).foregroundColor(.secondary)
        }
    }
}

extension TextField {
    func placeholder(_ text: String) -> some View {
        self.placeholder(text, when: self.text.wrappedValue.isEmpty)
    }
}

// MARK: - Preview

struct ConfigurationDemoView_Previews: PreviewProvider {
    static var previews: some View {
        ConfigurationDemoView()
            .environmentObject(AppConfiguration.manager)
    }
}