import SwiftUI

/// Developer Tools documentation view - explains available CLI plugins
struct DeveloperToolsView: View {
    var body: some View {
        List {
            Section {
                Text("Archery includes command-line plugins to help with development. Run these from your project directory using Swift Package Manager.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Section("Feature Scaffold") {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Generate new features with all the Archery macros pre-configured.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    CodeBlockView("""
                    swift package plugin feature-scaffold Profile ./Features
                    """)

                    Text("Creates:")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    VStack(alignment: .leading, spacing: 4) {
                        BulletPoint("ProfileView.swift - SwiftUI view")
                        BulletPoint("ProfileViewModel.swift - @Observable ViewModel")
                        BulletPoint("ProfileItem.swift - @Persistable model")
                        BulletPoint("ProfileRoute.swift - @Route navigation")
                        BulletPoint("ProfileTests.swift - Unit tests")
                    }
                }
                .padding(.vertical, 4)
            }

            Section("Architecture Linter") {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Enforce architectural boundaries and best practices.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    CodeBlockView("""
                    swift package plugin archery-lint
                    """)

                    Text("Rules enforced:")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    VStack(alignment: .leading, spacing: 4) {
                        BulletPoint("No feature-to-feature imports")
                        BulletPoint("Views shouldn't import persistence directly")
                        BulletPoint("Use shared modules for cross-feature code")
                    }

                    Text("CI Integration:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)

                    CodeBlockView("""
                    swift run archery-lint --format github
                    """)
                }
                .padding(.vertical, 4)
            }

            Section("Performance Budget") {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Check binary size and build time against defined budgets.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    CodeBlockView("""
                    swift package plugin archery-budget \\
                      --binary .build/release/MyApp \\
                      --build-time 45.2
                    """)

                    Text("Thresholds:")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    VStack(alignment: .leading, spacing: 4) {
                        BulletPoint("Binary size: 50 MB default")
                        BulletPoint("Build time: 2 minutes default")
                        BulletPoint("Configurable via JSON")
                    }
                }
                .padding(.vertical, 4)
            }

            Section {
                Link(destination: URL(string: "https://github.com/briannadoubt/Archery#developer-tools")!) {
                    Label("View Documentation", systemImage: "book")
                }

                Link(destination: URL(string: "https://github.com/briannadoubt/Archery/issues")!) {
                    Label("Report an Issue", systemImage: "ladybug")
                }
            }
        }
        .navigationTitle("Developer Tools")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.large)
        #endif
    }
}

// MARK: - Supporting Views

private struct CodeBlockView: View {
    let code: String

    init(_ code: String) {
        self.code = code
    }

    var body: some View {
        Text(code)
            .font(.system(.caption, design: .monospaced))
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.primary.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private struct BulletPoint: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text("•")
                .foregroundStyle(.secondary)
            Text(text)
                .font(.caption)
        }
    }
}

#Preview {
    NavigationStack {
        DeveloperToolsView()
    }
}
