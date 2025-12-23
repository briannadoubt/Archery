import Foundation

// MARK: - Design Tokens Generator CLI
//
// Usage: design-tokens-generator --input <path> --output <path> [--enum-name <name>] [--access-level <level>]
//
// Arguments:
//   --input         Path to the design-tokens.json manifest file
//   --output        Path where the generated Swift file will be written
//   --enum-name     Name of the generated enum (default: DesignTokens)
//   --access-level  Access level for generated code: public, internal, or empty (default: public)

@main
struct DesignTokensGenerator {
    static func main() throws {
        let args = CommandLine.arguments

        guard let inputIndex = args.firstIndex(of: "--input"),
              inputIndex + 1 < args.count else {
            fputs("Error: --input argument is required\n", stderr)
            exit(1)
        }
        let inputPath = args[inputIndex + 1]

        guard let outputIndex = args.firstIndex(of: "--output"),
              outputIndex + 1 < args.count else {
            fputs("Error: --output argument is required\n", stderr)
            exit(1)
        }
        let outputPath = args[outputIndex + 1]

        var enumName = "DesignTokens"
        if let enumIndex = args.firstIndex(of: "--enum-name"),
           enumIndex + 1 < args.count {
            enumName = args[enumIndex + 1]
        }

        var accessLevel = "public"
        if let accessIndex = args.firstIndex(of: "--access-level"),
           accessIndex + 1 < args.count {
            accessLevel = args[accessIndex + 1]
        }

        // Parse the manifest
        let manifest: ManifestParser.Manifest
        do {
            manifest = try ManifestParser.parseManifest(at: inputPath)
        } catch {
            fputs("Error: Failed to parse manifest at \(inputPath): \(error.localizedDescription)\n", stderr)
            exit(1)
        }

        // Generate the Swift code
        let generatedCode = CodeGenerator.generate(
            manifest: manifest,
            enumName: enumName,
            accessLevel: accessLevel
        )

        // Ensure output directory exists
        let outputURL = URL(fileURLWithPath: outputPath)
        let outputDir = outputURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)

        // Write the output file
        do {
            try generatedCode.write(toFile: outputPath, atomically: true, encoding: .utf8)
        } catch {
            fputs("Error: Failed to write output to \(outputPath): \(error.localizedDescription)\n", stderr)
            exit(1)
        }

        print("design-tokens-generator: Generated \(enumName) from \(inputPath)")
    }
}
