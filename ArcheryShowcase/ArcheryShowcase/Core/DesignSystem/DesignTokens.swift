import SwiftUI
import Archery

// MARK: - @DesignTokens Demo
// Demonstrates the @DesignTokens macro which generates:
// - ColorToken enum with all color cases
// - TypographyToken enum with all typography cases
// - SpacingToken enum with all spacing cases
// - theme(for:) static method returning ArcheryTheme
// - DesignTokenSet protocol conformance
//
// Example usage:
// @DesignTokens(manifest: "path/to/design-tokens.json")
// enum MyDesignTokens {}
//
// The macro reads a JSON manifest with colors, typography, and spacing definitions.

// MARK: - Design Tokens (manual implementation showing macro pattern)

struct DesignTokens {
    // MARK: - Colors
    struct Colors {
        let primary = Color.blue
        let secondary = Color.gray
        let tertiary = Color(.tertiaryLabel)
        let accent = Color.accentColor
        let background = Color(.systemBackground)
        let surface = Color(.secondarySystemBackground)
        let error = Color.red
        let warning = Color.orange
        let success = Color.green
        let info = Color.blue

        // Semantic colors
        let textPrimary = Color.primary
        let textSecondary = Color.secondary
        let textDisabled = Color(.tertiaryLabel)
        let border = Color(.separator)
        let divider = Color(.separator)
        let overlay = Color.black.opacity(0.4)
    }

    // MARK: - Typography
    struct Typography {
        let largeTitle = Font.largeTitle
        let title1 = Font.title
        let title2 = Font.title2
        let title3 = Font.title3
        let headline = Font.headline
        let body = Font.body
        let callout = Font.callout
        let subheadline = Font.subheadline
        let footnote = Font.footnote
        let caption1 = Font.caption
        let caption2 = Font.caption2
    }

    // MARK: - Spacing
    struct Spacing {
        let xxSmall: CGFloat = 2
        let xSmall: CGFloat = 4
        let small: CGFloat = 8
        let medium: CGFloat = 16
        let large: CGFloat = 24
        let xLarge: CGFloat = 32
        let xxLarge: CGFloat = 48
    }

    // MARK: - Corner Radius
    struct CornerRadius {
        let small: CGFloat = 4
        let medium: CGFloat = 8
        let large: CGFloat = 12
        let xLarge: CGFloat = 16
        let full: CGFloat = 9999
    }

    // MARK: - Shadows
    struct Shadows {
        let small = ShadowStyle(color: .black.opacity(0.1), radius: 2, y: 1)
        let medium = ShadowStyle(color: .black.opacity(0.1), radius: 4, y: 2)
        let large = ShadowStyle(color: .black.opacity(0.1), radius: 8, y: 4)
    }

    struct ShadowStyle {
        let color: Color
        let radius: CGFloat
        let y: CGFloat
    }

    // MARK: - Animation
    struct Animation {
        let quick = SwiftUI.Animation.easeInOut(duration: 0.15)
        let normal = SwiftUI.Animation.easeInOut(duration: 0.3)
        let slow = SwiftUI.Animation.easeInOut(duration: 0.5)
        let spring = SwiftUI.Animation.spring(response: 0.3, dampingFraction: 0.7)
    }

    // MARK: - Instances
    let colors = Colors()
    let typography = Typography()
    let spacing = Spacing()
    let cornerRadius = CornerRadius()
    let shadows = Shadows()
    let animation = Animation()

    // MARK: - Default
    static let `default` = DesignTokens()
}

// MARK: - Environment Key

struct DesignTokensKey: EnvironmentKey {
    static let defaultValue = DesignTokens.default
}

extension EnvironmentValues {
    var designTokens: DesignTokens {
        get { self[DesignTokensKey.self] }
        set { self[DesignTokensKey.self] = newValue }
    }
}

// MARK: - Theme Manager

class ThemeManager: ObservableObject {
    private static let themeKey = "app.theme"

    @Published var currentTheme: AppTheme {
        didSet {
            UserDefaults.standard.set(currentTheme.rawValue, forKey: Self.themeKey)
        }
    }

    var currentTokens: DesignTokens {
        DesignTokens.default
    }

    init() {
        if let saved = UserDefaults.standard.string(forKey: Self.themeKey),
           let theme = AppTheme(rawValue: saved) {
            self.currentTheme = theme
        } else {
            self.currentTheme = .system
        }
    }
}

enum AppTheme: String, Codable, CaseIterable {
    case system
    case light
    case dark

    var displayName: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    var icon: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .light: return "sun.max.fill"
        case .dark: return "moon.fill"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .light: return .light
        case .dark: return .dark
        case .system: return nil
        }
    }
}
