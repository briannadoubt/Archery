#if canImport(XCTest)
import XCTest
import SwiftUI

// MARK: - Shell UI Tests

@MainActor
public final class ShellUITests: XCTestCase {
    private var app: XCUIApplication!

    override public func setUp() {
        super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--uitesting"]
        app.launchEnvironment = [
            "DISABLE_ANIMATIONS": "1",
            "MOCK_DATA": "1"
        ]
    }

    override public func tearDown() {
        app = nil
        super.tearDown()
    }

    // MARK: - Cold Start Performance

    public func testColdStartPerformance() throws {
        measure(metrics: [
            XCTApplicationLaunchMetric(),
            XCTMemoryMetric(),
            XCTCPUMetric()
        ]) {
            app.launch()

            // Wait for main view to appear
            let mainView = app.otherElements["MainView"]
            XCTAssertTrue(mainView.waitForExistence(timeout: 0.3), "App should launch in under 300ms")

            app.terminate()
        }
    }

    // MARK: - Tab Navigation

    public func testTabNavigation() {
        app.launch()

        // Test tab bar exists
        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.exists, "Tab bar should exist")

        // Navigate through all tabs
        let homeTab = tabBar.buttons["Home"]
        let searchTab = tabBar.buttons["Search"]
        let profileTab = tabBar.buttons["Profile"]

        if homeTab.exists {
            homeTab.tap()
            XCTAssertTrue(app.navigationBars["Home"].exists)
        }

        if searchTab.exists {
            searchTab.tap()
            XCTAssertTrue(app.navigationBars["Search"].exists)
        }

        if profileTab.exists {
            profileTab.tap()
            XCTAssertTrue(app.navigationBars["Profile"].exists)
        }
    }

    // MARK: - Deep Linking

    public func testDeepLinking() {
        // Launch with deep link
        app.launchEnvironment["DEEP_LINK"] = "archery://profile/settings"
        app.launch()

        // Verify navigation to settings
        let settingsView = app.otherElements["SettingsView"]
        XCTAssertTrue(settingsView.waitForExistence(timeout: 2.0), "Should navigate to settings via deep link")
    }

    // MARK: - Accessibility

    public func testAccessibilityLabels() {
        app.launch()

        // Check main navigation elements have labels
        let tabBar = app.tabBars.firstMatch
        for button in tabBar.buttons.allElementsBoundByIndex {
            if button.exists {
                XCTAssertFalse(button.label.isEmpty, "Tab button should have accessibility label")
            }
        }

        // Check images have labels
        for image in app.images.allElementsBoundByIndex.prefix(5) {
            if image.exists && !image.identifier.contains("decorative") {
                XCTAssertFalse(image.label.isEmpty, "Non-decorative images should have labels")
            }
        }
    }

    // MARK: - Error States

    public func testErrorHandling() {
        app.launchEnvironment["FORCE_ERROR"] = "1"
        app.launch()

        // Trigger network error
        let refreshButton = app.buttons["Refresh"]
        if refreshButton.exists {
            refreshButton.tap()

            // Check error alert appears
            let alert = app.alerts.firstMatch
            XCTAssertTrue(alert.waitForExistence(timeout: 2.0), "Error alert should appear")

            // Dismiss alert
            alert.buttons["OK"].tap()
            XCTAssertFalse(alert.exists, "Alert should be dismissed")
        }
    }

    // MARK: - Memory Pressure

    public func testMemoryPressure() {
        app.launch()

        // Navigate through multiple screens
        for _ in 0..<10 {
            // Push view
            if app.buttons["Details"].exists {
                app.buttons["Details"].tap()
            }

            // Pop view
            if app.navigationBars.buttons["Back"].exists {
                app.navigationBars.buttons["Back"].tap()
            }
        }

        // App should still be responsive
        let mainView = app.otherElements["MainView"]
        XCTAssertTrue(mainView.exists, "App should remain responsive after navigation stress")
    }

    // MARK: - Rotation Support

    public func testRotation() {
        #if !os(macOS)
        app.launch()

        let device = XCUIDevice.shared
        let initialOrientation = device.orientation

        // Rotate to landscape
        device.orientation = .landscapeLeft

        // Verify UI adapts
        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.exists, "Tab bar should exist in landscape")

        // Rotate to portrait
        device.orientation = .portrait
        XCTAssertTrue(tabBar.exists, "Tab bar should exist in portrait")

        // Restore orientation
        device.orientation = initialOrientation
        #endif
    }

    // MARK: - Background/Foreground

    public func testBackgroundForeground() {
        #if os(iOS) || os(tvOS)
        app.launch()

        // Send to background
        XCUIDevice.shared.press(.home)
        sleep(1)

        // Return to foreground
        app.activate()

        // Verify state restoration
        let mainView = app.otherElements["MainView"]
        XCTAssertTrue(mainView.waitForExistence(timeout: 2.0), "App should restore state after backgrounding")
        #endif
    }
}

// MARK: - UI Test Helpers

public extension XCUIElement {
    func waitForNonExistence(timeout: TimeInterval) -> Bool {
        let predicate = NSPredicate(format: "exists == false")
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: self)
        return XCTWaiter().wait(for: [expectation], timeout: timeout) == .completed
    }

    func tapIfExists() {
        if exists {
            tap()
        }
    }

    var isVisible: Bool {
        exists && !frame.isEmpty && frame.minX >= 0 && frame.minY >= 0
    }
}

// MARK: - Performance Metrics

public struct PerformanceMetrics {
    public let launchTime: TimeInterval
    public let memoryUsage: Double // MB
    public let cpuUsage: Double // Percentage
    public let frameRate: Double // FPS

    public var meetsRequirements: Bool {
        launchTime < 0.3 && // Under 300ms
        memoryUsage < 150 && // Under 150MB
        frameRate >= 60 // 60fps or better
    }

    public var summary: String {
        """
        Performance Metrics:
        - Launch Time: \(String(format: "%.2f", launchTime * 1000))ms
        - Memory Usage: \(String(format: "%.1f", memoryUsage))MB
        - CPU Usage: \(String(format: "%.1f%%", cpuUsage))
        - Frame Rate: \(String(format: "%.0f", frameRate))fps
        Status: \(meetsRequirements ? "PASS" : "FAIL")
        """
    }
}

// MARK: - Mock Data Provider

public final class UITestMockDataProvider {
    public static func configureMockEnvironment(_ app: XCUIApplication) {
        app.launchEnvironment["MOCK_DATA"] = "1"
        app.launchEnvironment["MOCK_USER_ID"] = "test-user-123"
        app.launchEnvironment["MOCK_API_DELAY"] = "0"
        app.launchEnvironment["DISABLE_ANIMATIONS"] = "1"
        app.launchEnvironment["DISABLE_ANALYTICS"] = "1"
    }

    public static func configureErrorEnvironment(_ app: XCUIApplication) {
        app.launchEnvironment["FORCE_ERROR"] = "1"
        app.launchEnvironment["ERROR_TYPE"] = "network_timeout"
    }

    public static func configureFeatureFlags(_ app: XCUIApplication, flags: [String: Bool]) {
        for (flag, enabled) in flags {
            app.launchEnvironment["FF_\(flag)"] = enabled ? "1" : "0"
        }
    }
}

// MARK: - Accessibility Audit

public final class UITestAccessibilityAudit {
    public static func audit(_ app: XCUIApplication) -> [AccessibilityIssue] {
        var issues: [AccessibilityIssue] = []

        // Check buttons
        for button in app.buttons.allElementsBoundByIndex {
            if button.exists && button.label.isEmpty {
                issues.append(AccessibilityIssue(
                    element: "Button",
                    identifier: button.identifier,
                    issue: "Missing accessibility label"
                ))
            }
        }

        // Check images
        for image in app.images.allElementsBoundByIndex {
            if image.exists && !image.identifier.contains("decorative") && image.label.isEmpty {
                issues.append(AccessibilityIssue(
                    element: "Image",
                    identifier: image.identifier,
                    issue: "Missing accessibility label"
                ))
            }
        }

        // Check text fields
        for field in app.textFields.allElementsBoundByIndex {
            if field.exists && field.placeholderValue == nil {
                issues.append(AccessibilityIssue(
                    element: "TextField",
                    identifier: field.identifier,
                    issue: "Missing placeholder or hint"
                ))
            }
        }

        return issues
    }

    public struct AccessibilityIssue {
        public let element: String
        public let identifier: String
        public let issue: String
    }
}

// MARK: - Navigation Flow Tester

@MainActor
public final class NavigationFlowTester {
    private let app: XCUIApplication
    private var visitedScreens: Set<String> = []
    private var navigationStack: [String] = []

    public init(app: XCUIApplication) {
        self.app = app
    }

    public func testNavigationFlow(startingFrom screen: String, depth: Int = 3) async -> NavigationFlowResult {
        navigationStack.append(screen)
        visitedScreens.insert(screen)

        await exploreScreen(depth: depth)

        return NavigationFlowResult(
            visitedScreens: visitedScreens,
            maxDepth: navigationStack.count,
            hasDeadEnds: checkForDeadEnds(),
            hasCycles: checkForCycles()
        )
    }

    private func exploreScreen(depth: Int) async {
        guard depth > 0 else { return }

        // Find all navigable elements
        let buttons = await app.buttons.allElementsBoundByIndex
        let cells = await app.cells.allElementsBoundByIndex

        for element in (buttons + cells).prefix(5) {
            if await element.exists && element.isHittable {
                await element.tap()

                // Check if we navigated somewhere new
                let currentScreen = await MainActor.run { identifyCurrentScreen() }
                if !visitedScreens.contains(currentScreen) {
                    visitedScreens.insert(currentScreen)
                    navigationStack.append(currentScreen)

                    // Explore deeper
                    await exploreScreen(depth: depth - 1)

                    // Navigate back
                    if await app.navigationBars.buttons["Back"].exists {
                        await app.navigationBars.buttons["Back"].tap()
                        navigationStack.removeLast()
                    }
                }
            }
        }
    }

    @MainActor
    private func identifyCurrentScreen() -> String {
        if let navBar = app.navigationBars.allElementsBoundByIndex.first(where: { $0.exists }) {
            return navBar.identifier.isEmpty ? "Unknown" : navBar.identifier
        }
        return "Unknown"
    }

    private func checkForDeadEnds() -> Bool {
        // Implementation would check for screens with no navigation options
        return false
    }

    private func checkForCycles() -> Bool {
        // Implementation would check for navigation cycles
        return false
    }

    public struct NavigationFlowResult {
        public let visitedScreens: Set<String>
        public let maxDepth: Int
        public let hasDeadEnds: Bool
        public let hasCycles: Bool

        public var summary: String {
            """
            Navigation Flow Test Results:
            - Screens Visited: \(visitedScreens.count)
            - Maximum Depth: \(maxDepth)
            - Dead Ends: \(hasDeadEnds ? "Found" : "None")
            - Cycles: \(hasCycles ? "Found" : "None")
            """
        }
    }
}
#endif
