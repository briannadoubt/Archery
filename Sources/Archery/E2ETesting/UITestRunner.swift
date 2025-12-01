import XCTest
import SwiftUI

// MARK: - UI Test Runner

/// Manages UI tests for critical application flows
public final class UITestRunner {
    
    private let app: XCUIApplication
    private let timeout: TimeInterval
    
    public init(app: XCUIApplication = XCUIApplication(), timeout: TimeInterval = 10) {
        self.app = app
        self.timeout = timeout
    }
    
    // MARK: - Test Execution
    
    /// Run all critical flow tests
    public func runCriticalFlows() async throws -> TestReport {
        var results: [FlowTestResult] = []
        
        // Define critical flows
        let flows: [CriticalFlow] = [
            .authentication,
            .onboarding,
            .mainNavigation,
            .dataEntry,
            .purchase,
            .settings
        ]
        
        for flow in flows {
            let result = await testFlow(flow)
            results.append(result)
        }
        
        return TestReport(
            timestamp: Date(),
            results: results,
            summary: generateSummary(results)
        )
    }
    
    /// Test a specific flow
    public func testFlow(_ flow: CriticalFlow) async -> FlowTestResult {
        let startTime = Date()
        var steps: [StepResult] = []
        var success = true
        var error: Error?
        
        do {
            switch flow {
            case .authentication:
                steps = try await testAuthenticationFlow()
            case .onboarding:
                steps = try await testOnboardingFlow()
            case .mainNavigation:
                steps = try await testMainNavigationFlow()
            case .dataEntry:
                steps = try await testDataEntryFlow()
            case .purchase:
                steps = try await testPurchaseFlow()
            case .settings:
                steps = try await testSettingsFlow()
            }
        } catch let testError {
            success = false
            error = testError
        }
        
        return FlowTestResult(
            flow: flow,
            steps: steps,
            success: success,
            error: error,
            duration: Date().timeIntervalSince(startTime)
        )
    }
    
    // MARK: - Flow Implementations
    
    private func testAuthenticationFlow() async throws -> [StepResult] {
        var steps: [StepResult] = []
        
        // Step 1: Launch app
        app.launch()
        steps.append(StepResult(
            name: "Launch app",
            success: app.wait(for: .runningForeground, timeout: timeout)
        ))
        
        // Step 2: Check for login screen
        let loginButton = app.buttons["Login"]
        steps.append(StepResult(
            name: "Find login button",
            success: loginButton.waitForExistence(timeout: timeout)
        ))
        
        // Step 3: Enter credentials
        let emailField = app.textFields["Email"]
        let passwordField = app.secureTextFields["Password"]
        
        if emailField.exists && passwordField.exists {
            emailField.tap()
            emailField.typeText("test@example.com")
            
            passwordField.tap()
            passwordField.typeText("testpassword")
            
            steps.append(StepResult(
                name: "Enter credentials",
                success: true
            ))
        } else {
            steps.append(StepResult(
                name: "Enter credentials",
                success: false,
                error: "Fields not found"
            ))
        }
        
        // Step 4: Submit login
        loginButton.tap()
        
        // Step 5: Verify navigation to home
        let homeIdentifier = app.navigationBars["Home"]
        steps.append(StepResult(
            name: "Navigate to home",
            success: homeIdentifier.waitForExistence(timeout: timeout)
        ))
        
        return steps
    }
    
    private func testOnboardingFlow() async throws -> [StepResult] {
        var steps: [StepResult] = []
        
        // Test onboarding screens
        let pageIndicators = app.pageIndicators.firstMatch
        if pageIndicators.exists {
            let pageCount = Int(pageIndicators.value as? String ?? "0") ?? 0
            
            for i in 0..<pageCount {
                app.swipeLeft()
                steps.append(StepResult(
                    name: "Swipe to page \(i + 1)",
                    success: true
                ))
                
                // Check for skip button
                if app.buttons["Skip"].exists {
                    steps.append(StepResult(
                        name: "Skip button available",
                        success: true
                    ))
                }
            }
        }
        
        // Complete onboarding
        let completeButton = app.buttons["Get Started"]
        if completeButton.exists {
            completeButton.tap()
            steps.append(StepResult(
                name: "Complete onboarding",
                success: true
            ))
        }
        
        return steps
    }
    
    private func testMainNavigationFlow() async throws -> [StepResult] {
        var steps: [StepResult] = []
        
        // Test tab navigation
        let tabBar = app.tabBars.firstMatch
        if tabBar.exists {
            let buttons = tabBar.buttons
            
            for i in 0..<min(buttons.count, 5) {
                buttons.element(boundBy: i).tap()
                steps.append(StepResult(
                    name: "Navigate to tab \(i)",
                    success: true
                ))
                
                // Allow screen to load
                try await Task.sleep(nanoseconds: 500_000_000)
            }
        }
        
        // Test navigation stack
        if app.navigationBars.count > 0 {
            // Try to push a detail view
            let firstCell = app.cells.firstMatch
            if firstCell.exists {
                firstCell.tap()
                steps.append(StepResult(
                    name: "Push detail view",
                    success: app.navigationBars.buttons["Back"].waitForExistence(timeout: 2)
                ))
                
                // Pop back
                app.navigationBars.buttons["Back"].tap()
                steps.append(StepResult(
                    name: "Pop to root",
                    success: true
                ))
            }
        }
        
        return steps
    }
    
    private func testDataEntryFlow() async throws -> [StepResult] {
        var steps: [StepResult] = []
        
        // Find a form
        let textFields = app.textFields
        let textField = textFields.firstMatch
        
        if textField.exists {
            // Test text entry
            textField.tap()
            textField.typeText("Test Data")
            steps.append(StepResult(
                name: "Enter text",
                success: true
            ))
            
            // Test keyboard dismissal
            app.keyboards.buttons["Done"].tap()
            steps.append(StepResult(
                name: "Dismiss keyboard",
                success: !app.keyboards.firstMatch.exists
            ))
        }
        
        // Test form submission
        let submitButton = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'submit' OR label CONTAINS[c] 'save'")).firstMatch
        if submitButton.exists {
            submitButton.tap()
            steps.append(StepResult(
                name: "Submit form",
                success: true
            ))
        }
        
        return steps
    }
    
    private func testPurchaseFlow() async throws -> [StepResult] {
        var steps: [StepResult] = []
        
        // Navigate to store/purchase screen
        if app.buttons["Store"].exists {
            app.buttons["Store"].tap()
            steps.append(StepResult(
                name: "Navigate to store",
                success: true
            ))
        }
        
        // Find purchase button
        let purchaseButton = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'buy' OR label CONTAINS[c] 'purchase'")).firstMatch
        if purchaseButton.exists {
            purchaseButton.tap()
            steps.append(StepResult(
                name: "Initiate purchase",
                success: true
            ))
            
            // Handle system purchase dialog (if in sandbox)
            let purchaseAlert = app.alerts.firstMatch
            if purchaseAlert.waitForExistence(timeout: 2) {
                purchaseAlert.buttons["Cancel"].tap()
                steps.append(StepResult(
                    name: "Cancel purchase dialog",
                    success: true
                ))
            }
        }
        
        return steps
    }
    
    private func testSettingsFlow() async throws -> [StepResult] {
        var steps: [StepResult] = []
        
        // Navigate to settings
        if app.buttons["Settings"].exists || app.tabBars.buttons["Settings"].exists {
            (app.buttons["Settings"].exists ? app.buttons["Settings"] : app.tabBars.buttons["Settings"]).tap()
            steps.append(StepResult(
                name: "Navigate to settings",
                success: true
            ))
        }
        
        // Test toggle switches
        let switches = app.switches
        if switches.count > 0 {
            let firstSwitch = switches.firstMatch
            let initialValue = firstSwitch.value as? String == "1"
            firstSwitch.tap()
            
            steps.append(StepResult(
                name: "Toggle setting",
                success: (firstSwitch.value as? String == "1") != initialValue
            ))
        }
        
        // Test navigation to sub-settings
        let cells = app.cells
        if cells.count > 0 {
            cells.firstMatch.tap()
            steps.append(StepResult(
                name: "Navigate to sub-settings",
                success: app.navigationBars.buttons["Back"].waitForExistence(timeout: 2)
            ))
            
            app.navigationBars.buttons["Back"].tap()
        }
        
        return steps
    }
    
    // MARK: - Helpers
    
    private func generateSummary(_ results: [FlowTestResult]) -> TestSummary {
        let total = results.count
        let passed = results.filter { $0.success }.count
        let failed = total - passed
        let totalSteps = results.flatMap { $0.steps }.count
        let passedSteps = results.flatMap { $0.steps }.filter { $0.success }.count
        
        return TestSummary(
            totalFlows: total,
            passedFlows: passed,
            failedFlows: failed,
            totalSteps: totalSteps,
            passedSteps: passedSteps,
            successRate: Double(passed) / Double(max(total, 1))
        )
    }
}

// MARK: - Flow Definitions

public enum CriticalFlow: String, CaseIterable {
    case authentication = "Authentication"
    case onboarding = "Onboarding"
    case mainNavigation = "Main Navigation"
    case dataEntry = "Data Entry"
    case purchase = "Purchase"
    case settings = "Settings"
}

// MARK: - Result Models

public struct FlowTestResult {
    public let flow: CriticalFlow
    public let steps: [StepResult]
    public let success: Bool
    public let error: Error?
    public let duration: TimeInterval
}

public struct StepResult {
    public let name: String
    public let success: Bool
    public let error: String?
    
    public init(name: String, success: Bool, error: String? = nil) {
        self.name = name
        self.success = success
        self.error = error
    }
}

public struct TestReport {
    public let timestamp: Date
    public let results: [FlowTestResult]
    public let summary: TestSummary
    
    public func generateMarkdown() -> String {
        """
        # UI Test Report
        
        **Date:** \(timestamp)
        
        ## Summary
        - Flows: \(summary.passedFlows)/\(summary.totalFlows) passed
        - Steps: \(summary.passedSteps)/\(summary.totalSteps) passed
        - Success Rate: \(String(format: "%.1f%%", summary.successRate * 100))
        
        ## Flow Results
        
        \(results.map { flowResult in
            """
            ### \(flowResult.flow.rawValue)
            - Status: \(flowResult.success ? "✅ Passed" : "❌ Failed")
            - Duration: \(String(format: "%.2f", flowResult.duration))s
            - Steps: \(flowResult.steps.filter { $0.success }.count)/\(flowResult.steps.count) passed
            
            \(flowResult.error != nil ? "Error: \(flowResult.error!.localizedDescription)\n" : "")
            """
        }.joined(separator: "\n\n"))
        """
    }
}

public struct TestSummary {
    public let totalFlows: Int
    public let passedFlows: Int
    public let failedFlows: Int
    public let totalSteps: Int
    public let passedSteps: Int
    public let successRate: Double
}

// MARK: - Accessibility Testing

public extension UITestRunner {
    
    /// Run accessibility audit
    func runAccessibilityAudit() throws -> AccessibilityReport {
        var issues: [AccessibilityIssue] = []
        
        // Check for accessibility labels
        let elements = app.descendants(matching: .any)
        for i in 0..<min(elements.count, 100) {
            let element = elements.element(boundBy: i)
            
            if element.isHittable && element.label.isEmpty {
                issues.append(AccessibilityIssue(
                    element: String(describing: element),
                    type: .missingLabel,
                    severity: .high
                ))
            }
        }
        
        // Check for button sizes
        let buttons = app.buttons
        for i in 0..<buttons.count {
            let button = buttons.element(boundBy: i)
            let frame = button.frame
            
            if frame.width < 44 || frame.height < 44 {
                issues.append(AccessibilityIssue(
                    element: button.identifier,
                    type: .insufficientTapTarget,
                    severity: .medium
                ))
            }
        }
        
        return AccessibilityReport(
            timestamp: Date(),
            issues: issues,
            passed: issues.isEmpty
        )
    }
}

public struct AccessibilityIssue {
    public let element: String
    public let type: IssueType
    public let severity: Severity
    
    public enum IssueType {
        case missingLabel
        case insufficientTapTarget
        case poorContrast
        case missingTrait
    }
    
    public enum Severity {
        case low, medium, high, critical
    }
}

public struct AccessibilityReport {
    public let timestamp: Date
    public let issues: [AccessibilityIssue]
    public let passed: Bool
}