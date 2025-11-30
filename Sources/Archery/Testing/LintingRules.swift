import Foundation

// MARK: - MainActor Linting

public struct MainActorLinter {
    public struct Violation: Equatable {
        public let file: String
        public let line: Int
        public let column: Int
        public let message: String
        public let severity: Severity
        
        public enum Severity {
            case error
            case warning
            case info
        }
    }
    
    public init() {}
    
    public func lint(sourceCode: String, fileName: String) -> [Violation] {
        var violations: [Violation] = []
        let lines = sourceCode.components(separatedBy: .newlines)
        
        for (lineIndex, line) in lines.enumerated() {
            let lineNumber = lineIndex + 1
            
            // Check for UI updates not on MainActor
            if line.contains("@Published") && !isMainActorContext(lines: lines, at: lineIndex) {
                violations.append(Violation(
                    file: fileName,
                    line: lineNumber,
                    column: line.firstIndex(of: "@")?.utf16Offset(in: line) ?? 0,
                    message: "@Published properties should be marked with @MainActor",
                    severity: .warning
                ))
            }
            
            // Check for View body not on MainActor
            if line.contains("var body: some View") && !line.contains("@MainActor") {
                let contextMainActor = isMainActorContext(lines: lines, at: lineIndex)
                if !contextMainActor {
                    violations.append(Violation(
                        file: fileName,
                        line: lineNumber,
                        column: 0,
                        message: "View body should be computed on MainActor",
                        severity: .error
                    ))
                }
            }
            
            // Check for async UI updates
            if line.contains("Task {") && containsUIUpdate(lines: lines, startingAt: lineIndex) {
                if !line.contains("@MainActor") && !line.contains("MainActor.run") {
                    violations.append(Violation(
                        file: fileName,
                        line: lineNumber,
                        column: line.firstIndex(of: "T")?.utf16Offset(in: line) ?? 0,
                        message: "Task containing UI updates should use @MainActor",
                        severity: .warning
                    ))
                }
            }
        }
        
        return violations
    }
    
    private func isMainActorContext(lines: [String], at index: Int) -> Bool {
        // Look backwards for class/struct declaration
        for i in (0..<index).reversed() {
            let line = lines[i]
            if line.contains("@MainActor") {
                return true
            }
            if line.contains("class ") || line.contains("struct ") || line.contains("actor ") {
                return line.contains("@MainActor")
            }
        }
        return false
    }
    
    private func containsUIUpdate(lines: [String], startingAt index: Int) -> Bool {
        let uiKeywords = ["self.", "@Published", ".sink", ".assign", "withAnimation", ".onReceive"]
        var braceCount = 0
        
        for i in index..<min(index + 20, lines.count) {
            let line = lines[i]
            braceCount += line.filter { $0 == "{" }.count
            braceCount -= line.filter { $0 == "}" }.count
            
            if braceCount == 0 && i > index {
                break
            }
            
            for keyword in uiKeywords {
                if line.contains(keyword) {
                    return true
                }
            }
        }
        
        return false
    }
}

// MARK: - Accessibility Linting

public struct AccessibilityLinter {
    public struct Violation: Equatable {
        public let file: String
        public let line: Int
        public let message: String
        public let fixIt: String?
    }
    
    public init() {}
    
    public func lint(sourceCode: String, fileName: String) -> [Violation] {
        var violations: [Violation] = []
        let lines = sourceCode.components(separatedBy: .newlines)
        
        for (lineIndex, line) in lines.enumerated() {
            let lineNumber = lineIndex + 1
            
            // Check for images without accessibility labels
            if line.contains("Image(") && !hasAccessibilityLabel(lines: lines, at: lineIndex) {
                violations.append(Violation(
                    file: fileName,
                    line: lineNumber,
                    message: "Image is missing accessibility label",
                    fixIt: ".accessibilityLabel(\"Description\")"
                ))
            }
            
            // Check for buttons without labels
            if line.contains("Button(action:") && !line.contains("label:") {
                if !hasAccessibilityLabel(lines: lines, at: lineIndex) {
                    violations.append(Violation(
                        file: fileName,
                        line: lineNumber,
                        message: "Button is missing accessibility label",
                        fixIt: ".accessibilityLabel(\"Action description\")"
                    ))
                }
            }
            
            // Check for custom controls
            if line.contains(".onTapGesture") && !hasAccessibilityTraits(lines: lines, at: lineIndex) {
                violations.append(Violation(
                    file: fileName,
                    line: lineNumber,
                    message: "Tappable element should have accessibility traits",
                    fixIt: ".accessibilityAddTraits(.isButton)"
                ))
            }
            
            // Check for form elements
            if (line.contains("TextField") || line.contains("TextEditor")) {
                if !hasAccessibilityHint(lines: lines, at: lineIndex) {
                    violations.append(Violation(
                        file: fileName,
                        line: lineNumber,
                        message: "Text input should have accessibility hint",
                        fixIt: ".accessibilityHint(\"Enter your text here\")"
                    ))
                }
            }
            
            // Check for decorative images
            if line.contains(".decorative") || line.contains("decorativeImage") {
                if !line.contains(".accessibilityHidden(true)") {
                    violations.append(Violation(
                        file: fileName,
                        line: lineNumber,
                        message: "Decorative images should be hidden from accessibility",
                        fixIt: ".accessibilityHidden(true)"
                    ))
                }
            }
        }
        
        return violations
    }
    
    private func hasAccessibilityLabel(lines: [String], at index: Int) -> Bool {
        return checkForModifier(lines: lines, at: index, modifier: ".accessibilityLabel")
    }
    
    private func hasAccessibilityTraits(lines: [String], at index: Int) -> Bool {
        return checkForModifier(lines: lines, at: index, modifier: ".accessibilityAddTraits")
    }
    
    private func hasAccessibilityHint(lines: [String], at index: Int) -> Bool {
        return checkForModifier(lines: lines, at: index, modifier: ".accessibilityHint")
    }
    
    private func checkForModifier(lines: [String], at index: Int, modifier: String) -> Bool {
        // Check next few lines for the modifier
        for i in index..<min(index + 5, lines.count) {
            if lines[i].contains(modifier) {
                return true
            }
            // Stop if we hit another view declaration
            if lines[i].contains("View {") || lines[i].contains("body:") {
                break
            }
        }
        return false
    }
}

// MARK: - Lint Report

public struct LintReport {
    public let mainActorViolations: [MainActorLinter.Violation]
    public let accessibilityViolations: [AccessibilityLinter.Violation]
    public let timestamp: Date
    
    public init(
        mainActorViolations: [MainActorLinter.Violation],
        accessibilityViolations: [AccessibilityLinter.Violation]
    ) {
        self.mainActorViolations = mainActorViolations
        self.accessibilityViolations = accessibilityViolations
        self.timestamp = Date()
    }
    
    public var hasErrors: Bool {
        mainActorViolations.contains { $0.severity == .error } ||
        !accessibilityViolations.isEmpty
    }
    
    public var summary: String {
        """
        Lint Report - \(DateFormatter.localizedString(from: timestamp, dateStyle: .short, timeStyle: .medium))
        
        MainActor Issues: \(mainActorViolations.count)
        - Errors: \(mainActorViolations.filter { $0.severity == .error }.count)
        - Warnings: \(mainActorViolations.filter { $0.severity == .warning }.count)
        
        Accessibility Issues: \(accessibilityViolations.count)
        
        Status: \(hasErrors ? "❌ Failed" : "✅ Passed")
        """
    }
    
    public func writeMarkdown(to url: URL) throws {
        let markdown = generateMarkdown()
        try markdown.write(to: url, atomically: true, encoding: .utf8)
    }
    
    private func generateMarkdown() -> String {
        var output = "# Lint Report\n\n"
        output += summary + "\n\n"
        
        if !mainActorViolations.isEmpty {
            output += "## MainActor Violations\n\n"
            output += "| File | Line | Severity | Message |\n"
            output += "|------|------|----------|----------|\n"
            for violation in mainActorViolations {
                output += "| \(violation.file) | \(violation.line) | \(violation.severity) | \(violation.message) |\n"
            }
            output += "\n"
        }
        
        if !accessibilityViolations.isEmpty {
            output += "## Accessibility Violations\n\n"
            output += "| File | Line | Message | Fix |\n"
            output += "|------|------|---------|-----|\n"
            for violation in accessibilityViolations {
                output += "| \(violation.file) | \(violation.line) | \(violation.message) | \(violation.fixIt ?? "N/A") |\n"
            }
        }
        
        return output
    }
}

// MARK: - Lint Configuration

public struct LintConfiguration: Codable {
    public let enabledRules: Set<String>
    public let disabledRules: Set<String>
    public let customRules: [CustomRule]
    public let excludedPaths: [String]
    public let severityOverrides: [String: String]
    
    public struct CustomRule: Codable {
        public let id: String
        public let pattern: String
        public let message: String
        public let severity: String
    }
    
    public init(
        enabledRules: Set<String> = [],
        disabledRules: Set<String> = [],
        customRules: [CustomRule] = [],
        excludedPaths: [String] = [],
        severityOverrides: [String: String] = [:]
    ) {
        self.enabledRules = enabledRules
        self.disabledRules = disabledRules
        self.customRules = customRules
        self.excludedPaths = excludedPaths
        self.severityOverrides = severityOverrides
    }
    
    public static func load(from url: URL) throws -> LintConfiguration {
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(LintConfiguration.self, from: data)
    }
}