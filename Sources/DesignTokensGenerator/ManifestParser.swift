import Foundation

// MARK: - Manifest Parser

/// Parses design token JSON manifests into structured data.
struct ManifestParser {

    // MARK: - Manifest Types

    struct Manifest: Decodable {
        struct ColorValues: Decodable {
            let light: String
            let dark: String?
            let highContrast: String?
        }

        struct TypographyValues: Decodable {
            let size: Double
            let weight: String
            let lineHeight: Double?
            let design: String?
        }

        let colors: [String: ColorValues]
        let typography: [String: TypographyValues]
        let spacing: [String: Double]
    }

    // MARK: - Configuration

    struct Configuration: Decodable {
        let manifestPath: String?
        let enumName: String?
        let outputFileName: String?
        let accessLevel: String?

        static let `default` = Configuration(
            manifestPath: nil,
            enumName: nil,
            outputFileName: nil,
            accessLevel: nil
        )
    }

    // MARK: - Parsing

    static func parseManifest(at path: String) throws -> Manifest {
        let url = URL(fileURLWithPath: path)
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(Manifest.self, from: data)
    }

    static func parseConfiguration(at path: String) throws -> Configuration {
        let url = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: path) else {
            return .default
        }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(Configuration.self, from: data)
    }
}
