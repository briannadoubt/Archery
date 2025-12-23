import SwiftUI
import Archery

// MARK: - Theme Manager
//
// ThemeManager handles user theme preferences (system/light/dark).
// Use it with ArcheryDesignTokens from the Archery library for design tokens.
//
// Example:
//   @EnvironmentObject var themeManager: ThemeManager
//   let theme = ArcheryDesignTokens.theme(for: themeManager.currentVariant)

@Observable
class ThemeManager {
    private static let themeKey = "app.theme"

    var currentTheme: AppTheme {
        didSet {
            UserDefaults.standard.set(currentTheme.rawValue, forKey: Self.themeKey)
        }
    }

    /// Returns the ThemeVariant corresponding to the current theme setting
    var currentVariant: ThemeVariant {
        switch currentTheme {
        case .system: return .light // Will be overridden by environment
        case .light: return .light
        case .dark: return .dark
        }
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

// MARK: - App Theme

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
