import Foundation
import SwiftUI

public struct AccessibilityDiagnostic: Sendable, Equatable {
    public enum Severity: String, Sendable {
        case error = "ERROR"
        case warning = "WARNING"
        case info = "INFO"
    }
    
    public enum Category: String, Sendable {
        case missingLabel = "missing_label"
        case missingHint = "missing_hint"
        case missingValue = "missing_value"
        case missingIdentifier = "missing_identifier"
        case insufficientContrast = "insufficient_contrast"
        case dynamicTypeOverflow = "dynamic_type_overflow"
        case tapTargetSize = "tap_target_size"
        case missingTraits = "missing_traits"
    }
    
    public let severity: Severity
    public let category: Category
    public let message: String
    public let file: String
    public let line: Int
    public let column: Int
    public let suggestedFix: String?
    
    public init(
        severity: Severity,
        category: Category,
        message: String,
        file: String = #file,
        line: Int = #line,
        column: Int = #column,
        suggestedFix: String? = nil
    ) {
        self.severity = severity
        self.category = category
        self.message = message
        self.file = file
        self.line = line
        self.column = column
        self.suggestedFix = suggestedFix
    }
}

@MainActor
public final class AccessibilityDiagnosticsEngine: @unchecked Sendable {
    public static let shared = AccessibilityDiagnosticsEngine()
    
    private var diagnostics: [AccessibilityDiagnostic] = []
    private var isEnabled: Bool = true
    
    private init() {}
    
    public func enable() {
        isEnabled = true
    }
    
    public func disable() {
        isEnabled = false
    }
    
    public func record(_ diagnostic: AccessibilityDiagnostic) {
        guard isEnabled else { return }
        diagnostics.append(diagnostic)
    }
    
    public func clear() {
        diagnostics.removeAll()
    }
    
    public func getDiagnostics() -> [AccessibilityDiagnostic] {
        return diagnostics
    }
    
    public func getDiagnosticsReport() -> String {
        let grouped = Dictionary(grouping: diagnostics, by: { $0.severity })
        var report = "Accessibility Diagnostics Report\n"
        report += "=================================\n\n"
        
        let errorCount = grouped[.error]?.count ?? 0
        let warningCount = grouped[.warning]?.count ?? 0
        let infoCount = grouped[.info]?.count ?? 0
        
        report += "Summary: \(errorCount) errors, \(warningCount) warnings, \(infoCount) info\n\n"
        
        for severity in [AccessibilityDiagnostic.Severity.error, .warning, .info] {
            if let items = grouped[severity], !items.isEmpty {
                report += "\(severity.rawValue)S:\n"
                for diagnostic in items {
                    report += "  [\(diagnostic.category.rawValue)] \(diagnostic.message)\n"
                    report += "    at \(diagnostic.file):\(diagnostic.line):\(diagnostic.column)\n"
                    if let fix = diagnostic.suggestedFix {
                        report += "    Fix: \(fix)\n"
                    }
                }
                report += "\n"
            }
        }
        
        return report
    }
    
    /// Reset the engine state - useful for testing
    public func reset() {
        clear()
        enable()
    }
}

public struct ContrastRatio: Sendable {
    public let ratio: Double
    public let foreground: Color
    public let background: Color
    
    public init(foreground: Color, background: Color) {
        self.foreground = foreground
        self.background = background
        self.ratio = ContrastRatio.calculate(foreground: foreground, background: background)
    }
    
    public var meetsAAStandard: Bool {
        ratio >= 4.5
    }
    
    public var meetsAAAStandard: Bool {
        ratio >= 7.0
    }
    
    public var meetsAALargeTextStandard: Bool {
        ratio >= 3.0
    }
    
    public var meetsAAALargeTextStandard: Bool {
        ratio >= 4.5
    }
    
    private static func calculate(foreground: Color, background: Color) -> Double {
        let fgLuminance = luminance(for: foreground)
        let bgLuminance = luminance(for: background)
        
        let lighter = max(fgLuminance, bgLuminance)
        let darker = min(fgLuminance, bgLuminance)
        
        return (lighter + 0.05) / (darker + 0.05)
    }
    
    private static func luminance(for color: Color) -> Double {
        #if canImport(UIKit)
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        
        UIColor(color).getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        
        let r = red <= 0.03928 ? red / 12.92 : pow((red + 0.055) / 1.055, 2.4)
        let g = green <= 0.03928 ? green / 12.92 : pow((green + 0.055) / 1.055, 2.4)
        let b = blue <= 0.03928 ? blue / 12.92 : pow((blue + 0.055) / 1.055, 2.4)
        
        return 0.2126 * r + 0.7152 * g + 0.0722 * b
        #elseif canImport(AppKit)
        // Convert to sRGB color space first to ensure getRed:green:blue:alpha: works
        // Some system colors (e.g., catalog colors) are in device-specific color spaces
        // and will crash if we try to extract RGB components without conversion
        let nsColor = NSColor(color).usingColorSpace(.sRGB) ?? NSColor(color)
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        
        nsColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        
        let r = red <= 0.03928 ? red / 12.92 : pow((red + 0.055) / 1.055, 2.4)
        let g = green <= 0.03928 ? green / 12.92 : pow((green + 0.055) / 1.055, 2.4)
        let b = blue <= 0.03928 ? blue / 12.92 : pow((blue + 0.055) / 1.055, 2.4)
        
        return 0.2126 * r + 0.7152 * g + 0.0722 * b
        #else
        return 1.0
        #endif
    }
}

public struct AccessibilityMetadata: Sendable {
    public let label: String?
    public let hint: String?
    public let value: String?
    public let identifier: String?
    public let traits: Set<AccessibilityTrait>
    public let isElement: Bool
    public let sortPriority: Double
    
    public init(
        label: String? = nil,
        hint: String? = nil,
        value: String? = nil,
        identifier: String? = nil,
        traits: Set<AccessibilityTrait> = [],
        isElement: Bool = true,
        sortPriority: Double = 0
    ) {
        self.label = label
        self.hint = hint
        self.value = value
        self.identifier = identifier
        self.traits = traits
        self.isElement = isElement
        self.sortPriority = sortPriority
    }
}

public enum AccessibilityTrait: String, Sendable {
    case button
    case link
    case header
    case searchField
    case image
    case selected
    case playsSound
    case keyboardKey
    case staticText
    case summaryElement
    case notEnabled
    case updatesFrequently
    case startsMediaSession
    case adjustable
    case allowsDirectInteraction
    case causesPageTurn
}

extension View {
    public func accessibilityMetadata(_ metadata: AccessibilityMetadata) -> some View {
        self.modifier(AccessibilityMetadataModifier(metadata: metadata))
    }
    
    public func validateAccessibility(
        requireLabel: Bool = true,
        requireIdentifier: Bool = false,
        minContrastRatio: Double? = nil
    ) -> some View {
        self.modifier(AccessibilityValidationModifier(
            requireLabel: requireLabel,
            requireIdentifier: requireIdentifier,
            minContrastRatio: minContrastRatio
        ))
    }
}

struct AccessibilityMetadataModifier: ViewModifier {
    let metadata: AccessibilityMetadata
    
    func body(content: Content) -> some View {
        content
            .accessibilityElement(children: metadata.isElement ? .combine : .ignore)
            .accessibilityLabel(metadata.label ?? "")
            .accessibilityHint(metadata.hint ?? "")
            .accessibilityValue(metadata.value ?? "")
            .accessibilityIdentifier(metadata.identifier ?? "")
            .accessibilitySortPriority(metadata.sortPriority)
    }
}

struct AccessibilityValidationModifier: ViewModifier {
    let requireLabel: Bool
    let requireIdentifier: Bool
    let minContrastRatio: Double?
    
    func body(content: Content) -> some View {
        content
            .onAppear {
                #if DEBUG
                performValidation()
                #endif
            }
    }
    
    private func performValidation() {
        let engine = AccessibilityDiagnosticsEngine.shared
        
        if requireLabel {
            engine.record(AccessibilityDiagnostic(
                severity: .warning,
                category: .missingLabel,
                message: "View missing accessibility label",
                suggestedFix: "Add .accessibilityLabel() modifier"
            ))
        }
        
        if requireIdentifier {
            engine.record(AccessibilityDiagnostic(
                severity: .info,
                category: .missingIdentifier,
                message: "View missing accessibility identifier",
                suggestedFix: "Add .accessibilityIdentifier() modifier for UI testing"
            ))
        }
    }
}

public struct DynamicTypeValidator {
    public static func validateTextScaling(
        for text: String,
        containerWidth: CGFloat,
        font: Font
    ) -> AccessibilityDiagnostic? {
        #if canImport(UIKit)
        let maxCategory = UIContentSizeCategory.accessibilityExtraExtraExtraLarge
        let metrics = UIFontMetrics.default
        let baseSize: CGFloat = 17
        let scaledSize = metrics.scaledValue(for: baseSize, compatibleWith: UITraitCollection(preferredContentSizeCategory: maxCategory))
        
        let estimatedWidth = CGFloat(text.count) * scaledSize * 0.6
        
        if estimatedWidth > containerWidth {
            return AccessibilityDiagnostic(
                severity: .warning,
                category: .dynamicTypeOverflow,
                message: "Text may overflow at largest Dynamic Type sizes",
                suggestedFix: "Consider using .lineLimit() or .minimumScaleFactor() modifiers"
            )
        }
        #endif
        
        return nil
    }
}

public struct TapTargetValidator {
    public static let minimumSize: CGSize = CGSize(width: 44, height: 44)
    
    public static func validate(size: CGSize) -> AccessibilityDiagnostic? {
        if size.width < minimumSize.width || size.height < minimumSize.height {
            return AccessibilityDiagnostic(
                severity: .error,
                category: .tapTargetSize,
                message: "Tap target size (\(size.width)x\(size.height)) is below minimum (\(minimumSize.width)x\(minimumSize.height))",
                suggestedFix: "Increase tap target to at least 44x44 points"
            )
        }
        return nil
    }
}