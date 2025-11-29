import SwiftUI

/// Default design token set generated from the shipped manifest.
@DesignTokens(manifest: """
{
  "colors": {
    "primary": { "light": "#0B6EFF", "dark": "#5EA1FF", "highContrast": "#005AE0" },
    "surface": { "light": "#FFFFFF", "dark": "#0D1320", "highContrast": "#000000" },
    "surfaceRaised": { "light": "#F4F6FB", "dark": "#111827", "highContrast": "#0A0A0A" },
    "text": { "light": "#0F172A", "dark": "#E5E7EB", "highContrast": "#FFFFFF" },
    "mutedText": { "light": "#6B7280", "dark": "#9CA3AF", "highContrast": "#D1D5DB" },
    "accent": { "light": "#FF7A45", "dark": "#FF9A6B", "highContrast": "#FF6B00" },
    "success": { "light": "#22C55E", "dark": "#4ADE80", "highContrast": "#1DB954" },
    "danger": { "light": "#D92D20", "dark": "#F97066", "highContrast": "#FF0000" }
  },
  "typography": {
    "title": { "size": 24, "weight": "semibold", "lineHeight": 30 },
    "body": { "size": 16, "weight": "regular", "lineHeight": 22 },
    "caption": { "size": 13, "weight": "regular", "lineHeight": 18 },
    "label": { "size": 15, "weight": "medium", "lineHeight": 20 }
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
public enum ArcheryDesignTokens {}
