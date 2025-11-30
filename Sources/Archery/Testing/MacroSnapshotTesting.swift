import Foundation

// MARK: - Macro Snapshot Testing

public struct MacroSnapshot {
    public let name: String
    public let input: String
    public let expected: String
    public let actual: String?
    public let file: String
    public let line: Int
    
    public init(
        name: String,
        input: String,
        expected: String,
        actual: String? = nil,
        file: String = #file,
        line: Int = #line
    ) {
        self.name = name
        self.input = input
        self.expected = expected
        self.actual = actual
        self.file = file
        self.line = line
    }
    
    public var passed: Bool {
        guard let actual = actual else { return false }
        return expected.trimmingCharacters(in: .whitespacesAndNewlines) ==
               actual.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

public final class MacroSnapshotRunner {
    private var snapshots: [MacroSnapshot] = []
    private let updateSnapshots: Bool
    private let snapshotDirectory: URL
    
    public init(
        updateSnapshots: Bool = ProcessInfo.processInfo.environment["UPDATE_SNAPSHOTS"] == "1",
        snapshotDirectory: URL? = nil
    ) {
        self.updateSnapshots = updateSnapshots
        self.snapshotDirectory = snapshotDirectory ?? URL(fileURLWithPath: #file)
            .deletingLastPathComponent()
            .appendingPathComponent("__Snapshots__")
    }
    
    public func assertMacroExpansion(
        macroName: String,
        input: String,
        expected: String? = nil,
        file: String = #file,
        line: Int = #line,
        testName: String = #function
    ) throws {
        let snapshotName = "\(macroName)_\(testName)"
        let snapshotFile = snapshotDirectory
            .appendingPathComponent("\(snapshotName).swift")
        
        // Load or create expected output
        let expectedOutput: String
        if let expected = expected {
            expectedOutput = expected
        } else if FileManager.default.fileExists(atPath: snapshotFile.path) {
            expectedOutput = try String(contentsOf: snapshotFile, encoding: .utf8)
        } else {
            expectedOutput = ""
        }
        
        // Note: Actual macro expansion should be done in test target with SwiftSyntax
        let actualOutput = "// Placeholder for macro expansion of \(macroName)\n\(input)"
        
        // Update snapshot if requested
        if updateSnapshots {
            try FileManager.default.createDirectory(
                at: snapshotDirectory,
                withIntermediateDirectories: true
            )
            try actualOutput.write(to: snapshotFile, atomically: true, encoding: .utf8)
        }
        
        // Record snapshot
        let snapshot = MacroSnapshot(
            name: snapshotName,
            input: input,
            expected: expectedOutput,
            actual: actualOutput,
            file: file,
            line: line
        )
        
        snapshots.append(snapshot)
        
        // Assert equality
        if !snapshot.passed && !updateSnapshots {
            throw MacroSnapshotError.snapshotMismatch(
                expected: expectedOutput,
                actual: actualOutput,
                file: file,
                line: line
            )
        }
    }
    
    public func generateReport() -> MacroSnapshotReport {
        MacroSnapshotReport(snapshots: snapshots)
    }
}

public struct MacroSnapshotReport {
    public let snapshots: [MacroSnapshot]
    
    public var passed: Int {
        snapshots.filter { $0.passed }.count
    }
    
    public var failed: Int {
        snapshots.filter { !$0.passed }.count
    }
    
    public var summary: String {
        """
        Macro Snapshot Test Results:
        ✅ Passed: \(passed)
        ❌ Failed: \(failed)
        📊 Total: \(snapshots.count)
        """
    }
    
    public func writeHTML(to url: URL) throws {
        let html = generateHTML()
        try html.write(to: url, atomically: true, encoding: .utf8)
    }
    
    private func generateHTML() -> String {
        """
        <!DOCTYPE html>
        <html>
        <head>
            <title>Macro Snapshot Report</title>
            <style>
                body { font-family: -apple-system, BlinkMacSystemFont, sans-serif; }
                .passed { background: #d4edda; }
                .failed { background: #f8d7da; }
                pre { background: #f5f5f5; padding: 10px; overflow: auto; }
                .diff { background: #fff3cd; }
            </style>
        </head>
        <body>
            <h1>Macro Snapshot Test Results</h1>
            \(summary.replacingOccurrences(of: "\n", with: "<br>"))
            <hr>
            \(snapshots.map { snapshot in
                """
                <div class="\(snapshot.passed ? "passed" : "failed")">
                    <h3>\(snapshot.name)</h3>
                    <h4>Input:</h4>
                    <pre>\(snapshot.input.htmlEscaped)</pre>
                    <h4>Expected:</h4>
                    <pre>\(snapshot.expected.htmlEscaped)</pre>
                    <h4>Actual:</h4>
                    <pre>\(snapshot.actual?.htmlEscaped ?? "N/A")</pre>
                </div>
                <hr>
                """
            }.joined(separator: "\n"))
        </body>
        </html>
        """
    }
}

public enum MacroSnapshotError: Error, LocalizedError {
    case snapshotMismatch(expected: String, actual: String, file: String, line: Int)
    case snapshotNotFound(name: String)
    
    public var errorDescription: String? {
        switch self {
        case .snapshotMismatch(let expected, let actual, let file, let line):
            return """
            Snapshot mismatch at \(file):\(line)
            Expected:
            \(expected)
            
            Actual:
            \(actual)
            """
        case .snapshotNotFound(let name):
            return "Snapshot not found: \(name)"
        }
    }
}

extension String {
    var htmlEscaped: String {
        self
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }
}