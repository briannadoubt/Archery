import Foundation
import SwiftCompilerPlugin
import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

enum DesignTokensDiagnostic: DiagnosticMessage {
    case mustBeNominal
    case missingManifest
    case manifestMustBeString
    case manifestNotFound(String)
    case manifestDecodeFailed(String, String)

    var message: String {
        switch self {
        case .mustBeNominal:
            return "@DesignTokens can only be applied to a struct or enum"
        case .missingManifest:
            return "@DesignTokens requires a manifest: \"path/to/tokens.json\" argument"
        case .manifestMustBeString:
            return "The manifest path must be a string literal"
        case .manifestNotFound(let path):
            return "Design token manifest not found at \(path)"
        case .manifestDecodeFailed(let path, let reason):
            return "Failed to decode design token manifest at \(path): \(reason)"
        }
    }

    var diagnosticID: MessageID { .init(domain: "ArcheryMacros.DesignTokens", id: "\(self)") }
    var severity: DiagnosticSeverity { .error }
}

public enum DesignTokensMacro: MemberMacro, ExtensionMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingMembersOf declaration: some DeclGroupSyntax,
        conformingTo _: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        let name: String
        let access: String
        if let enumDecl = declaration.as(EnumDeclSyntax.self) {
            name = enumDecl.name.text
            access = enumDecl.access
        } else if let structDecl = declaration.as(StructDeclSyntax.self) {
            name = structDecl.name.text
            access = structDecl.access
        } else {
            throw DiagnosticsError(diagnostics: [diagnostic(for: declaration, kind: .mustBeNominal)])
        }

        let manifestPath = try manifestPath(from: node, context: context, declaration: declaration)
        let manifest = try loadManifest(at: manifestPath, declaration: declaration)

        let colorEnum = makeEnum(
            accessModifier: access,
            name: "ColorToken",
            cases: manifest.colors.keys.sorted()
        )
        let typographyEnum = makeEnum(
            accessModifier: access,
            name: "TypographyToken",
            cases: manifest.typography.keys.sorted()
        )
        let spacingEnum = makeEnum(
            accessModifier: access,
            name: "SpacingToken",
            cases: manifest.spacing.keys.sorted()
        )

        let themeDecl = DeclSyntax(stringLiteral: makeThemeBuilder(name: name, access: access, manifest: manifest))
        let tokenName = DeclSyntax(stringLiteral: "\(access)static let name = \"\(name)\"")

        return [colorEnum, typographyEnum, spacingEnum, themeDecl, tokenName]
    }

    public static func expansion(
        of attribute: AttributeSyntax,
        attachedTo declaration: some DeclGroupSyntax,
        providingExtensionsOf type: some TypeSyntaxProtocol,
        conformingTo protocols: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [ExtensionDeclSyntax] {
        guard declaration.isStructOrEnum else {
            return []
        }
        let ext = DeclSyntax(stringLiteral: "extension \(type.trimmedDescription): DesignTokenSet {}")
        return [ext.as(ExtensionDeclSyntax.self)].compactMap { $0 }
    }
}

// MARK: - Helpers

private extension DesignTokensMacro {
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

    static func manifestPath(
        from node: AttributeSyntax,
        context: some MacroExpansionContext,
        declaration: some DeclGroupSyntax
    ) throws -> String {
        guard let args = node.arguments?.as(LabeledExprListSyntax.self) else {
            throw DiagnosticsError(diagnostics: [diagnostic(for: declaration, kind: .missingManifest)])
        }

        guard let manifestArg = args.first(where: { $0.label?.text == nil || $0.label?.text == "manifest" }) else {
            throw DiagnosticsError(diagnostics: [diagnostic(for: declaration, kind: .missingManifest)])
        }

        guard let literal = manifestArg.expression.as(StringLiteralExprSyntax.self) else {
            throw DiagnosticsError(diagnostics: [diagnostic(for: declaration, kind: .manifestMustBeString)])
        }

        let rawPath = literal.segments.compactMap { segment -> String? in
            segment.as(StringSegmentSyntax.self)?.content.text
        }.joined()
        if rawPath.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("{") {
            return rawPath
        }
        let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let packageRoot = findPackageRoot(startingAt: cwd)

        if let loc = context.location(of: node) {
            let fileDesc = loc.file.description.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            if !fileDesc.isEmpty {
                let source = URL(fileURLWithPath: fileDesc).standardized
                let sourceDir = source.deletingLastPathComponent()
                let sourceRelative = URL(fileURLWithPath: rawPath, relativeTo: sourceDir).standardized
                if FileManager.default.fileExists(atPath: sourceRelative.path) {
                    return sourceRelative.path
                }
            }
        }

        var probe = cwd
        repeat {
            let candidate = URL(fileURLWithPath: rawPath, relativeTo: probe).standardized
            if FileManager.default.fileExists(atPath: candidate.path) {
                return candidate.path
            }

            probe.deleteLastPathComponent()
        } while probe.pathComponents.count > 1

        let filename = URL(fileURLWithPath: rawPath).lastPathComponent
        var searchRoot = packageRoot ?? cwd
        repeat {
            if let discovered = findFile(named: filename, startingAt: searchRoot) {
                return discovered.path
            }
            searchRoot.deleteLastPathComponent()
        } while searchRoot.pathComponents.count > 1

        if let packageRoot, rawPath == filename {
            let candidate = packageRoot.appendingPathComponent("Sources/Archery/DesignTokens.json")
            if FileManager.default.fileExists(atPath: candidate.path) {
                return candidate.path
            }
        }

        throw DiagnosticsError(diagnostics: [diagnostic(for: declaration, kind: .manifestNotFound(rawPath))])
    }

    static func loadManifest(
        at path: String,
        declaration: some DeclGroupSyntax
    ) throws -> Manifest {
        let url = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: url.path) else {
            if let data = path.data(using: .utf8), let manifest = try? JSONDecoder().decode(Manifest.self, from: data) {
                return manifest
            }
            throw DiagnosticsError(diagnostics: [diagnostic(for: declaration, kind: .manifestNotFound(path))])
        }
        do {
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode(Manifest.self, from: data)
        } catch {
            throw DiagnosticsError(diagnostics: [diagnostic(for: declaration, kind: .manifestDecodeFailed(url.path, error.localizedDescription))])
        }
    }

    static func makeEnum(accessModifier: String, name: String, cases: [String]) -> DeclSyntax {
        let joined = cases.map { "    case \($0.safeIdentifier)" }.joined(separator: "\n")
        return DeclSyntax(stringLiteral: """
\(accessModifier)enum \(name): String, CaseIterable, Sendable {
\(joined)
}
""")
    }

    static func makeThemeBuilder(name: String, access: String, manifest: Manifest) -> String {
        let colorLines = manifest.colors.sorted(by: { $0.key < $1.key }).map { key, value in
            let dark = value.dark ?? value.light
            let high = value.highContrast ?? dark
            return "        \"\(key)\": ArcheryTheme.resolvedColor(variant: variant, light: \"\(value.light)\", dark: \"\(dark)\", highContrast: \"\(high)\")"
        }.joined(separator: ",\n")

        let colorHex = manifest.colors.sorted(by: { $0.key < $1.key }).map { key, value in
            let dark = value.dark ?? value.light
            let high = value.highContrast ?? dark
            return "        \"\(key)\": ArcheryTheme.resolvedHex(variant: variant, light: \"\(value.light)\", dark: \"\(dark)\", highContrast: \"\(high)\")"
        }.joined(separator: ",\n")

        let typographyLines: [String] = manifest.typography
            .sorted(by: { $0.key < $1.key })
            .map { key, value in
                let design = value.design.map { ".\($0)" } ?? ".default"
                let lineHeightValue = value.lineHeight.map { "\($0)" } ?? "nil"
                return "        \"\(key)\": TypographyStyle(size: \(value.size), weight: \(weight(for: value.weight)), lineHeight: \(lineHeightValue), design: \(design))"
            }

        let spacingLines: [String] = manifest.spacing
            .sorted(by: { $0.key < $1.key })
            .map { key, value in
                "        \"\(key)\": \(value)"
            }

        return """
\(access)static func theme(for variant: ThemeVariant) -> ArcheryTheme {
    let colors: [String: SwiftUI.Color] = [
\(colorLines)
    ]

    let colorHex: [String: String] = [
\(colorHex)
    ]

    let typography: [String: TypographyStyle] = [
\(typographyLines.joined(separator: ",\n"))
    ]

    let spacing: [String: CGFloat] = [
\(spacingLines.joined(separator: ",\n"))
    ]

    return ArcheryTheme(
        name: "\(name)",
        variant: variant,
        colors: colors,
        colorHex: colorHex,
        typography: typography,
        spacing: spacing
    )
}
"""
    }

    static func weight(for input: String) -> String {
        switch input.lowercased() {
        case "ultralight": return "SwiftUI.Font.Weight.ultraLight"
        case "thin": return "SwiftUI.Font.Weight.thin"
        case "light": return "SwiftUI.Font.Weight.light"
        case "regular": return "SwiftUI.Font.Weight.regular"
        case "medium": return "SwiftUI.Font.Weight.medium"
        case "semibold", "semi-bold": return "SwiftUI.Font.Weight.semibold"
        case "bold": return "SwiftUI.Font.Weight.bold"
        case "heavy": return "SwiftUI.Font.Weight.heavy"
        case "black": return "SwiftUI.Font.Weight.black"
        default: return "SwiftUI.Font.Weight.regular"
        }
    }

    static func diagnostic(for node: some SyntaxProtocol, kind: DesignTokensDiagnostic) -> Diagnostic {
        Diagnostic(node: Syntax(node), message: kind)
    }

    static func findFile(named filename: String, startingAt root: URL) -> URL? {
        guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil) else { return nil }
        for case let url as URL in enumerator where url.lastPathComponent == filename {
            return url
        }
        return nil
    }

    static func findPackageRoot(startingAt url: URL) -> URL? {
        var probe = url
        let fm = FileManager.default
        while probe.pathComponents.count > 1 {
            if fm.fileExists(atPath: probe.appendingPathComponent("Package.swift").path) {
                return probe
            }
            probe.deleteLastPathComponent()
        }
        return nil
    }
}

private extension DeclGroupSyntax {
    var access: String {
        if modifiers.contains(where: { $0.name.tokenKind == .keyword(.public) }) { return "public " }
        if modifiers.contains(where: { $0.name.tokenKind == .keyword(.fileprivate) }) { return "fileprivate " }
        if modifiers.contains(where: { $0.name.tokenKind == .keyword(.private) }) { return "private " }
        return ""
    }

    var isStructOrEnum: Bool { self is StructDeclSyntax || self is EnumDeclSyntax }
}

private extension String {
    var safeIdentifier: String {
        let cleaned = replacingOccurrences(of: "-", with: "_")
        if cleaned.first?.isNumber == true { return "_" + cleaned }
        return cleaned
    }
}
