import Foundation
import SwiftUI
import Archery

// MARK: - @DesignTokens Demo
// This macro generates:
// - ColorToken enum with all color keys
// - TypographyToken enum with all typography keys
// - SpacingToken enum with all spacing keys
// - theme(for:) static method that builds an ArcheryTheme
// - Conforms to DesignTokenSet

// Using inline JSON manifest (the macro supports this format)
@DesignTokens(manifest: """
{
  "colors": {
    "brand": { "light": "#6366F1", "dark": "#818CF8", "highContrast": "#4F46E5" },
    "brandSecondary": { "light": "#EC4899", "dark": "#F472B6", "highContrast": "#DB2777" },
    "background": { "light": "#FFFFFF", "dark": "#111827", "highContrast": "#000000" },
    "foreground": { "light": "#111827", "dark": "#F9FAFB", "highContrast": "#FFFFFF" },
    "success": { "light": "#10B981", "dark": "#34D399", "highContrast": "#059669" },
    "error": { "light": "#EF4444", "dark": "#F87171", "highContrast": "#DC2626" }
  },
  "typography": {
    "headline": { "size": 22, "weight": "semibold", "lineHeight": 28 },
    "body": { "size": 17, "weight": "regular", "lineHeight": 22 },
    "caption": { "size": 12, "weight": "regular", "lineHeight": 16 }
  },
  "spacing": {
    "xs": 4,
    "sm": 8,
    "md": 12,
    "lg": 16,
    "xl": 24
  }
}
""")
public enum ShowcaseDesignTokens {}

// MARK: - Design Tokens Showcase View

struct DesignTokensShowcaseView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast

    private var currentVariant: ThemeVariant {
        if contrast == .increased { return .highContrast }
        return colorScheme == .dark ? .dark : .light
    }

    private var theme: ArcheryTheme {
        ShowcaseDesignTokens.theme(for: currentVariant)
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("@DesignTokens generates type-safe design system tokens from a JSON manifest.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text("Current variant: \(currentVariant.rawValue)")
                        .font(.caption.monospaced())
                        .foregroundStyle(theme.color(ShowcaseDesignTokens.ColorToken.brand))
                }
            }

            Section("Colors") {
                ForEach(ShowcaseDesignTokens.ColorToken.allCases, id: \.rawValue) { token in
                    HStack {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(theme.color(token))
                            .frame(width: 44, height: 44)
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .strokeBorder(Color.primary.opacity(0.1), lineWidth: 1)
                            )

                        VStack(alignment: .leading) {
                            Text(token.rawValue)
                                .font(.subheadline.weight(.medium))
                            if let hex = theme.colorHex(token) {
                                Text(hex)
                                    .font(.caption.monospaced())
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(.vertical, 2)
                }
            }

            Section("Typography") {
                ForEach(ShowcaseDesignTokens.TypographyToken.allCases, id: \.rawValue) { token in
                    let style = theme.typography(token)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("The quick brown fox")
                            .font(style.font)

                        HStack {
                            Text(token.rawValue)
                                .font(.caption.weight(.medium))
                            Spacer()
                            Text("\(Int(style.size))pt • \(weightName(style.weight))")
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }

            Section("Spacing") {
                HStack(alignment: .bottom, spacing: 12) {
                    ForEach(ShowcaseDesignTokens.SpacingToken.allCases, id: \.rawValue) { token in
                        let value = theme.spacing(token)
                        VStack(spacing: 4) {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(theme.color(ShowcaseDesignTokens.ColorToken.brand).opacity(0.3))
                                .frame(width: value, height: value)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 4)
                                        .strokeBorder(theme.color(ShowcaseDesignTokens.ColorToken.brand), lineWidth: 1)
                                )

                            Text(token.rawValue)
                                .font(.system(size: 9).weight(.medium))
                            Text("\(Int(value))")
                                .font(.system(size: 8).monospaced())
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }

            Section("Usage Example") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("@DesignTokens(manifest: \"tokens.json\")")
                        .font(.caption.monospaced())
                    Text("enum MyTokens {}")
                        .font(.caption.monospaced())
                    Text("")
                    Text("// Generated:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("MyTokens.ColorToken.brand")
                        .font(.caption.monospaced())
                    Text("MyTokens.TypographyToken.headline")
                        .font(.caption.monospaced())
                    Text("MyTokens.SpacingToken.lg")
                        .font(.caption.monospaced())
                    Text("MyTokens.theme(for: .dark)")
                        .font(.caption.monospaced())
                }
                .padding(8)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
        .navigationTitle("Design Tokens")
    }

    private func weightName(_ weight: Font.Weight) -> String {
        switch weight {
        case .ultraLight: return "ultraLight"
        case .thin: return "thin"
        case .light: return "light"
        case .regular: return "regular"
        case .medium: return "medium"
        case .semibold: return "semibold"
        case .bold: return "bold"
        case .heavy: return "heavy"
        case .black: return "black"
        default: return "regular"
        }
    }
}

#Preview {
    NavigationStack {
        DesignTokensShowcaseView()
    }
}
