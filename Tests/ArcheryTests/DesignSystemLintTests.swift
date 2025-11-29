import Foundation
import XCTest

final class DesignSystemLintTests: XCTestCase {
    func testClientUsesSemanticColors() throws {
        let projectRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // file
            .deletingLastPathComponent() // ArcheryTests
            .deletingLastPathComponent() // Tests
        let clientRoot = projectRoot.appendingPathComponent("Sources/ArcheryClient")

        let disallowedColors = "(black|blue|brown|cyan|gray|green|indigo|mint|orange|pink|purple|red|teal|yellow|primary|secondary)"
        let colorRegex = try NSRegularExpression(pattern: "Color\\.\\(?" + disallowedColors)
        let styleRegex = try NSRegularExpression(pattern: "\\.(foregroundColor|foregroundStyle)\\(\\." + disallowedColors)

        var violations: [String] = []

        for file in swiftFiles(at: clientRoot) {
            guard let contents = try? String(contentsOf: file, encoding: .utf8) else { continue }
            if colorRegex.firstMatch(in: contents, range: contents.nsRange) != nil {
                violations.append("\(file.path): direct Color.* usage")
            }
            if styleRegex.firstMatch(in: contents, range: contents.nsRange) != nil {
                violations.append("\(file.path): .foregroundColor/Style with system color")
            }
        }

        if !violations.isEmpty {
            XCTFail("Semantic color lint failed:\n- " + violations.joined(separator: "\n- "))
        }
    }
}

private extension String {
    var nsRange: NSRange { NSRange(location: 0, length: utf16.count) }
}

private func swiftFiles(at url: URL) -> [URL] {
    guard let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: nil) else { return [] }
    return enumerator.compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" }
}
