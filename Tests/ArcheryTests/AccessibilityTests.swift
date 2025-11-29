import XCTest
import SwiftUI
@testable import Archery

@MainActor
final class AccessibilityTests: XCTestCase {
    
    override func setUp() {
        super.setUp()
        Task { @MainActor in
            AccessibilityDiagnosticsEngine.shared.clear()
            AccessibilityDiagnosticsEngine.shared.enable()
        }
    }
    
    override func tearDown() {
        Task { @MainActor in
            AccessibilityDiagnosticsEngine.shared.clear()
        }
        super.tearDown()
    }
    
    func testAccessibilityDiagnosticCreation() {
        let diagnostic = AccessibilityDiagnostic(
            severity: .error,
            category: .missingLabel,
            message: "Missing accessibility label",
            suggestedFix: "Add .accessibilityLabel()"
        )
        
        XCTAssertEqual(diagnostic.severity, .error)
        XCTAssertEqual(diagnostic.category, .missingLabel)
        XCTAssertEqual(diagnostic.message, "Missing accessibility label")
        XCTAssertEqual(diagnostic.suggestedFix, "Add .accessibilityLabel()")
    }
    
    func testDiagnosticsEngine() {
        let engine = AccessibilityDiagnosticsEngine.shared
        engine.clear()
        
        let diagnostic1 = AccessibilityDiagnostic(
            severity: .error,
            category: .missingLabel,
            message: "Missing label"
        )
        
        let diagnostic2 = AccessibilityDiagnostic(
            severity: .warning,
            category: .insufficientContrast,
            message: "Low contrast"
        )
        
        engine.record(diagnostic1)
        engine.record(diagnostic2)
        
        let diagnostics = engine.getDiagnostics()
        XCTAssertGreaterThanOrEqual(diagnostics.count, 2)
        
        let report = engine.getDiagnosticsReport()
        XCTAssertTrue(report.contains("error") || report.contains("ERROR"))
        XCTAssertTrue(report.contains("warning") || report.contains("WARNING"))
    }
    
    func testContrastRatioCalculation() {
        let whiteOnBlack = ContrastRatio(
            foreground: .white,
            background: .black
        )
        
        XCTAssertTrue(whiteOnBlack.meetsAAStandard)
        XCTAssertTrue(whiteOnBlack.meetsAAAStandard)
        XCTAssertGreaterThan(whiteOnBlack.ratio, 20)
        
        let grayOnWhite = ContrastRatio(
            foreground: .gray,
            background: .white
        )
        
        XCTAssertTrue(grayOnWhite.ratio > 1)
    }
    
    func testAccessibilityMetadata() {
        let metadata = AccessibilityMetadata(
            label: "Submit Button",
            hint: "Tap to submit the form",
            value: "Ready",
            identifier: "submit_button",
            traits: [.button],
            isElement: true,
            sortPriority: 1.0
        )
        
        XCTAssertEqual(metadata.label, "Submit Button")
        XCTAssertEqual(metadata.hint, "Tap to submit the form")
        XCTAssertEqual(metadata.value, "Ready")
        XCTAssertEqual(metadata.identifier, "submit_button")
        XCTAssertTrue(metadata.traits.contains(.button))
        XCTAssertTrue(metadata.isElement)
        XCTAssertEqual(metadata.sortPriority, 1.0)
    }
    
    func testDynamicTypeValidator() {
        #if os(iOS) || os(tvOS)
        let diagnostic = DynamicTypeValidator.validateTextScaling(
            for: "This is a very long text that might overflow when using large Dynamic Type settings",
            containerWidth: 100,
            font: .body
        )
        
        XCTAssertNotNil(diagnostic)
        if let diagnostic = diagnostic {
            XCTAssertEqual(diagnostic.category, .dynamicTypeOverflow)
        }
        #else
        XCTAssertTrue(true)
        #endif
    }
    
    func testTapTargetValidator() {
        let smallTargetDiagnostic = TapTargetValidator.validate(
            size: CGSize(width: 20, height: 20)
        )
        
        XCTAssertNotNil(smallTargetDiagnostic)
        if let diagnostic = smallTargetDiagnostic {
            XCTAssertEqual(diagnostic.severity, .error)
            XCTAssertEqual(diagnostic.category, .tapTargetSize)
        }
        
        let validTargetDiagnostic = TapTargetValidator.validate(
            size: CGSize(width: 44, height: 44)
        )
        
        XCTAssertNil(validTargetDiagnostic)
    }
    
    func testAccessibilityLinterConfig() {
        let defaultConfig = AccessibilityLinter.Config.default
        XCTAssertTrue(defaultConfig.requireLabels)
        XCTAssertFalse(defaultConfig.requireHints)
        XCTAssertTrue(defaultConfig.requireIdentifiers)
        XCTAssertEqual(defaultConfig.minContrastRatio, 4.5)
        XCTAssertEqual(defaultConfig.minTapTargetSize, CGSize(width: 44, height: 44))
        
        let strictConfig = AccessibilityLinter.Config.strict
        XCTAssertTrue(strictConfig.requireLabels)
        XCTAssertTrue(strictConfig.requireHints)
        XCTAssertTrue(strictConfig.requireIdentifiers)
        XCTAssertEqual(strictConfig.minContrastRatio, 7.0)
        XCTAssertEqual(strictConfig.minTapTargetSize, CGSize(width: 48, height: 48))
    }
    
    func testAccessibilityLinter() {
        let engine = AccessibilityDiagnosticsEngine.shared
        
        engine.record(AccessibilityDiagnostic(
            severity: .error,
            category: .missingLabel,
            message: "Missing label"
        ))
        
        engine.record(AccessibilityDiagnostic(
            severity: .warning,
            category: .insufficientContrast,
            message: "Low contrast"
        ))
        
        let linter = AccessibilityLinter(config: .default)
        let result = linter.lint()
        
        XCTAssertFalse(result.passed)
        XCTAssertEqual(result.errorCount, 1)
        XCTAssertEqual(result.warningCount, 1)
        XCTAssertEqual(result.infoCount, 0)
        
        XCTAssertTrue(result.summary.contains("failed"))
        XCTAssertTrue(result.detailedReport.contains("Missing label"))
    }
    
    func testCIScriptGeneration() {
        let script = AccessibilityLinter.generateCIScript(config: .default)
        
        XCTAssertTrue(script.contains("#!/bin/bash"))
        XCTAssertTrue(script.contains("Running Accessibility Lint"))
        XCTAssertTrue(script.contains("swift test --enable-accessibility-audit"))
        XCTAssertTrue(script.contains("Checking Dynamic Type support"))
        XCTAssertTrue(script.contains("Checking RTL layout support"))
    }
    
    func testAccessibilityTraits() {
        let traits: Set<AccessibilityTrait> = [.button, .selected]
        XCTAssertTrue(traits.contains(.button))
        XCTAssertTrue(traits.contains(.selected))
        XCTAssertFalse(traits.contains(.link))
    }
}

final class AccessibilityViewModifierTests: XCTestCase {
    func testViewAccessibilityExtensions() {
        let metadata = AccessibilityMetadata(
            label: "Test Label",
            hint: "Test Hint",
            identifier: "test_id"
        )
        
        XCTAssertNotNil(metadata)
    }
}