import SwiftUI
import Archery

struct SettingsView: View {
    @Environment(\.navigationHandle) private var nav

    var body: some View {
        List {
            windowsSection

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

            #if os(iOS) || os(visionOS)
            Section("Siri & Shortcuts") {
                AppShortcutsButton {
                    // Optional: track analytics when user opens shortcuts
                }
            }
            #endif

            Section("About") {
                NavigationLink("Help & Support", destination: Text("Help").navigationTitle("Help"))
                NavigationLink("Terms of Service", destination: Text("Terms").navigationTitle("Terms"))
                NavigationLink("Privacy Policy", destination: Text("Privacy").navigationTitle("Privacy"))
            }

            Section {
                NavigationLink {
                    LabsSettingsView()
                } label: {
                    Label("Labs", systemImage: "flask")
                }
            } header: {
                Label("Experimental", systemImage: "testtube.2")
            } footer: {
                Text("Try experimental features before they're fully released. These features may change or be removed.")
            }

            Section("Debug") {
                NavigationLink("Deep Links", destination: DeepLinkTesterView())
            }

            Section {
                NavigationLink {
                    DeveloperToolsView()
                } label: {
                    Label("Developer Tools", systemImage: "hammer")
                }
            } header: {
                Label("For Developers", systemImage: "terminal")
            } footer: {
                Text("CLI plugins for scaffolding features, linting architecture, and checking performance budgets.")
            }
        }
        .navigationTitle("Settings")
    }

    // MARK: - Windows Section
    //
    // Uses the navigation handle to present routes in windows.
    // The @presents(.window, id: "...") annotation on the route cases
    // tells the navigation system to open them in separate windows.
    // On unsupported platforms, they fall back to push navigation.

    @ViewBuilder
    private var windowsSection: some View {
        Section {
            Button {
                // Navigate using the route - automatically opens in window
                // because SettingsRoute.preferences has @presents(.window, id: "preferences")
                nav?.navigate(to: SettingsRoute.preferences)
            } label: {
                Label("Open Preferences Window", systemImage: "gearshape.2")
            }

            Button {
                nav?.navigate(to: SettingsRoute.macroExplorer)
            } label: {
                Label("Open Macro Explorer", systemImage: "chevron.left.forwardslash.chevron.right")
            }

            Button {
                nav?.navigate(to: SettingsRoute.quickEntry)
            } label: {
                Label("Quick Task Entry", systemImage: "plus.rectangle")
            }
        } header: {
            Label("Additional Windows", systemImage: "macwindow.on.rectangle")
        } footer: {
            #if os(macOS) || os(iOS) || os(visionOS)
            Text("Uses nav.navigate(to: .preferences) - same API as sheets/push. The @presents(.window) annotation opens it in a window.")
            #else
            Text("Window presentation not supported on this platform. Routes will use push navigation instead.")
            #endif
        }
    }
}

#Preview {
    NavigationStack {
        SettingsView()
    }
}
