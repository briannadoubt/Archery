import SwiftUI
import Archery

struct SettingsView: View {
    @Environment(\.navigationHandle) private var nav

    var body: some View {
        List {
            Section("Account") {
                NavigationLink("Profile", destination: ProfileView())
                NavigationLink("Subscription", destination: SubscriptionView())
                NavigationLink("Privacy", destination: Text("Privacy Settings").navigationTitle("Privacy"))
            }

            Section("Preferences") {
                NavigationLink("Appearance", destination: AppearanceView())
                NavigationLink("Notifications", destination: NotificationsSettingsView())
                NavigationLink("Data & Storage", destination: Text("Data & Storage").navigationTitle("Data & Storage"))
            }

            Section("Developer") {
                NavigationLink { AnalyticsShowcaseView() } label: {
                    Label("Analytics & Events", systemImage: "chart.bar.xaxis")
                }
                NavigationLink { ObservabilityShowcaseView() } label: {
                    Label("Observability Dashboard", systemImage: "waveform.path.ecg")
                }
                NavigationLink { MonetizationShowcaseView() } label: {
                    Label("StoreKit & Monetization", systemImage: "creditcard")
                }
                NavigationLink { DatabaseShowcaseView() } label: {
                    Label("Database Persistence", systemImage: "cylinder.split.1x2")
                }
                NavigationLink("Macro Showcase", destination: MacroShowcaseView())
                NavigationLink("Advanced Macros", destination: AdvancedMacrosShowcaseView())
                NavigationLink("App Intents", destination: AppIntentsShowcaseView())
                NavigationLink("Widget Setup", destination: WidgetSharedPreview())
                NavigationLink("Routes & Deep Links", destination: DeepLinkTesterView())
                NavigationLink("Design Tokens", destination: DesignTokensShowcaseView())
                NavigationLink("@ViewModelBound", destination: ViewModelBoundShowcaseView())
                NavigationLink("@AppShell", destination: AppShellShowcaseView())
                NavigationLink("@SharedModel", destination: SharedModelShowcaseView())
            }

            Section("About") {
                NavigationLink("Help & Support", destination: Text("Help").navigationTitle("Help"))
                NavigationLink("Terms of Service", destination: Text("Terms").navigationTitle("Terms"))
                NavigationLink("Privacy Policy", destination: Text("Privacy").navigationTitle("Privacy"))
            }
        }
        .navigationTitle("Settings")
    }
}

#Preview {
    NavigationStack {
        SettingsView()
    }
}
