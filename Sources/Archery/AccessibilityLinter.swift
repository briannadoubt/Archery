import Foundation
import SwiftUI

public struct AccessibilityLinter {
    public struct Config: Sendable {
        public let requireLabels: Bool
        public let requireHints: Bool
        public let requireIdentifiers: Bool
        public let minContrastRatio: Double
        public let minTapTargetSize: CGSize
        public let checkDynamicType: Bool
        public let checkRTLLayout: Bool
        public let failOnError: Bool
        public let failOnWarning: Bool
        
        public init(
            requireLabels: Bool = true,
            requireHints: Bool = false,
            requireIdentifiers: Bool = true,
            minContrastRatio: Double = 4.5,
            minTapTargetSize: CGSize = CGSize(width: 44, height: 44),
            checkDynamicType: Bool = true,
            checkRTLLayout: Bool = true,
            failOnError: Bool = true,
            failOnWarning: Bool = false
        ) {
            self.requireLabels = requireLabels
            self.requireHints = requireHints
            self.requireIdentifiers = requireIdentifiers
            self.minContrastRatio = minContrastRatio
            self.minTapTargetSize = minTapTargetSize
            self.checkDynamicType = checkDynamicType
            self.checkRTLLayout = checkRTLLayout
            self.failOnError = failOnError
            self.failOnWarning = failOnWarning
        }
        
        public static let `default` = Config()
        public static let strict = Config(
            requireLabels: true,
            requireHints: true,
            requireIdentifiers: true,
            minContrastRatio: 7.0,
            minTapTargetSize: CGSize(width: 48, height: 48),
            checkDynamicType: true,
            checkRTLLayout: true,
            failOnError: true,
            failOnWarning: true
        )
    }
    
    public struct LintResult: Sendable {
        public let passed: Bool
        public let diagnostics: [AccessibilityDiagnostic]
        public let errorCount: Int
        public let warningCount: Int
        public let infoCount: Int
        
        public var summary: String {
            if passed {
                return "✅ Accessibility lint passed with \(errorCount) errors, \(warningCount) warnings"
            } else {
                return "❌ Accessibility lint failed with \(errorCount) errors, \(warningCount) warnings"
            }
        }
        
        public var detailedReport: String {
            var report = summary + "\n\n"
            
            if !diagnostics.isEmpty {
                report += "Diagnostics:\n"
                for diagnostic in diagnostics {
                    report += "  [\(diagnostic.severity.rawValue)] \(diagnostic.message)\n"
                    report += "    at \(diagnostic.file):\(diagnostic.line)\n"
                    if let fix = diagnostic.suggestedFix {
                        report += "    Fix: \(fix)\n"
                    }
                }
            }
            
            return report
        }
    }
    
    private let config: Config
    
    public init(config: Config = .default) {
        self.config = config
    }
    
    @MainActor
    public func lint() -> LintResult {
        let engine = AccessibilityDiagnosticsEngine.shared
        let diagnostics = engine.getDiagnostics()
        
        let errors = diagnostics.filter { $0.severity == .error }
        let warnings = diagnostics.filter { $0.severity == .warning }
        let info = diagnostics.filter { $0.severity == .info }
        
        let passed = (errors.isEmpty || !config.failOnError) &&
                     (warnings.isEmpty || !config.failOnWarning)
        
        return LintResult(
            passed: passed,
            diagnostics: diagnostics,
            errorCount: errors.count,
            warningCount: warnings.count,
            infoCount: info.count
        )
    }
    
    public static func generateCIScript(config: Config = .default) -> String {
        var script = """
        #!/bin/bash
        # Accessibility Lint CI Script
        
        echo "Running Accessibility Lint..."
        
        # Run tests with accessibility checks enabled
        swift test --enable-accessibility-audit
        
        # Check exit code
        if [ $? -ne 0 ]; then
            echo "❌ Accessibility lint failed"
            exit 1
        fi
        
        echo "✅ Accessibility lint passed"
        """
        
        if config.checkDynamicType {
            script += """
            
            
            # Check Dynamic Type support
            echo "Checking Dynamic Type support..."
            xcrun simctl list devices | grep -q "iPhone"
            if [ $? -eq 0 ]; then
                # Run UI tests with different text sizes
                for size in "XS" "S" "M" "L" "XL" "XXL" "XXXL" "AX1" "AX2" "AX3" "AX4" "AX5"; do
                    echo "Testing with text size: $size"
                    defaults write com.apple.Accessibility UIPreferredContentSizeCategoryName UICTContentSizeCategory$size
                    xcodebuild test -scheme Archery -destination "platform=iOS Simulator,name=iPhone 15"
                done
            fi
            """
        }
        
        if config.checkRTLLayout {
            script += """
            
            
            # Check RTL layout
            echo "Checking RTL layout support..."
            # Generate RTL snapshots
            swift test --filter RTLSnapshot
            """
        }
        
        return script
    }
}

public struct AccessibilityAudit {
    @MainActor
    public static func audit<Content: View>(
        _ view: Content,
        config: AccessibilityLinter.Config = .default
    ) -> AccessibilityLinter.LintResult {
        let linter = AccessibilityLinter(config: config)
        
        _ = view
            .accessibilityElement(children: .contain)
            .onAppear {
                Task { @MainActor in
                    performAudit(config: config)
                }
            }
        
        return linter.lint()
    }
    
    @MainActor
    private static func performAudit(config: AccessibilityLinter.Config) {
        let engine = AccessibilityDiagnosticsEngine.shared
        
        if config.requireLabels {
            engine.record(AccessibilityDiagnostic(
                severity: .error,
                category: .missingLabel,
                message: "View requires accessibility label",
                suggestedFix: "Add .accessibilityLabel() modifier"
            ))
        }
        
        if config.requireIdentifiers {
            engine.record(AccessibilityDiagnostic(
                severity: .warning,
                category: .missingIdentifier,
                message: "View should have accessibility identifier for UI testing",
                suggestedFix: "Add .accessibilityIdentifier() modifier"
            ))
        }
    }
}

public protocol AccessibilityAuditable {
    func auditAccessibility() -> AccessibilityLinter.LintResult
}

extension View {
    public func auditAccessibility(
        config: AccessibilityLinter.Config = .default,
        reportFailures: Bool = true
    ) -> some View {
        self.onAppear {
            let linter = AccessibilityLinter(config: config)
            let result = linter.lint()
            
            if !result.passed && reportFailures {
                #if DEBUG
                print(result.detailedReport)
                #endif
            }
        }
    }
    
    public func accessibilityLint(_ config: AccessibilityLinter.Config = .default) -> some View {
        self.modifier(AccessibilityLintModifier(config: config))
    }
}

struct AccessibilityLintModifier: ViewModifier {
    let config: AccessibilityLinter.Config
    
    func body(content: Content) -> some View {
        content
            .onAppear {
                #if DEBUG
                performLint()
                #endif
            }
    }
    
    @MainActor
    private func performLint() {
        let linter = AccessibilityLinter(config: config)
        let result = linter.lint()
        
        if !result.passed {
            print("⚠️ Accessibility Issues Detected:")
            print(result.detailedReport)
        }
    }
}

#if DEBUG
public struct AccessibilityLintPreview<Content: View>: View {
    let content: Content
    let config: AccessibilityLinter.Config
    
    public init(
        config: AccessibilityLinter.Config = .default,
        @ViewBuilder content: () -> Content
    ) {
        self.config = config
        self.content = content()
    }
    
    public var body: some View {
        content
            .accessibilityLint(config)
            .overlay(alignment: .topTrailing) {
                AccessibilityStatusBadge()
            }
    }
}

struct AccessibilityStatusBadge: View {
    @State private var result: AccessibilityLinter.LintResult?
    
    var body: some View {
        if let result = result {
            HStack(spacing: 4) {
                Image(systemName: result.passed ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                Text("\(result.errorCount)E \(result.warningCount)W")
                    .font(.caption2)
            }
            .padding(4)
            .background(result.passed ? Color.green : Color.red)
            .foregroundColor(.white)
            .cornerRadius(4)
            .padding()
        }
    }
}
#endif