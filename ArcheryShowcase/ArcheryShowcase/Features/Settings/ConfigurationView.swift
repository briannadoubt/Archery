import SwiftUI
import Archery

// MARK: - Configuration View
//
// Demonstrates the @Configuration macro capabilities:
// - Viewing current configuration values
// - Environment detection (dev/staging/prod)
// - Secret management with Keychain storage
// - Runtime overrides
// - Validation status
// - Remote config refresh

struct ConfigurationView: View {
    @State private var validationResult: ValidationResult?
    @State private var showingOverrides = false
    @State private var showingSecrets = false
    @State private var isRefreshing = false

    var body: some View {
        List {
            introSection
            environmentSection
            apiConfigSection
            featureTogglesSection
            cacheSection
            analyticsSection
            secretsSection
            validationSection
            actionsSection
            usageSection
        }
        .navigationTitle("Configuration")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.large)
        #endif
        .sheet(isPresented: $showingOverrides) {
            ConfigurationOverridesSheet()
        }
        .sheet(isPresented: $showingSecrets) {
            SecretsManagementSheet()
        }
    }

    // MARK: - Intro Section

    @ViewBuilder
    private var introSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                Text("The @Configuration macro generates a type-safe configuration system with layered config sources, validation, secrets, and environment-specific values.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack(spacing: 12) {
                    MacroBadge(icon: "checkmark.shield", label: "Validated")
                    MacroBadge(icon: "lock.shield", label: "Encrypted Secrets")
                    MacroBadge(icon: "globe", label: "Env-Aware")
                }
            }
        }
    }

    // MARK: - Environment Section

    @ViewBuilder
    private var environmentSection: some View {
        Section {
            ConfigRow(
                label: "Current Environment",
                value: ConfigurationEnvironment.current.rawValue,
                icon: "globe"
            )
            ConfigRow(
                label: "Is Production",
                value: ConfigurationEnvironment.current.isProduction ? "Yes" : "No",
                icon: "shield.checkered"
            )
            ConfigRow(
                label: "Is Development",
                value: ConfigurationEnvironment.current.isDevelopment ? "Yes" : "No",
                icon: "hammer"
            )
        } header: {
            Label("Environment", systemImage: "globe.americas")
        } footer: {
            Text("Environment is determined by ARCHERY_ENVIRONMENT variable or DEBUG build flag.")
        }
    }

    // MARK: - API Config Section

    @ViewBuilder
    private var apiConfigSection: some View {
        Section {
            ConfigRow(
                label: "Base URL",
                value: AppConfiguration.apiBaseURL,
                icon: "link"
            )
            ConfigRow(
                label: "Timeout",
                value: "\(AppConfiguration.requestTimeout)s",
                icon: "clock"
            )
            ConfigRow(
                label: "Max Retries",
                value: "\(AppConfiguration.maxRetries)",
                icon: "arrow.clockwise"
            )
        } header: {
            Label("API Configuration", systemImage: "network")
        } footer: {
            Text("@Required and @Validate macros enforce URL pattern and numeric ranges.")
        }
    }

    // MARK: - Feature Toggles Section

    @ViewBuilder
    private var featureTogglesSection: some View {
        Section {
            ConfigToggleRow(
                label: "Debug Logging",
                isOn: AppConfiguration.debugLogging,
                isEnvironmentSpecific: true
            )
            ConfigToggleRow(
                label: "Performance Tracing",
                isOn: AppConfiguration.performanceTracing,
                isEnvironmentSpecific: true
            )
            ConfigToggleRow(
                label: "Experimental Features",
                isOn: AppConfiguration.experimentalFeatures
            )
        } header: {
            Label("Feature Toggles", systemImage: "switch.2")
        } footer: {
            Text("@EnvironmentSpecific values can differ per environment (dev/staging/prod).")
        }
    }

    // MARK: - Cache Section

    @ViewBuilder
    private var cacheSection: some View {
        Section {
            ConfigRow(
                label: "Cache TTL",
                value: "\(AppConfiguration.cacheTTL)s",
                icon: "clock.arrow.circlepath"
            )
            ConfigRow(
                label: "Max Cache Size",
                value: "\(AppConfiguration.maxCacheSize) items",
                icon: "internaldrive"
            )
        } header: {
            Label("Cache", systemImage: "memorychip")
        }
    }

    // MARK: - Analytics Section

    @ViewBuilder
    private var analyticsSection: some View {
        Section {
            ConfigToggleRow(
                label: "Analytics Enabled",
                isOn: AppConfiguration.analyticsEnabled
            )
            ConfigRow(
                label: "Log Level",
                value: AppConfiguration.logLevel,
                icon: "list.bullet.rectangle"
            )
        } header: {
            Label("Analytics", systemImage: "chart.bar")
        } footer: {
            Text("@Validate(values:) restricts log level to trace, debug, info, warning, error.")
        }
    }

    // MARK: - Secrets Section

    @ViewBuilder
    private var secretsSection: some View {
        Section {
            SecretRow(label: "API Key", secretKey: "apiKey")
            SecretRow(label: "Analytics Tracking ID", secretKey: "analyticsTrackingId")

            Button {
                showingSecrets = true
            } label: {
                Label("Manage Secrets", systemImage: "key.fill")
            }
        } header: {
            Label("Secrets", systemImage: "lock.shield")
        } footer: {
            Text("@Secret properties are stored in Keychain with AES-256 encryption. The macro generates `resolved<Name>` getters.")
        }
    }

    // MARK: - Validation Section

    @ViewBuilder
    private var validationSection: some View {
        if let result = validationResult {
            Section {
                HStack {
                    Image(systemName: result.isValid ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundColor(result.isValid ? .green : .red)
                    Text(result.isValid ? "Configuration Valid" : "Validation Failed")
                        .font(.headline)
                }

                if !result.errors.isEmpty {
                    ForEach(result.errors.indices, id: \.self) { index in
                        HStack(alignment: .top) {
                            Image(systemName: "xmark.circle")
                                .foregroundColor(.red)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(result.errors[index].path)
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                Text(result.errors[index].message)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                if !result.warnings.isEmpty {
                    ForEach(result.warnings.indices, id: \.self) { index in
                        HStack(alignment: .top) {
                            Image(systemName: "exclamationmark.triangle")
                                .foregroundColor(.orange)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(result.warnings[index].path)
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                Text(result.warnings[index].message)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            } header: {
                Label("Validation Result", systemImage: "checkmark.shield")
            }
        }
    }

    // MARK: - Actions Section

    @ViewBuilder
    private var actionsSection: some View {
        Section {
            Button {
                validateConfiguration()
            } label: {
                Label("Validate Configuration", systemImage: "checkmark.shield")
            }

            Button {
                refreshRemoteConfig()
            } label: {
                HStack {
                    Label("Refresh Remote Config", systemImage: "arrow.clockwise")
                    Spacer()
                    if isRefreshing {
                        ProgressView()
                            .controlSize(.small)
                    }
                }
            }
            .disabled(isRefreshing)

            Button {
                showingOverrides = true
            } label: {
                Label("Manage Overrides", systemImage: "slider.horizontal.3")
            }

            Button(role: .destructive) {
                AppConfiguration.clearOverrides()
                validationResult = nil
            } label: {
                Label("Clear All Overrides", systemImage: "trash")
            }
        } header: {
            Label("Actions", systemImage: "gear")
        }
    }

    // MARK: - Usage Section

    @ViewBuilder
    private var usageSection: some View {
        Section {
            Text("""
            @Configuration(
                environmentPrefix: "ARCHERY",
                validateOnChange: true
            )
            struct AppConfiguration {
                @Required
                @Validate(pattern: "^https://.*")
                var apiBaseURL: String = "https://..."

                @EnvironmentSpecific
                var debugLogging: Bool = false

                @Secret
                var apiKey: String = ""
            }

            // Access configuration:
            let url = AppConfiguration.apiBaseURL

            // Override at runtime:
            AppConfiguration.override("debugLogging", value: true)
            """)
            .font(.system(.caption, design: .monospaced))
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.primary.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        } header: {
            Label("Usage", systemImage: "doc.text")
        }
    }

    // MARK: - Actions

    private func validateConfiguration() {
        do {
            _ = try AppConfiguration.validate()
            validationResult = ValidationResult(
                isValid: true,
                errors: [],
                warnings: []
            )
        } catch {
            validationResult = ValidationResult(
                isValid: false,
                errors: [ConfigValidationError(path: "root", message: error.localizedDescription)],
                warnings: []
            )
        }
    }

    private func refreshRemoteConfig() {
        isRefreshing = true
        Task {
            await AppConfiguration.refresh()
            await MainActor.run {
                isRefreshing = false
            }
        }
    }
}

// MARK: - Supporting Views

private struct MacroBadge: View {
    let icon: String
    let label: String

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption2)
            Text(label)
                .font(.caption2)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.accentColor.opacity(0.1))
        .clipShape(Capsule())
    }
}

private struct ConfigRow: View {
    let label: String
    let value: String
    let icon: String

    var body: some View {
        HStack {
            Label(label, systemImage: icon)
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
                .font(.system(.body, design: .monospaced))
                .lineLimit(1)
        }
    }
}

private struct ConfigToggleRow: View {
    let label: String
    let isOn: Bool
    var isEnvironmentSpecific: Bool = false

    var body: some View {
        HStack {
            Text(label)
            if isEnvironmentSpecific {
                Image(systemName: "globe")
                    .font(.caption)
                    .foregroundStyle(.blue)
            }
            Spacer()
            Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                .foregroundColor(isOn ? .green : .secondary)
        }
    }
}

private struct SecretRow: View {
    let label: String
    let secretKey: String
    @State private var isRevealed = false
    @State private var secretValue: String?

    var body: some View {
        HStack {
            Text(label)
            Spacer()

            if isRevealed, let value = secretValue {
                Text(value.prefix(12) + (value.count > 12 ? "..." : ""))
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
            } else {
                Text("********")
                    .foregroundStyle(.secondary)
            }

            Button(isRevealed ? "Hide" : "Show") {
                if !isRevealed {
                    loadSecret()
                }
                isRevealed.toggle()
            }
            .font(.caption)
            .buttonStyle(.bordered)
        }
    }

    private func loadSecret() {
        Task { @MainActor in
            if let secret = try? SecretsManager.shared.retrieve(secretKey) {
                secretValue = secret.value
            } else {
                secretValue = "(not set)"
            }
        }
    }
}

// MARK: - Overrides Sheet

struct ConfigurationOverridesSheet: View {
    @State private var overrideKey = ""
    @State private var overrideValue = ""
    @Environment(\.dismiss) private var dismiss

    private let availableKeys: [(key: String, type: String)] = [
        ("apiBaseURL", "String"),
        ("requestTimeout", "Int"),
        ("maxRetries", "Int"),
        ("debugLogging", "Bool"),
        ("performanceTracing", "Bool"),
        ("experimentalFeatures", "Bool"),
        ("cacheTTL", "Int"),
        ("maxCacheSize", "Int"),
        ("analyticsEnabled", "Bool"),
        ("logLevel", "String")
    ]

    var body: some View {
        NavigationStack {
            List {
                Section {
                    TextField("Configuration Key", text: $overrideKey)
                    TextField("Value", text: $overrideValue)

                    Button("Apply Override") {
                        applyOverride()
                    }
                    .disabled(overrideKey.isEmpty || overrideValue.isEmpty)
                } header: {
                    Text("Add Override")
                } footer: {
                    Text("Overrides are applied at runtime and persist until cleared.")
                }

                Section {
                    ForEach(availableKeys, id: \.key) { item in
                        Button {
                            overrideKey = item.key
                        } label: {
                            HStack {
                                Text(item.key)
                                    .font(.system(.body, design: .monospaced))
                                Spacer()
                                Text(item.type)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .tint(.primary)
                    }
                } header: {
                    Text("Available Keys")
                }
            }
            .navigationTitle("Overrides")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func applyOverride() {
        let value: Any
        if overrideValue.lowercased() == "true" {
            value = true
        } else if overrideValue.lowercased() == "false" {
            value = false
        } else if let intValue = Int(overrideValue) {
            value = intValue
        } else {
            value = overrideValue
        }

        AppConfiguration.override(overrideKey, value: value)
        overrideKey = ""
        overrideValue = ""
    }
}

// MARK: - Secrets Management Sheet

struct SecretsManagementSheet: View {
    @State private var secretKey = ""
    @State private var secretValue = ""
    @State private var storedSecrets: [String] = []
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    TextField("Secret Key", text: $secretKey)
                    SecureField("Secret Value", text: $secretValue)

                    Button("Store Secret") {
                        storeSecret()
                    }
                    .disabled(secretKey.isEmpty || secretValue.isEmpty)
                } header: {
                    Text("Add Secret")
                } footer: {
                    Text("Secrets are encrypted with AES-256 and stored in the Keychain.")
                }

                Section {
                    if storedSecrets.isEmpty {
                        Text("No secrets stored")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(storedSecrets, id: \.self) { key in
                            HStack {
                                Text(key)
                                    .font(.system(.body, design: .monospaced))
                                Spacer()
                                Button(role: .destructive) {
                                    deleteSecret(key)
                                } label: {
                                    Image(systemName: "trash")
                                }
                            }
                        }
                    }
                } header: {
                    Text("Stored Secrets")
                }
            }
            .navigationTitle("Secrets")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear {
                loadSecrets()
            }
        }
    }

    private func storeSecret() {
        Task { @MainActor in
            let secret = Secret(
                key: secretKey,
                value: secretValue,
                environment: ConfigurationEnvironment.current,
                tags: ["showcase"]
            )
            try? SecretsManager.shared.store(secret)
            secretKey = ""
            secretValue = ""
            loadSecrets()
        }
    }

    private func deleteSecret(_ key: String) {
        Task { @MainActor in
            try? SecretsManager.shared.delete(key)
            loadSecrets()
        }
    }

    private func loadSecrets() {
        Task { @MainActor in
            // Use retrieveAll and map to keys
            if let secrets = try? SecretsManager.shared.retrieveAll() {
                storedSecrets = secrets.map(\.key)
            }
        }
    }
}

#Preview {
    NavigationStack {
        ConfigurationView()
    }
}
