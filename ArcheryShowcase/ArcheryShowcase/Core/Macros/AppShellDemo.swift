import Foundation
import SwiftUI
import Archery

// MARK: - @AppShell Demo
//
// The @AppShell macro generates a complete navigation shell including:
// - ShellView with TabView-based navigation
// - Per-tab NavigationStack with path management
// - Route enums for type-safe navigation
// - Sheet and full-screen cover presentation
// - Navigation state persistence
// - DI container integration
// - Preview providers
//
// Note: @AppShell is designed to be used at the app's root level.
// It generates a full ShellView struct and requires a Tab enum.
//
// Example usage:
// @AppShell
// struct MyAppShell {
//     enum Tab: CaseIterable { case home, settings }
//     enum Sheet { case newItem }
//
//     @MainActor
//     static func buildHome(_ route: HomeRoute, _ container: EnvContainer) -> some View { ... }
// }

// MARK: - Showcase View

struct AppShellShowcaseView: View {
    @State private var showingMiniDemo = false

    var body: some View {
        List {
            Section {
                Text("@AppShell generates a complete TabView-based navigation shell with state persistence, deep linking, and DI integration.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Generated Components") {
                ForEach(generatedComponents, id: \.name) { component in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(component.name)
                                .font(.subheadline.weight(.medium))
                            Text(component.description)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    }
                }
            }

            Section("Mini Shell Demo") {
                Button("Open Demo Shell") {
                    showingMiniDemo = true
                }
            }

            Section("Required Structure") {
                VStack(alignment: .leading, spacing: 4) {
                    Text("@AppShell")
                        .font(.caption.monospaced())
                    Text("struct MyAppShell {")
                        .font(.caption.monospaced())
                    Text("    // Required: Tab enum")
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                    Text("    enum Tab: CaseIterable {")
                        .font(.caption.monospaced())
                    Text("        case home, settings")
                        .font(.caption.monospaced())
                    Text("    }")
                        .font(.caption.monospaced())
                    Text("")
                    Text("    // Optional: Sheet/FullScreen enums")
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                    Text("    enum Sheet { case newItem }")
                        .font(.caption.monospaced())
                    Text("}")
                        .font(.caption.monospaced())
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            Section("Features") {
                AppShellFeatureRow(icon: "square.stack.3d.up", title: "Per-Tab Navigation", description: "Each tab maintains its own NavigationStack")
                AppShellFeatureRow(icon: "arrow.triangle.2.circlepath", title: "State Persistence", description: "Navigation state survives app restart")
                AppShellFeatureRow(icon: "link", title: "Deep Linking", description: "URL-based route matching")
                AppShellFeatureRow(icon: "cube.box", title: "DI Integration", description: "EnvContainer passed to all views")
                AppShellFeatureRow(icon: "rectangle.on.rectangle", title: "Modal Support", description: "Sheet and full-screen cover presentation")
            }
        }
        .navigationTitle("@AppShell")
        .fullScreenCover(isPresented: $showingMiniDemo) {
            MiniShellDemoView(isPresented: $showingMiniDemo)
        }
    }

    private var generatedComponents: [(name: String, description: String)] {
        [
            ("ShellView", "Main TabView with NavigationStacks"),
            ("Route Enums", "Type-safe routes per tab (e.g., HomeRoute)"),
            ("register(into:)", "DI registration for shell dependencies"),
            ("previewContainer()", "Preview-ready container setup"),
            ("Navigation Persistence", "Save/restore navigation state"),
            ("Sheet/FullScreen Bindings", "Modal presentation helpers")
        ]
    }
}

private struct AppShellFeatureRow: View {
    let icon: String
    let title: String
    let description: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(.tint)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

// Mini demo of the generated shell
private struct MiniShellDemoView: View {
    @Binding var isPresented: Bool
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                List {
                    Section("Home Tab") {
                        Text("This simulates what @AppShell generates")
                            .foregroundStyle(.secondary)
                        NavigationLink("Detail View") {
                            Text("Detail Content")
                                .navigationTitle("Detail")
                        }
                    }
                }
                .navigationTitle("Home")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close") { isPresented = false }
                    }
                }
            }
            .tabItem {
                Label("Home", systemImage: "house")
            }
            .tag(0)

            NavigationStack {
                List {
                    Text("Explore content here")
                }
                .navigationTitle("Explore")
            }
            .tabItem {
                Label("Explore", systemImage: "magnifyingglass")
            }
            .tag(1)

            NavigationStack {
                List {
                    Text("Profile content here")
                }
                .navigationTitle("Profile")
            }
            .tabItem {
                Label("Profile", systemImage: "person")
            }
            .tag(2)
        }
    }
}

#Preview {
    NavigationStack {
        AppShellShowcaseView()
    }
}
