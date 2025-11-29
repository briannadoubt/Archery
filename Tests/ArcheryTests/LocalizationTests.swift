import XCTest
import SwiftUI
@testable import Archery

final class LocalizationTests: XCTestCase {
    
    override func setUp() {
        super.setUp()
        LocalizationEngine.shared.setMode(.normal)
    }
    
    override func tearDown() {
        LocalizationEngine.shared.setMode(.normal)
        super.tearDown()
    }
    
    func testLocalizedString() {
        let localized = LocalizedString(
            key: "test.key",
            tableName: "Test",
            bundle: .main,
            comment: "Test comment"
        )
        
        XCTAssertEqual(localized.key, "test.key")
        XCTAssertEqual(localized.tableName, "Test")
        XCTAssertEqual(localized.bundle, .main)
        XCTAssertEqual(localized.comment, "Test comment")
        
        // Test with arguments
        let withArgs = LocalizedString(
            key: "greeting",
            arguments: ["World"]
        )
        XCTAssertEqual(withArgs.key, "greeting")
    }
    
    func testLocalizationModes() {
        XCTAssertEqual(LocalizationMode.normal.locale, Locale.current)
        XCTAssertEqual(LocalizationMode.pseudo.locale, Locale(identifier: "x-pseudo"))
        XCTAssertEqual(LocalizationMode.rtl.locale, Locale(identifier: "ar"))
        XCTAssertEqual(LocalizationMode.doubleLength.locale, Locale(identifier: "x-pseudo"))
        XCTAssertEqual(LocalizationMode.accented.locale, Locale(identifier: "x-pseudo"))
    }
    
    func testLocalizationEngineTransform() {
        let engine = LocalizationEngine.shared
        let testText = "Hello World"
        
        engine.setMode(.normal)
        XCTAssertEqual(engine.transform(testText), "Hello World")
        
        engine.setMode(.pseudo)
        let pseudoTransformed = engine.transform(testText)
        XCTAssertTrue(pseudoTransformed.hasPrefix("["))
        XCTAssertTrue(pseudoTransformed.hasSuffix("]"))
        XCTAssertTrue(pseudoTransformed.contains("ë"))
        
        engine.setMode(.rtl)
        let rtlTransformed = engine.transform(testText)
        XCTAssertTrue(rtlTransformed.contains("\u{202E}"))
        
        engine.setMode(.doubleLength)
        XCTAssertEqual(engine.transform(testText), "Hello World Hello World")
        
        engine.setMode(.accented)
        let accentedTransformed = engine.transform(testText)
        XCTAssertTrue(accentedTransformed.contains("é"))
    }
    
    func testPseudoLocalization() {
        let engine = LocalizationEngine.shared
        engine.setMode(.pseudo)
        
        let text = "The quick brown fox"
        let transformed = engine.transform(text)
        
        XCTAssertTrue(transformed.hasPrefix("["))
        XCTAssertTrue(transformed.hasSuffix("]"))
        XCTAssertTrue(transformed.contains("ü"))
        XCTAssertTrue(transformed.contains("ï"))
    }
    
    func testExtractedString() {
        let extracted = ExtractedString(
            key: "welcome.message",
            defaultValue: "Welcome to our app",
            comment: "Greeting shown on first launch",
            tableName: "Onboarding"
        )
        
        XCTAssertEqual(extracted.key, "welcome.message")
        XCTAssertEqual(extracted.defaultValue, "Welcome to our app")
        XCTAssertEqual(extracted.comment, "Greeting shown on first launch")
        XCTAssertEqual(extracted.tableName, "Onboarding")
    }
    
    func testStringExtraction() {
        let engine = LocalizationEngine.shared
        
        let string1 = ExtractedString(
            key: "button.submit",
            defaultValue: "Submit",
            comment: "Submit button label"
        )
        
        let string2 = ExtractedString(
            key: "button.cancel",
            defaultValue: "Cancel",
            comment: "Cancel button label"
        )
        
        engine.recordExtractedString(string1)
        engine.recordExtractedString(string2)
        
        let extracted = engine.getExtractedStrings()
        XCTAssertTrue(extracted.contains(string1))
        XCTAssertTrue(extracted.contains(string2))
    }
    
    func testMissingKeyTracking() {
        let engine = LocalizationEngine.shared
        
        engine.recordMissingKey("missing.key.1")
        engine.recordMissingKey("missing.key.2")
        engine.recordMissingKey("missing.key.1")
        
        let missing = engine.getMissingKeys()
        XCTAssertTrue(missing.contains("missing.key.1"))
        XCTAssertTrue(missing.contains("missing.key.2"))
    }
    
    func testStringsFileGeneration() {
        let engine = LocalizationEngine.shared
        
        let string1 = ExtractedString(
            key: "app.name",
            defaultValue: "My App",
            comment: "Application name",
            tableName: "Main"
        )
        
        let string2 = ExtractedString(
            key: "app.version",
            defaultValue: "Version 1.0",
            comment: "Version string",
            tableName: "Main"
        )
        
        engine.recordExtractedString(string1)
        engine.recordExtractedString(string2)
        
        let stringsFile = engine.generateStringsFile(tableName: "Main")
        
        XCTAssertTrue(stringsFile.contains("Generated strings file for Main"))
        XCTAssertTrue(stringsFile.contains("\"app.name\" = \"My App\""))
        XCTAssertTrue(stringsFile.contains("\"app.version\" = \"Version 1.0\""))
        XCTAssertTrue(stringsFile.contains("Application name"))
        XCTAssertTrue(stringsFile.contains("Version string"))
    }
    
    func testLocalizationValidator() {
        let engine = LocalizationEngine.shared
        
        engine.recordMissingKey("undefined.key")
        
        let longString = ExtractedString(
            key: "very.long",
            defaultValue: String(repeating: "a", count: 150),
            comment: ""
        )
        engine.recordExtractedString(longString)
        
        let noComment = ExtractedString(
            key: "no.comment",
            defaultValue: "Text",
            comment: ""
        )
        engine.recordExtractedString(noComment)
        
        let diagnostics = LocalizationValidator.validateStrings()
        
        XCTAssertTrue(diagnostics.contains { $0.type == .missingKey })
        XCTAssertTrue(diagnostics.contains { $0.type == .tooLong })
        XCTAssertTrue(diagnostics.contains { $0.type == .missingComment })
    }
    
    func testLocalizationDiagnostic() {
        let diagnostic = LocalizationDiagnostic(
            type: .missingKey,
            key: "test.key",
            message: "Key not found"
        )
        
        XCTAssertEqual(diagnostic.type, .missingKey)
        XCTAssertEqual(diagnostic.key, "test.key")
        XCTAssertEqual(diagnostic.message, "Key not found")
    }
    
    func testAllLocalizationModes() {
        let modes = LocalizationMode.allCases
        XCTAssertEqual(modes.count, 5)
        XCTAssertTrue(modes.contains(.normal))
        XCTAssertTrue(modes.contains(.pseudo))
        XCTAssertTrue(modes.contains(.rtl))
        XCTAssertTrue(modes.contains(.doubleLength))
        XCTAssertTrue(modes.contains(.accented))
    }
}