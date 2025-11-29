# Accessibility & Localization Platform Support

## Platform Support Matrix

This document outlines the platform-specific support for accessibility and localization features in the Archery framework.

### Accessibility Features

| Feature | iOS/iPadOS | macOS | tvOS | watchOS | visionOS | Mac Catalyst |
|---------|------------|-------|------|---------|----------|--------------|
| **Accessibility Labels** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| **Accessibility Hints** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| **Accessibility Identifiers** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| **Accessibility Traits** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| **Dynamic Type Validation** | ✅ | ⚠️ | ✅ | ⚠️ | ✅ | ✅ |
| **Contrast Ratio Analysis** | ✅ | ✅ | ✅ | ⚠️ | ✅ | ✅ |
| **Tap Target Size Validation** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| **VoiceOver Support** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |

### Localization Features

| Feature | iOS/iPadOS | macOS | tvOS | watchOS | visionOS | Mac Catalyst |
|---------|------------|-------|------|---------|----------|--------------|
| **String Localization** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| **RTL Layout Support** | ✅ | ✅ | ✅ | ⚠️ | ✅ | ✅ |
| **Pseudo-Localization** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| **Double-Length Testing** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| **Accented Characters** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| **@Localizable Macro** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| **String Extraction** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| **Missing Key Detection** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |

### Legend

- ✅ Full Support
- ⚠️ Limited Support (see notes below)
- ❌ Not Supported

## Platform-Specific Notes

### macOS
- **Dynamic Type**: macOS doesn't have Dynamic Type in the same way as iOS. Text scaling is handled through System Preferences → Accessibility → Display → Text Size
- **Color Space**: macOS uses different color spaces than iOS. The framework automatically converts to sRGB for contrast calculations to avoid crashes with catalog colors

### watchOS
- **RTL Layout**: Limited screen space makes RTL layout support less comprehensive than on larger screens
- **Dynamic Type**: Simplified Dynamic Type support due to screen constraints
- **Contrast Ratio**: Limited color depth on some older Apple Watch models

### tvOS
- **Navigation**: Focus-based navigation requires additional accessibility considerations
- **Tap Targets**: Replaced with focus targets for remote control interaction

## Usage Examples

### iOS-Specific Dynamic Type Validation
```swift
#if os(iOS) || os(tvOS)
let diagnostic = DynamicTypeValidator.validateTextScaling(
    for: "Long text string",
    containerWidth: 320,
    font: .body
)
#endif
```

### macOS-Specific Color Handling
```swift
#if canImport(AppKit)
// Automatically converts to sRGB color space
let contrast = ContrastRatio(
    foreground: .systemBlue,
    background: .systemBackground
)
#endif
```

### Universal Accessibility Labels
```swift
// Works on all platforms
Text("Submit")
    .accessibilityLabel("Submit form")
    .accessibilityHint("Double tap to submit the form")
    .accessibilityIdentifier("submit_button")
```

## Testing Recommendations

### iOS/iPadOS
1. Test with VoiceOver enabled
2. Test all Dynamic Type sizes from XS to XXXL
3. Test with Accessibility Inspector
4. Validate RTL layouts with Arabic or Hebrew locales

### macOS
1. Test with VoiceOver enabled
2. Test with increased contrast mode
3. Validate keyboard navigation
4. Test with different color profiles

### watchOS
1. Test with VoiceOver enabled
2. Test with larger text sizes
3. Validate Digital Crown navigation
4. Test with reduced motion

### tvOS
1. Test with VoiceOver enabled
2. Test focus navigation with Siri Remote
3. Validate high contrast mode
4. Test with larger text sizes

## CI Integration

The accessibility linter supports all platforms but may produce different warnings based on platform capabilities:

```bash
# Run platform-specific tests
swift test --filter AccessibilityTests

# Generate CI script with platform awareness
let script = AccessibilityLinter.generateCIScript(
    config: .default
)
```

## Migration Guide

When migrating code between platforms:

1. **Always use conditional compilation** for platform-specific features
2. **Provide fallbacks** for limited-support features
3. **Test on target platform** before deployment
4. **Use platform-agnostic APIs** where possible

## Resources

- [Apple Accessibility Documentation](https://developer.apple.com/accessibility/)
- [SwiftUI Accessibility](https://developer.apple.com/documentation/swiftui/view-accessibility)
- [Localization Best Practices](https://developer.apple.com/documentation/xcode/localization)
- [RTL Language Support](https://developer.apple.com/design/human-interface-guidelines/right-to-left)