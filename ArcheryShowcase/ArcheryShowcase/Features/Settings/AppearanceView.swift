import SwiftUI

struct AppearanceView: View {
    @Environment(ThemeManager.self) var themeManager

    var body: some View {
        @Bindable var themeManager = themeManager
        Form {
            Section("Theme") {
                Picker("Appearance", selection: $themeManager.currentTheme) {
                    ForEach(AppTheme.allCases, id: \.self) { theme in
                        Label(theme.displayName, systemImage: theme.icon)
                            .tag(theme)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            }

            Section("Preview") {
                PreviewColors()
            }

            Section {
                Text("Theme changes are applied immediately and saved automatically.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Appearance")
    }
}

private struct PreviewColors: View {
    var body: some View {
        HStack(spacing: 16) {
            ColorSwatch(color: Color.accentColor, label: "Accent", isLight: false)
            #if os(macOS)
            ColorSwatch(color: Color(NSColor.windowBackgroundColor), label: "Background", isLight: true)
            ColorSwatch(color: Color(NSColor.controlBackgroundColor), label: "Secondary", isLight: true)
            #else
            ColorSwatch(color: Color(.systemBackground), label: "Background", isLight: true)
            ColorSwatch(color: Color(.secondarySystemBackground), label: "Secondary", isLight: true)
            #endif
        }
    }
}

private struct ColorSwatch: View {
    let color: Color
    let label: String
    let isLight: Bool

    var body: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(color)
            .frame(height: 60)
            .overlay {
                Text(label)
                    .font(.caption)
                    .foregroundColor(isLight ? .primary : .white)
            }
    }
}

#Preview {
    NavigationStack {
        AppearanceView()
            .environment(ThemeManager())
    }
}
