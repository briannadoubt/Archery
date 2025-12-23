import SwiftUI
import Archery

// MARK: - Labs Settings View

/// Settings view for experimental feature flags.
/// Uses @FeatureFlag and FeatureFlagManager for runtime toggles.
struct LabsSettingsView: View {
    private var flagManager: FeatureFlagManager { FeatureFlagManager.shared }
    @State private var hasPremium = false

    var body: some View {
        let flagManager = FeatureFlagManager.shared
        List {
            Section {
                Text("These features are experimental and may not work as expected. Enable them to try new functionality before it's fully released.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            #if DEBUG
            Section("Debug Entitlements") {
                Toggle(isOn: $hasPremium) {
                    Label("Unlock Premium", systemImage: "crown.fill")
                }
                .onChange(of: hasPremium) { _, newValue in
                    if newValue {
                        StoreKitManager.shared.grantDebugEntitlement(.premium)
                    } else {
                        StoreKitManager.shared.revokeDebugEntitlement(.premium)
                    }
                }

                Text("Grants premium entitlement for testing locked features like Insights tab.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            #endif

            Section("AI & Automation") {
                FeatureFlagToggle<AppFeatureFlags.AiSuggestionsFlag>()
                FeatureFlagToggle<AppFeatureFlags.SmartSchedulingFlag>()
            }

            Section("User Interface") {
                FeatureFlagToggle<AppFeatureFlags.CompactListViewFlag>()
                FeatureFlagToggle<AppFeatureFlags.QuickAddGestureFlag>()
            }

            Section("Widgets") {
                FeatureFlagToggle<AppFeatureFlags.AdvancedWidgetsFlag>()
            }

            if !flagManager.overrides.isEmpty {
                Section {
                    Button("Reset All to Defaults", role: .destructive) {
                        flagManager.clearOverrides()
                    }
                }
            }
        }
        .navigationTitle("Labs")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            #if DEBUG
            hasPremium = StoreKitManager.shared.hasEntitlement(.premium)
            #endif
        }
    }
}

// MARK: - Feature Flag Toggle

/// Reusable toggle for a single feature flag.
struct FeatureFlagToggle<Flag: FeatureFlag>: View where Flag.Value == Bool {
    @State private var isEnabled: Bool = false

    private var manager: FeatureFlagManager { FeatureFlagManager.shared }

    private var displayName: String {
        AppFeatureFlags.displayName(for: Flag.key)
    }

    private var description: String {
        AppFeatureFlags.flagDescription(for: Flag.key)
    }

    private var hasOverride: Bool {
        manager.overrides[Flag.key] != nil
    }

    var body: some View {
        let manager = FeatureFlagManager.shared
        VStack(alignment: .leading, spacing: 4) {
            Toggle(isOn: $isEnabled) {
                HStack {
                    Text(displayName)
                    if hasOverride {
                        Image(systemName: "arrow.uturn.backward.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.blue)
                    }
                }
            }
            .onChange(of: isEnabled) { _, newValue in
                manager.override(Flag.self, with: newValue)
            }

            Text(description)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
        .onAppear {
            isEnabled = manager.isEnabled(for: Flag.self)
        }
        .contextMenu {
            if hasOverride {
                Button("Reset to Default") {
                    manager.override(Flag.self, with: nil)
                    isEnabled = Flag.defaultValue
                }
            }
        }
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        LabsSettingsView()
    }
}
