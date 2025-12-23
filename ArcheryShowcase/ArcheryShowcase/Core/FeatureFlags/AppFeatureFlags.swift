import Archery

// MARK: - App Feature Flags

/// Feature flags for experimental functionality.
/// The @FeatureFlag macro generates nested flag types for each case.
///
/// Usage:
/// ```swift
/// // Check if a flag is enabled
/// if FeatureFlagManager.shared.isEnabled(for: AppFeatureFlags.AiSuggestionsFlag.self) { ... }
///
/// // Override in Settings/Labs
/// FeatureFlagManager.shared.override(AppFeatureFlags.AiSuggestionsFlag.self, with: true)
///
/// // Use in views
/// someView.featureFlag(AppFeatureFlags.AiSuggestionsFlag.self)
/// ```
@FeatureFlag
public enum AppFeatureFlags {
    /// AI-powered task suggestions based on history
    case aiSuggestions

    /// Smart scheduling that auto-assigns due dates
    case smartScheduling

    /// Compact list view mode for tasks
    case compactListView

    /// Quick add gesture (swipe down from anywhere)
    case quickAddGesture

    /// Widget customization options
    case advancedWidgets
}

// MARK: - App Feature Flags Registration

/// Convenience access to flag types
extension AppFeatureFlags {
    /// All available feature flags for iteration in Labs UI
    static var allFlags: [any FeatureFlag.Type] {
        [
            AiSuggestionsFlag.self,
            SmartSchedulingFlag.self,
            CompactListViewFlag.self,
            QuickAddGestureFlag.self,
            AdvancedWidgetsFlag.self
        ]
    }

    /// Human-readable names for each flag
    static func displayName(for key: String) -> String {
        switch key {
        case "ai-suggestions": return "AI Suggestions"
        case "smart-scheduling": return "Smart Scheduling"
        case "compact-list-view": return "Compact List View"
        case "quick-add-gesture": return "Quick Add Gesture"
        case "advanced-widgets": return "Advanced Widgets"
        default: return key.replacingOccurrences(of: "-", with: " ").capitalized
        }
    }

    /// Descriptions for each flag
    static func flagDescription(for key: String) -> String {
        switch key {
        case "ai-suggestions": return "Get AI-powered task suggestions based on your history and patterns"
        case "smart-scheduling": return "Automatically suggest due dates based on task content and your schedule"
        case "compact-list-view": return "Show more tasks on screen with a condensed list layout"
        case "quick-add-gesture": return "Swipe down from anywhere to quickly add a new task"
        case "advanced-widgets": return "Unlock additional widget customization options"
        default: return "Experimental feature"
        }
    }
}
