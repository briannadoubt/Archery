#!/usr/bin/swift
import Foundation

/// Syncs Sources/Archery/DesignTokens.json into the inline literal used by Sources/Archery/DesignTokens.swift.
/// This keeps macro-friendly inline fallback in lockstep with the canonical JSON.

let fileManager = FileManager.default
let repoRoot = URL(fileURLWithPath: fileManager.currentDirectoryPath)
let jsonPath = repoRoot.appendingPathComponent("Sources/Archery/DesignTokens.json")
let swiftPath = repoRoot.appendingPathComponent("Sources/Archery/DesignTokens.swift")

guard let json = try? String(contentsOf: jsonPath, encoding: .utf8) else {
    fputs("✖️ Could not read \(jsonPath.path)\n", stderr)
    exit(1)
}

let inlineLiteral = """
\"\"\"\n\(json)\n\"\"\"
"""

var swift = try String(contentsOf: swiftPath, encoding: .utf8)

let pattern = #"@DesignTokens\(manifest: (?s:.*)\)\npublic enum ArcheryDesignTokens"# + ""
let replacement = "@DesignTokens(manifest: \(inlineLiteral))\npublic enum ArcheryDesignTokens"

if let range = swift.range(of: pattern, options: .regularExpression) {
    swift.replaceSubrange(range, with: replacement)
    try swift.write(to: swiftPath, atomically: true, encoding: .utf8)
    print("✅ Synced inline manifest from JSON.")
} else {
    print("ℹ️ Pattern not found; no changes written.")
}
