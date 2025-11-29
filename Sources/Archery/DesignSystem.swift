import Foundation
#if canImport(SwiftUI)
import SwiftUI

public enum ThemeVariant: String, CaseIterable, Hashable, Sendable {
    case light
    case dark
    case highContrast

    var colorScheme: ColorScheme {
        switch self {
        case .light, .highContrast: return .light
        case .dark: return .dark
        }
    }

    var colorSchemeContrast: ColorSchemeContrast {
        self == .highContrast ? .increased : .standard
    }

    static func resolve(colorScheme: ColorScheme, contrast: ColorSchemeContrast) -> ThemeVariant {
        if contrast == .increased { return .highContrast }
        return colorScheme == .dark ? .dark : .light
    }
}

public struct TypographyStyle: Sendable, Equatable {
    public let size: CGFloat
    public let weight: Font.Weight
    public let lineHeight: CGFloat?
    public let design: Font.Design

    public init(
        size: CGFloat,
        weight: Font.Weight,
        lineHeight: CGFloat? = nil,
        design: Font.Design = .default
    ) {
        self.size = size
        self.weight = weight
        self.lineHeight = lineHeight
        self.design = design
    }

    public var font: Font {
        Font.system(size: size, weight: weight, design: design)
    }
}

public struct ArcheryTheme: Sendable {
    public let name: String
    public let variant: ThemeVariant

    private let colors: [String: Color]
    private let colorHex: [String: String]
    private let typography: [String: TypographyStyle]
    private let spacing: [String: CGFloat]

    public init(
        name: String,
        variant: ThemeVariant,
        colors: [String: Color],
        colorHex: [String: String],
        typography: [String: TypographyStyle],
        spacing: [String: CGFloat]
    ) {
        self.name = name
        self.variant = variant
        self.colors = colors
        self.colorHex = colorHex
        self.typography = typography
        self.spacing = spacing
    }

    public func color<T: RawRepresentable>(_ token: T) -> Color where T.RawValue == String {
        colors[token.rawValue] ?? Color.clear
    }

    public func colorHex<T: RawRepresentable>(_ token: T) -> String? where T.RawValue == String {
        colorHex[token.rawValue]
    }

    public func typography<T: RawRepresentable>(_ token: T) -> TypographyStyle where T.RawValue == String {
        typography[token.rawValue] ?? TypographyStyle(size: 16, weight: .regular, lineHeight: nil)
    }

    public func spacing<T: RawRepresentable>(_ token: T) -> CGFloat where T.RawValue == String {
        spacing[token.rawValue] ?? 0
    }

    public static func resolvedColor(
        variant: ThemeVariant,
        light: String,
        dark: String?,
        highContrast: String?
    ) -> Color {
        Color(hex: resolvedHex(variant: variant, light: light, dark: dark, highContrast: highContrast))
    }

    public static func resolvedHex(
        variant: ThemeVariant,
        light: String,
        dark: String?,
        highContrast: String?
    ) -> String {
        switch variant {
        case .light:
            return light
        case .dark:
            return dark ?? light
        case .highContrast:
            return highContrast ?? dark ?? light
        }
    }
}

public protocol DesignTokenSet {
    static var name: String { get }
    static func theme(for variant: ThemeVariant) -> ArcheryTheme
}

// MARK: - Color Helpers

public extension Color {
    init(hex: String) {
        let cleaned = hex.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "#", with: "")
        var int: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&int)

        let a, r, g, b: UInt64
        switch cleaned.count {
        case 6: // RRGGBB
            (a, r, g, b) = (255, (int >> 16) & 0xFF, (int >> 8) & 0xFF, int & 0xFF)
        case 8: // AARRGGBB
            (a, r, g, b) = ((int >> 24) & 0xFF, (int >> 16) & 0xFF, (int >> 8) & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }

        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

// MARK: - Environment plumbing

private struct ArcheryThemeKey: EnvironmentKey {
    static let defaultValue = ArcheryTheme(
        name: "ArcheryTheme.placeholder",
        variant: .light,
        colors: [:],
        colorHex: [:],
        typography: [:],
        spacing: [:]
    )
}

private struct ArcheryThemeVariantKey: EnvironmentKey {
    static let defaultValue: ThemeVariant = .light
}

public extension EnvironmentValues {
    var archeryTheme: ArcheryTheme {
        get { self[ArcheryThemeKey.self] }
        set { self[ArcheryThemeKey.self] = newValue }
    }

    var archeryThemeVariant: ThemeVariant {
        get { self[ArcheryThemeVariantKey.self] }
        set { self[ArcheryThemeVariantKey.self] = newValue }
    }
}

private struct ArcheryThemeScope<Tokens: DesignTokenSet>: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    let tokens: Tokens.Type
    let overrideVariant: ThemeVariant?

    func body(content: Content) -> some View {
        let variant = overrideVariant ?? ThemeVariant.resolve(colorScheme: colorScheme, contrast: colorSchemeContrast)
        let theme = Tokens.theme(for: variant)
        return content
            .environment(\.archeryThemeVariant, variant)
            .environment(\.archeryTheme, theme)
    }
}

public extension View {
    func archeryThemeScope<Tokens: DesignTokenSet>(
        _ tokens: Tokens.Type = ArcheryDesignTokens.self,
        variant: ThemeVariant? = nil
    ) -> some View {
        modifier(ArcheryThemeScope(tokens: tokens, overrideVariant: variant))
    }
}

// MARK: - Preview Catalog

public struct ThemePreviewCatalog<Tokens: DesignTokenSet, Content: View>: View {
    private let tokens: Tokens.Type
    private let content: (ThemeVariant, ArcheryTheme) -> Content

    public init(
        tokens: Tokens.Type = ArcheryDesignTokens.self,
        @ViewBuilder content: @escaping (ThemeVariant, ArcheryTheme) -> Content
    ) {
        self.tokens = tokens
        self.content = content
    }

    public var body: some View {
        ForEach(Array(ThemeVariant.allCases), id: \.self) { variant in
            let theme = tokens.theme(for: variant)
            content(variant, theme)
                .environment(\.archeryTheme, theme)
                .environment(\.archeryThemeVariant, variant)
                .environment(\.colorScheme, variant.colorScheme)
        }
    }
}
#endif
