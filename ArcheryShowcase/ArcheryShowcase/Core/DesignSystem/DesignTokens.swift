import SwiftUI
import Archery

// MARK: - Design Tokens

@DesignTokens(
    source: .figma(fileId: "demo-file-id", token: "demo-token"),
    platforms: [.iOS, .macOS, .watchOS, .tvOS],
    themes: [.light, .dark, .highContrast]
)
struct DesignTokens {
    // MARK: - Colors
    struct Colors {
        let primary: Color
        let secondary: Color
        let tertiary: Color
        let accent: Color
        let background: Color
        let surface: Color
        let error: Color
        let warning: Color
        let success: Color
        let info: Color
        
        // Semantic colors
        let textPrimary: Color
        let textSecondary: Color
        let textDisabled: Color
        let border: Color
        let divider: Color
        let overlay: Color
        
        // Brand colors
        let brand100: Color
        let brand200: Color
        let brand300: Color
        let brand400: Color
        let brand500: Color
        let brand600: Color
        let brand700: Color
        let brand800: Color
        let brand900: Color
    }
    
    // MARK: - Typography
    struct Typography {
        let largeTitle: Font
        let title1: Font
        let title2: Font
        let title3: Font
        let headline: Font
        let body: Font
        let callout: Font
        let subheadline: Font
        let footnote: Font
        let caption1: Font
        let caption2: Font
        
        // Weights
        let regular: Font.Weight = .regular
        let medium: Font.Weight = .medium
        let semibold: Font.Weight = .semibold
        let bold: Font.Weight = .bold
    }
    
    // MARK: - Spacing
    struct Spacing {
        let xSmall: CGFloat = 4
        let small: CGFloat = 8
        let medium: CGFloat = 16
        let large: CGFloat = 24
        let xLarge: CGFloat = 32
        let xxLarge: CGFloat = 48
        let xxxLarge: CGFloat = 64
    }
    
    // MARK: - Corner Radius
    struct CornerRadius {
        let small: CGFloat = 4
        let medium: CGFloat = 8
        let large: CGFloat = 12
        let xLarge: CGFloat = 16
        let round: CGFloat = 9999
    }
    
    // MARK: - Shadows
    struct Shadows {
        let small: Shadow
        let medium: Shadow
        let large: Shadow
        let inner: Shadow
        
        struct Shadow {
            let color: Color
            let radius: CGFloat
            let x: CGFloat
            let y: CGFloat
        }
    }
    
    // MARK: - Animation
    struct Animation {
        let fast: Double = 0.15
        let normal: Double = 0.25
        let slow: Double = 0.35
        let spring: SwiftUI.Animation = .spring(response: 0.3, dampingFraction: 0.7)
        let easeIn: SwiftUI.Animation = .easeIn(duration: 0.25)
        let easeOut: SwiftUI.Animation = .easeOut(duration: 0.25)
        let easeInOut: SwiftUI.Animation = .easeInOut(duration: 0.25)
    }
    
    // MARK: - Breakpoints
    struct Breakpoints {
        let small: CGFloat = 320
        let medium: CGFloat = 768
        let large: CGFloat = 1024
        let xLarge: CGFloat = 1440
    }
    
    // MARK: - Default Values
    static let `default` = DesignTokens(
        colors: Colors(
            primary: .blue,
            secondary: .gray,
            tertiary: .green,
            accent: .accentColor,
            background: Color(.systemBackground),
            surface: Color(.secondarySystemBackground),
            error: .red,
            warning: .orange,
            success: .green,
            info: .blue,
            textPrimary: .primary,
            textSecondary: .secondary,
            textDisabled: Color(.tertiaryLabel),
            border: Color(.separator),
            divider: Color(.separator),
            overlay: Color.black.opacity(0.4),
            brand100: Color(hex: "#E3F2FF"),
            brand200: Color(hex: "#B8DFFF"),
            brand300: Color(hex: "#8DCBFF"),
            brand400: Color(hex: "#62B7FF"),
            brand500: Color(hex: "#37A3FF"),
            brand600: Color(hex: "#0C8FFF"),
            brand700: Color(hex: "#0070E0"),
            brand800: Color(hex: "#0052B0"),
            brand900: Color(hex: "#003480")
        ),
        typography: Typography(
            largeTitle: .largeTitle,
            title1: .title,
            title2: .title2,
            title3: .title3,
            headline: .headline,
            body: .body,
            callout: .callout,
            subheadline: .subheadline,
            footnote: .footnote,
            caption1: .caption,
            caption2: .caption2
        ),
        spacing: Spacing(),
        cornerRadius: CornerRadius(),
        shadows: Shadows(
            small: .init(color: .black.opacity(0.1), radius: 2, x: 0, y: 1),
            medium: .init(color: .black.opacity(0.15), radius: 4, x: 0, y: 2),
            large: .init(color: .black.opacity(0.2), radius: 8, x: 0, y: 4),
            inner: .init(color: .black.opacity(0.05), radius: 2, x: 0, y: -1)
        ),
        animation: Animation(),
        breakpoints: Breakpoints()
    )
    
    static let light = `default`
    
    static let dark = DesignTokens(
        colors: Colors(
            primary: .blue,
            secondary: .gray,
            tertiary: .green,
            accent: .accentColor,
            background: Color(.systemBackground),
            surface: Color(.secondarySystemBackground),
            error: .red,
            warning: .orange,
            success: .green,
            info: .blue,
            textPrimary: .primary,
            textSecondary: .secondary,
            textDisabled: Color(.tertiaryLabel),
            border: Color(.separator),
            divider: Color(.separator),
            overlay: Color.black.opacity(0.6),
            brand100: Color(hex: "#003480"),
            brand200: Color(hex: "#0052B0"),
            brand300: Color(hex: "#0070E0"),
            brand400: Color(hex: "#0C8FFF"),
            brand500: Color(hex: "#37A3FF"),
            brand600: Color(hex: "#62B7FF"),
            brand700: Color(hex: "#8DCBFF"),
            brand800: Color(hex: "#B8DFFF"),
            brand900: Color(hex: "#E3F2FF")
        ),
        typography: Typography(
            largeTitle: .largeTitle,
            title1: .title,
            title2: .title2,
            title3: .title3,
            headline: .headline,
            body: .body,
            callout: .callout,
            subheadline: .subheadline,
            footnote: .footnote,
            caption1: .caption,
            caption2: .caption2
        ),
        spacing: Spacing(),
        cornerRadius: CornerRadius(),
        shadows: Shadows(
            small: .init(color: .white.opacity(0.1), radius: 2, x: 0, y: 1),
            medium: .init(color: .white.opacity(0.15), radius: 4, x: 0, y: 2),
            large: .init(color: .white.opacity(0.2), radius: 8, x: 0, y: 4),
            inner: .init(color: .white.opacity(0.05), radius: 2, x: 0, y: -1)
        ),
        animation: Animation(),
        breakpoints: Breakpoints()
    )
    
    let colors: Colors
    let typography: Typography
    let spacing: Spacing
    let cornerRadius: CornerRadius
    let shadows: Shadows
    let animation: Animation
    let breakpoints: Breakpoints
}

// MARK: - Environment Key

private struct DesignTokensKey: EnvironmentKey {
    static let defaultValue = DesignTokens.default
}

extension EnvironmentValues {
    var designTokens: DesignTokens {
        get { self[DesignTokensKey.self] }
        set { self[DesignTokensKey.self] = newValue }
    }
}

// MARK: - Color Extension

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (1, 1, 1, 0)
        }
        
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue:  Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}