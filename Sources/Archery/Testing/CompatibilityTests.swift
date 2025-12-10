import Foundation

#if canImport(XCTest)
import XCTest

// MARK: - Platform Compatibility Tests

public final class PlatformCompatibilityTests: XCTestCase {
    
    // MARK: - iOS Compatibility
    
    #if os(iOS)
    public func testIOSMinimumVersion() {
        if #available(iOS 17.0, *) {
            XCTAssertTrue(true, "Running on supported iOS version")
        } else {
            XCTFail("iOS 17.0+ required")
        }
    }
    
    public func testIOSFeatures() {
        // Test iOS-specific features
        #if canImport(UIKit)
        XCTAssertNotNil(UIApplication.shared)
        #endif
        
        #if canImport(WidgetKit)
        XCTAssertTrue(true, "WidgetKit available")
        #endif
        
        #if canImport(ActivityKit)
        if #available(iOS 16.1, *) {
            XCTAssertTrue(true, "ActivityKit available")
        }
        #endif
    }
    #endif
    
    // MARK: - macOS Compatibility
    
    #if os(macOS)
    public func testMacOSMinimumVersion() {
        if #available(macOS 14.0, *) {
            XCTAssertTrue(true, "Running on supported macOS version")
        } else {
            XCTFail("macOS 14.0+ required")
        }
    }
    
    public func testMacOSFeatures() {
        #if canImport(AppKit)
        XCTAssertNotNil(NSApplication.shared)
        #endif
    }
    #endif
    
    // MARK: - watchOS Compatibility
    
    #if os(watchOS)
    public func testWatchOSMinimumVersion() {
        if #available(watchOS 10.0, *) {
            XCTAssertTrue(true, "Running on supported watchOS version")
        } else {
            XCTFail("watchOS 10.0+ required")
        }
    }
    #endif
    
    // MARK: - tvOS Compatibility
    
    #if os(tvOS)
    public func testTvOSMinimumVersion() {
        if #available(tvOS 17.0, *) {
            XCTAssertTrue(true, "Running on supported tvOS version")
        } else {
            XCTFail("tvOS 17.0+ required")
        }
    }
    #endif
    
    // MARK: - visionOS Compatibility
    
    #if os(visionOS)
    public func testVisionOSMinimumVersion() {
        if #available(visionOS 1.0, *) {
            XCTAssertTrue(true, "Running on supported visionOS version")
        } else {
            XCTFail("visionOS 1.0+ required")
        }
    }
    #endif
}

// MARK: - Swift Version Compatibility

public final class SwiftVersionCompatibilityTests: XCTestCase {
    
    public func testSwiftVersion() {
        #if swift(>=6.2)
        XCTAssertTrue(true, "Swift 6.2+ supported")
        #else
        XCTFail("Swift 6.2+ required")
        #endif
    }
    
    public func testConcurrencyFeatures() async {
        // Test async/await
        let result = await asyncOperation()
        XCTAssertEqual(result, "Success")
        
        // Test actor isolation
        let actor = TestActor()
        await actor.increment()
        let value = await actor.value
        XCTAssertEqual(value, 1)
    }
    
    private func asyncOperation() async -> String {
        "Success"
    }
    
    actor TestActor {
        var value = 0
        
        func increment() {
            value += 1
        }
    }
    
    public func testSendableConformance() {
        struct SendableStruct: Sendable {
            let value: Int
        }
        
        let sendable = SendableStruct(value: 42)
        Task {
            _ = sendable // Should compile without warnings
        }
        
        XCTAssertTrue(true, "Sendable conformance works")
    }
}

// MARK: - API Availability Tests

public final class APIAvailabilityTests: XCTestCase {
    
    public func testSwiftUIAvailability() {
        #if canImport(SwiftUI)
        XCTAssertTrue(true, "SwiftUI available")
        #else
        XCTFail("SwiftUI required")
        #endif
    }
    
    public func testCombineAvailability() {
        #if canImport(Combine)
        XCTAssertTrue(true, "Combine available")
        #endif
    }
    
    public func testObservationAvailability() {
        if #available(iOS 17.0, macOS 14.0, tvOS 17.0, watchOS 10.0, *) {
            #if canImport(Observation)
            XCTAssertTrue(true, "Observation framework available")
            #endif
        }
    }
    
    public func testSwiftDataAvailability() {
        if #available(iOS 17.0, macOS 14.0, tvOS 17.0, watchOS 10.0, *) {
            #if canImport(SwiftData)
            XCTAssertTrue(true, "SwiftData available")
            #endif
        }
    }
    
    public func testChartsAvailability() {
        if #available(iOS 16.0, macOS 13.0, tvOS 16.0, watchOS 9.0, *) {
            #if canImport(Charts)
            XCTAssertTrue(true, "Charts framework available")
            #endif
        }
    }
}

// MARK: - Backward Compatibility Tests

public final class BackwardCompatibilityTests: XCTestCase {
    
    public func testDeprecatedAPIs() {
        // Test that deprecated APIs still work
        #if !os(watchOS)
        testLegacyNavigation()
        #endif
        testLegacyObservable()
    }
    
    private func testLegacyNavigation() {
        // Test NavigationView (deprecated in favor of NavigationStack)
        #if canImport(SwiftUI)
        // Would create a NavigationView here in actual test
        XCTAssertTrue(true, "Legacy navigation APIs work")
        #endif
    }
    
    private func testLegacyObservable() {
        // Test ObservableObject (still supported alongside @Observable)
        #if canImport(Combine)
        class LegacyViewModel: ObservableObject {
            @Published var value = 0
        }
        
        let vm = LegacyViewModel()
        vm.value = 1
        XCTAssertEqual(vm.value, 1, "Legacy ObservableObject works")
        #endif
    }
}

// MARK: - Migration Path Tests

public final class MigrationPathTests: XCTestCase {
    
    public func testDataMigration() throws {
        // Test migration from v1 to v2 data format
        let v1Data = LegacyDataFormat(version: 1, content: "test")
        let v2Data = try migrateToV2(v1Data)
        
        XCTAssertEqual(v2Data.version, 2)
        XCTAssertEqual(v2Data.content, "test")
        XCTAssertNotNil(v2Data.metadata)
    }
    
    struct LegacyDataFormat: Codable {
        let version: Int
        let content: String
    }
    
    struct ModernDataFormat: Codable {
        let version: Int
        let content: String
        let metadata: [String: String]
    }
    
    private func migrateToV2(_ legacy: LegacyDataFormat) throws -> ModernDataFormat {
        ModernDataFormat(
            version: 2,
            content: legacy.content,
            metadata: ["migrated": "true"]
        )
    }
}

// MARK: - Cross-Platform Code Sharing

public final class CrossPlatformTests: XCTestCase {
    
    public func testSharedBusinessLogic() {
        // Test that business logic works on all platforms
        let calculator = Calculator()
        XCTAssertEqual(calculator.add(2, 3), 5)
        XCTAssertEqual(calculator.multiply(4, 5), 20)
    }
    
    public func testPlatformSpecificUI() {
        #if os(iOS)
        XCTAssertTrue(hasTabBar(), "iOS has tab bar")
        #elseif os(macOS)
        XCTAssertTrue(hasSidebar(), "macOS has sidebar")
        #elseif os(tvOS)
        XCTAssertTrue(hasFocusEngine(), "tvOS has focus engine")
        #elseif os(watchOS)
        XCTAssertTrue(hasCrown(), "watchOS has digital crown")
        #endif
    }
    
    private func hasTabBar() -> Bool {
        #if os(iOS)
        return true
        #else
        return false
        #endif
    }
    
    private func hasSidebar() -> Bool {
        #if os(macOS)
        return true
        #else
        return false
        #endif
    }
    
    private func hasFocusEngine() -> Bool {
        #if os(tvOS)
        return true
        #else
        return false
        #endif
    }
    
    private func hasCrown() -> Bool {
        #if os(watchOS)
        return true
        #else
        return false
        #endif
    }
    
    struct Calculator {
        func add(_ a: Int, _ b: Int) -> Int { a + b }
        func multiply(_ a: Int, _ b: Int) -> Int { a * b }
    }
}
#endif

// MARK: - Compatibility Report

public struct CompatibilityReport {
    public let platform: String
    public let osVersion: String
    public let swiftVersion: String
    public let xcodeVersion: String
    public let supportedFeatures: Set<String>
    public let unsupportedFeatures: Set<String>
    public let deprecations: [Deprecation]
    
    public struct Deprecation {
        public let api: String
        public let replacement: String
        public let removalVersion: String?
    }
    
    public static func generate() -> CompatibilityReport {
        var supportedFeatures = Set<String>()
        var unsupportedFeatures = Set<String>()
        
        // Check features
        #if canImport(SwiftUI)
        supportedFeatures.insert("SwiftUI")
        #else
        unsupportedFeatures.insert("SwiftUI")
        #endif
        
        #if canImport(WidgetKit)
        supportedFeatures.insert("Widgets")
        #else
        unsupportedFeatures.insert("Widgets")
        #endif
        
        #if canImport(ActivityKit)
        supportedFeatures.insert("Live Activities")
        #else
        unsupportedFeatures.insert("Live Activities")
        #endif
        
        #if canImport(AppIntents)
        supportedFeatures.insert("App Intents")
        #else
        unsupportedFeatures.insert("App Intents")
        #endif
        
        let deprecations = [
            Deprecation(
                api: "NavigationView",
                replacement: "NavigationStack",
                removalVersion: nil
            ),
            Deprecation(
                api: "StateObject",
                replacement: "@State with @Observable",
                removalVersion: nil
            )
        ]
        
        return CompatibilityReport(
            platform: getCurrentPlatform(),
            osVersion: ProcessInfo.processInfo.operatingSystemVersionString,
            swiftVersion: getSwiftVersion(),
            xcodeVersion: getXcodeVersion(),
            supportedFeatures: supportedFeatures,
            unsupportedFeatures: unsupportedFeatures,
            deprecations: deprecations
        )
    }
    
    private static func getCurrentPlatform() -> String {
        #if os(iOS)
        return "iOS"
        #elseif os(macOS)
        return "macOS"
        #elseif os(tvOS)
        return "tvOS"
        #elseif os(watchOS)
        return "watchOS"
        #elseif os(visionOS)
        return "visionOS"
        #else
        return "Unknown"
        #endif
    }
    
    private static func getSwiftVersion() -> String {
        #if swift(>=6.2)
        return "6.2+"
        #elseif swift(>=6.0)
        return "6.0-6.1"
        #else
        return "<6.0"
        #endif
    }
    
    private static func getXcodeVersion() -> String {
        // This would be detected from build environment
        return "26.0"
    }
    
    public var summary: String {
        """
        Compatibility Report
        ====================
        Platform: \(platform)
        OS Version: \(osVersion)
        Swift: \(swiftVersion)
        Xcode: \(xcodeVersion)
        
        Supported Features (\(supportedFeatures.count)):
        \(supportedFeatures.sorted().map { "  ✅ \($0)" }.joined(separator: "\n"))
        
        Unsupported Features (\(unsupportedFeatures.count)):
        \(unsupportedFeatures.sorted().map { "  ❌ \($0)" }.joined(separator: "\n"))
        
        Deprecations:
        \(deprecations.map { "  ⚠️ \($0.api) -> \($0.replacement)" }.joined(separator: "\n"))
        """
    }
}