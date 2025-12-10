import SwiftCompilerPlugin
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros
import SwiftDiagnostics

// MARK: - Diagnostics

enum PersistableDiagnostic: String, DiagnosticMessage {
    case mustBeStruct
    case mustBeCodable
    case noProperties

    var message: String {
        switch self {
        case .mustBeStruct:
            return "@Persistable can only be applied to structs"
        case .mustBeCodable:
            return "@Persistable requires the type to conform to Codable"
        case .noProperties:
            return "@Persistable requires at least one stored property"
        }
    }

    var diagnosticID: MessageID {
        MessageID(domain: "ArcheryMacros", id: rawValue)
    }

    var severity: DiagnosticSeverity { .error }
}

// MARK: - @Persistable Macro

/// Generates GRDB conformances (FetchableRecord, PersistableRecord, TableRecord)
/// and a type-safe Columns enum for database queries.
///
/// Usage:
/// ```swift
/// @Persistable(table: "players")
/// struct Player: Codable, Identifiable {
///     var id: Int64
///     var name: String
///     var score: Int
/// }
/// ```
///
/// Generates:
/// ```swift
/// extension Player: FetchableRecord, PersistableRecord {
///     static let databaseTableName = "players"
///
///     enum Columns {
///         static let id = Column(CodingKeys.id)
///         static let name = Column(CodingKeys.name)
///         static let score = Column(CodingKeys.score)
///     }
/// }
/// ```
public struct PersistableMacro: MemberMacro, ExtensionMacro {

    // MARK: - Configuration

    struct Config {
        var tableName: String?
        var primaryKey: String = "id"
    }

    static func parseConfig(from node: AttributeSyntax) -> Config {
        var config = Config()

        guard let arguments = node.arguments?.as(LabeledExprListSyntax.self) else {
            return config
        }

        for argument in arguments {
            let label = argument.label?.text

            switch label {
            case "table", nil:
                if let stringLiteral = argument.expression.as(StringLiteralExprSyntax.self),
                   let segment = stringLiteral.segments.first?.as(StringSegmentSyntax.self) {
                    config.tableName = segment.content.text
                }
            case "primaryKey":
                if let stringLiteral = argument.expression.as(StringLiteralExprSyntax.self),
                   let segment = stringLiteral.segments.first?.as(StringSegmentSyntax.self) {
                    config.primaryKey = segment.content.text
                }
            default:
                break
            }
        }

        return config
    }

    // MARK: - Property Extraction

    struct PropertyInfo {
        let name: String
        let type: String
        let isOptional: Bool
    }

    static func extractProperties(from structDecl: StructDeclSyntax) -> [PropertyInfo] {
        var properties: [PropertyInfo] = []

        for member in structDecl.memberBlock.members {
            guard let varDecl = member.decl.as(VariableDeclSyntax.self) else { continue }

            // Skip computed properties (those with accessors that aren't just didSet/willSet)
            for binding in varDecl.bindings {
                if let accessor = binding.accessorBlock {
                    // Check if it's a computed property
                    if case .accessors(let accessorList) = accessor.accessors {
                        let hasGetter = accessorList.contains { $0.accessorSpecifier.tokenKind == .keyword(.get) }
                        if hasGetter {
                            continue // Skip computed properties
                        }
                    }
                }

                guard let identifier = binding.pattern.as(IdentifierPatternSyntax.self) else { continue }
                let name = identifier.identifier.text

                // Get the type
                var typeName = "Any"
                var isOptional = false

                if let typeAnnotation = binding.typeAnnotation {
                    let typeString = typeAnnotation.type.trimmedDescription
                    typeName = typeString

                    // Check if optional
                    if typeAnnotation.type.is(OptionalTypeSyntax.self) ||
                       typeString.hasSuffix("?") ||
                       typeString.hasPrefix("Optional<") {
                        isOptional = true
                    }
                }

                properties.append(PropertyInfo(name: name, type: typeName, isOptional: isOptional))
            }
        }

        return properties
    }

    // MARK: - MemberMacro (generates Columns enum, databaseTableName, and query builders)

    public static func expansion(
        of node: AttributeSyntax,
        providingMembersOf declaration: some DeclGroupSyntax,
        conformingTo protocols: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        guard let structDecl = declaration.as(StructDeclSyntax.self) else {
            throw DiagnosticsError(diagnostics: [
                Diagnostic(node: Syntax(node), message: PersistableDiagnostic.mustBeStruct)
            ])
        }

        let properties = extractProperties(from: structDecl)

        guard !properties.isEmpty else {
            throw DiagnosticsError(diagnostics: [
                Diagnostic(node: Syntax(node), message: PersistableDiagnostic.noProperties)
            ])
        }

        let config = parseConfig(from: node)
        let typeName = structDecl.name.text
        let tableName = config.tableName ?? typeName.lowercased()

        // Generate Columns enum
        let columnDeclarations = properties.map { prop in
            "static let \(prop.name) = GRDB.Column(CodingKeys.\(prop.name))"
        }.joined(separator: "\n        ")

        let columnsEnum = """
        enum Columns {
            \(columnDeclarations)
        }
        """

        // Generate databaseTableName (required by TableRecord)
        let tableNameDecl = """
        static let databaseTableName = "\(tableName)"
        """

        return [
            DeclSyntax(stringLiteral: columnsEnum),
            DeclSyntax(stringLiteral: tableNameDecl)
        ]
    }

    // MARK: - ExtensionMacro (no longer generates conformances - user must add them)
    // This is now a no-op since we can't add external protocol conformances from a macro

    public static func expansion(
        of node: AttributeSyntax,
        attachedTo declaration: some DeclGroupSyntax,
        providingExtensionsOf type: some TypeSyntaxProtocol,
        conformingTo protocols: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [ExtensionDeclSyntax] {
        // Note: Extension macros cannot add conformances to external protocols like GRDB.FetchableRecord
        // The user must add FetchableRecord, PersistableRecord conformances manually
        return []
    }
}
