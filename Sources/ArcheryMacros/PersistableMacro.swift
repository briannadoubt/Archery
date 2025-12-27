import SwiftCompilerPlugin
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros
import SwiftDiagnostics

// MARK: - Diagnostics

enum PersistableDiagnostic: String, DiagnosticMessage {
    case mustBeStruct
    case noProperties
    case missingNonisolated
    case missingSendable

    var message: String {
        switch self {
        case .mustBeStruct:
            return "@Persistable can only be applied to structs"
        case .noProperties:
            return "@Persistable requires at least one stored property"
        case .missingNonisolated:
            return "@Persistable requires 'nonisolated' modifier on the struct to avoid Swift 6 MainActor isolation conflicts with GRDB's Sendable requirements"
        case .missingSendable:
            return "@Persistable requires 'Sendable' conformance on the struct for thread-safe database operations"
        }
    }

    var diagnosticID: MessageID {
        MessageID(domain: "ArcheryMacros", id: rawValue)
    }

    var severity: DiagnosticSeverity { .error }
}

// MARK: - @Persistable Macro

/// Generates GRDB conformances, type-safe Columns enum, and optionally full App Intents integration.
///
/// ## Requirements
///
/// The struct MUST be declared with `nonisolated` and `Sendable` to avoid Swift 6 MainActor
/// isolation conflicts with GRDB's thread-safe database operations:
///
/// ```swift
/// @Persistable(table: "players")
/// nonisolated struct Player: Sendable {
///     var id: String
///     var name: String
///     var score: Int
/// }
/// ```
///
/// ## Generated Conformances
///
/// The macro generates these conformances via extension:
/// - `Codable` - For encoding/decoding
/// - `Identifiable` - For SwiftUI lists
/// - `Hashable` - For collections
/// - `FetchableRecord` - GRDB fetch support
/// - `PersistableRecord` - GRDB insert/update/delete support
/// - `AutoMigrating` - Automatic schema migrations
///
/// ## App Intents Integration
///
/// Add `displayName` to generate App Intents Entity and Intent types:
///
/// ```swift
/// @Persistable(table: "tasks", displayName: "Task")
/// nonisolated struct TaskItem: Sendable {
///     var id: String
///     var title: String
/// }
/// // Generates: TaskItemEntity, TaskItemEntityListIntent, TaskItemEntityDeleteIntent
/// ```
///
/// The file using `displayName` must `import AppIntents`.
public struct PersistableMacro: MemberMacro, ExtensionMacro {

    // MARK: - Configuration

    struct Config {
        var tableName: String?
        var primaryKey: String = "id"
        // App Intents configuration
        var displayName: String?
        var titleProperty: String = "title"
        var generateIntents: Bool = true
    }

    static func parseConfig(from node: AttributeSyntax, typeName: String) -> Config {
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
            case "displayName":
                if let stringLiteral = argument.expression.as(StringLiteralExprSyntax.self),
                   let segment = stringLiteral.segments.first?.as(StringSegmentSyntax.self) {
                    config.displayName = segment.content.text
                }
            case "titleProperty":
                if let stringLiteral = argument.expression.as(StringLiteralExprSyntax.self),
                   let segment = stringLiteral.segments.first?.as(StringSegmentSyntax.self) {
                    config.titleProperty = segment.content.text
                }
            case "intents":
                config.generateIntents = argument.expression.description.trimmingCharacters(in: .whitespaces) == "true"
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
        var hasDefault: Bool = false

        var displayName: String {
            // Convert camelCase to Title Case
            name.replacingOccurrences(
                of: "([a-z])([A-Z])",
                with: "$1 $2",
                options: .regularExpression
            ).capitalized
        }
    }

    // MARK: - Schema Property Info (with attribute detection)

    struct SchemaPropertyInfo {
        let name: String
        let type: String
        let isOptional: Bool
        var hasDefault: Bool = false

        // Schema attributes
        var isPrimaryKey: Bool = false
        var isIndexed: Bool = false
        var isUnique: Bool = false
        var uniqueGroup: String? = nil
        var foreignKeyType: String? = nil
        var isCreatedAt: Bool = false
        var isUpdatedAt: Bool = false
        var isTransient: Bool = false
        var defaultValue: String? = nil
        /// Explicit column type from @ColumnType attribute (e.g., "integer", "text")
        var columnTypeOverride: String? = nil

        /// Column name from CodingKeys (if specified)
        var codingKeyName: String? = nil

        /// Column name - uses CodingKey value if available, otherwise converts to snake_case
        var columnName: String {
            if let key = codingKeyName {
                return key
            }
            return name.replacingOccurrences(
                of: "([a-z])([A-Z])",
                with: "$1_$2",
                options: .regularExpression
            ).lowercased()
        }

        /// Map Swift type to GRDB column type
        var grdbColumnType: String {
            // Use explicit override if provided
            if let override = columnTypeOverride {
                return ".\(override)"
            }

            let baseType = type.replacingOccurrences(of: "?", with: "")
            switch baseType {
            case "String": return ".text"
            case "Int", "Int8", "Int16", "Int32", "Int64": return ".integer"
            case "UInt", "UInt8", "UInt16", "UInt32", "UInt64": return ".integer"
            case "Double", "Float", "CGFloat": return ".double"
            case "Bool": return ".integer"  // SQLite stores as 0/1
            case "Date": return ".datetime"
            case "Data": return ".blob"
            case "UUID": return ".text"
            case "URL": return ".text"
            default:
                // Likely an enum or custom type - store as text for RawRepresentable
                return ".text"
            }
        }
    }

    /// Extract CodingKeys enum mappings from the struct
    static func extractCodingKeys(from structDecl: StructDeclSyntax) -> [String: String] {
        var mappings: [String: String] = [:]

        for member in structDecl.memberBlock.members {
            guard let enumDecl = member.decl.as(EnumDeclSyntax.self),
                  enumDecl.name.text == "CodingKeys" else { continue }

            for enumMember in enumDecl.memberBlock.members {
                guard let caseDecl = enumMember.decl.as(EnumCaseDeclSyntax.self) else { continue }

                for element in caseDecl.elements {
                    let caseName = element.name.text
                    // Check for raw value assignment (e.g., case foo = "bar")
                    if let rawValue = element.rawValue,
                       let stringLiteral = rawValue.value.as(StringLiteralExprSyntax.self),
                       let segment = stringLiteral.segments.first?.as(StringSegmentSyntax.self) {
                        mappings[caseName] = segment.content.text
                    } else {
                        // No raw value, use case name as-is
                        mappings[caseName] = caseName
                    }
                }
            }
        }

        return mappings
    }

    /// Extract properties with schema attribute detection
    static func extractSchemaProperties(from structDecl: StructDeclSyntax) -> [SchemaPropertyInfo] {
        var properties: [SchemaPropertyInfo] = []

        // First extract CodingKeys mappings
        let codingKeys = extractCodingKeys(from: structDecl)

        for member in structDecl.memberBlock.members {
            guard let varDecl = member.decl.as(VariableDeclSyntax.self) else { continue }

            for binding in varDecl.bindings {
                // Skip computed properties
                if let accessor = binding.accessorBlock {
                    switch accessor.accessors {
                    case .getter:
                        continue
                    case .accessors(let accessorList):
                        let hasGetter = accessorList.contains { $0.accessorSpecifier.tokenKind == .keyword(.get) }
                        let hasDidSetOrWillSet = accessorList.contains {
                            $0.accessorSpecifier.tokenKind == .keyword(.didSet) ||
                            $0.accessorSpecifier.tokenKind == .keyword(.willSet)
                        }
                        if hasGetter && !hasDidSetOrWillSet {
                            continue
                        }
                    }
                }

                guard let identifier = binding.pattern.as(IdentifierPatternSyntax.self) else { continue }
                let name = identifier.identifier.text

                var typeName = "Any"
                var isOptional = false

                if let typeAnnotation = binding.typeAnnotation {
                    let typeString = typeAnnotation.type.trimmedDescription
                    typeName = typeString

                    if typeAnnotation.type.is(OptionalTypeSyntax.self) ||
                       typeString.hasSuffix("?") ||
                       typeString.hasPrefix("Optional<") {
                        isOptional = true
                    }
                }

                var propInfo = SchemaPropertyInfo(
                    name: name,
                    type: typeName,
                    isOptional: isOptional,
                    hasDefault: binding.initializer != nil,
                    codingKeyName: codingKeys[name]
                )

                // Detect schema attributes on the variable declaration
                for attr in varDecl.attributes {
                    guard let attrSyntax = attr.as(AttributeSyntax.self) else { continue }
                    let attrName = attrSyntax.attributeName.trimmedDescription

                    switch attrName {
                    case "PrimaryKey":
                        propInfo.isPrimaryKey = true
                    case "Indexed":
                        propInfo.isIndexed = true
                    case "Unique":
                        propInfo.isUnique = true
                        // Extract group name if provided
                        if let args = attrSyntax.arguments?.as(LabeledExprListSyntax.self),
                           let firstArg = args.first,
                           let stringLiteral = firstArg.expression.as(StringLiteralExprSyntax.self),
                           let segment = stringLiteral.segments.first?.as(StringSegmentSyntax.self) {
                            propInfo.uniqueGroup = segment.content.text
                        }
                    case "ForeignKey":
                        // Extract the referenced type
                        if let args = attrSyntax.arguments?.as(LabeledExprListSyntax.self),
                           let firstArg = args.first {
                            // The argument is Type.self, extract the type name
                            let expr = firstArg.expression.description.trimmingCharacters(in: .whitespaces)
                            if expr.hasSuffix(".self") {
                                propInfo.foreignKeyType = String(expr.dropLast(5))
                            }
                        }
                    case "CreatedAt":
                        propInfo.isCreatedAt = true
                    case "UpdatedAt":
                        propInfo.isUpdatedAt = true
                    case "NotPersisted":
                        propInfo.isTransient = true
                    case "Default":
                        // Extract the default value
                        if let args = attrSyntax.arguments?.as(LabeledExprListSyntax.self),
                           let firstArg = args.first {
                            propInfo.defaultValue = firstArg.expression.description.trimmingCharacters(in: .whitespaces)
                        }
                    case "ColumnType":
                        // Extract the column type (e.g., .integer, .text)
                        if let args = attrSyntax.arguments?.as(LabeledExprListSyntax.self),
                           let firstArg = args.first {
                            // Argument is a member access like .integer or .text
                            let expr = firstArg.expression.description.trimmingCharacters(in: .whitespaces)
                            if expr.hasPrefix(".") {
                                propInfo.columnTypeOverride = String(expr.dropFirst())
                            } else {
                                propInfo.columnTypeOverride = expr
                            }
                        }
                    default:
                        break
                    }
                }

                properties.append(propInfo)
            }
        }

        return properties
    }

    // MARK: - Migration Generation

    static func generateMigration(
        tableName: String,
        properties: [SchemaPropertyInfo],
        primaryKey: String
    ) -> String {
        // Filter out transient properties
        let persistedProperties = properties.filter { !$0.isTransient }

        // Build column definitions
        var columnDefs: [String] = []
        var indexDefs: [String] = []
        var uniqueGroups: [String: [String]] = [:]

        for prop in persistedProperties {
            let colName = prop.columnName
            let colType = prop.grdbColumnType

            if prop.isPrimaryKey || prop.name == primaryKey || prop.name == "id" {
                // Primary key
                columnDefs.append("            t.primaryKey(\"\(colName)\", \(colType))")
            } else if prop.foreignKeyType != nil {
                // Foreign key column - stored as regular column
                // Note: We don't generate .references() because we can't reliably
                // know the referenced table name at macro expansion time.
                // Use @ForeignKey for documentation and compile-time relationship tracking.
                var colDef = "            t.column(\"\(colName)\", \(colType))"
                if !prop.isOptional {
                    colDef += ".notNull()"
                }
                columnDefs.append(colDef)

                // Foreign keys are often queried - auto-index
                if prop.isIndexed {
                    indexDefs.append("            try db.create(index: \"\(tableName)_\(colName)_idx\", on: \"\(tableName)\", columns: [\"\(colName)\"])")
                }
            } else {
                // Regular column
                var colDef = "            t.column(\"\(colName)\", \(colType))"
                if !prop.isOptional {
                    colDef += ".notNull()"
                }
                if prop.isUnique && prop.uniqueGroup == nil {
                    colDef += ".unique()"
                }
                if let defaultVal = prop.defaultValue {
                    // Quote strings, pass numbers directly
                    if prop.grdbColumnType == ".text" && !defaultVal.hasPrefix("\"") {
                        colDef += ".defaults(to: \"\(defaultVal)\")"
                    } else {
                        colDef += ".defaults(to: \(defaultVal))"
                    }
                }
                columnDefs.append(colDef)

                // Track unique groups for composite unique constraints
                if let group = prop.uniqueGroup {
                    uniqueGroups[group, default: []].append(colName)
                }

                // Add index if marked
                if prop.isIndexed {
                    indexDefs.append("            try db.create(index: \"\(tableName)_\(colName)_idx\", on: \"\(tableName)\", columns: [\"\(colName)\"])")
                }
            }
        }

        // Build the migration
        var migrationBody = """
        static let createTableMigration = Migration(id: "create_\(tableName)") { db in
            try db.create(table: "\(tableName)") { t in
\(columnDefs.joined(separator: "\n"))
            }
"""

        // Add composite unique constraints
        for (group, columns) in uniqueGroups.sorted(by: { $0.key < $1.key }) {
            let colList = columns.map { "\"\($0)\"" }.joined(separator: ", ")
            migrationBody += "\n            try db.create(index: \"\(tableName)_\(group)_unique\", on: \"\(tableName)\", columns: [\(colList)], unique: true)"
        }

        // Add indexes
        if !indexDefs.isEmpty {
            migrationBody += "\n" + indexDefs.joined(separator: "\n")
        }

        migrationBody += "\n        }"

        return migrationBody
    }

    static func extractProperties(from structDecl: StructDeclSyntax) -> [PropertyInfo] {
        var properties: [PropertyInfo] = []

        // First try to get properties from initializer (more accurate for types with custom init)
        for member in structDecl.memberBlock.members {
            if let initDecl = member.decl.as(InitializerDeclSyntax.self) {
                for param in initDecl.signature.parameterClause.parameters {
                    let name = (param.secondName ?? param.firstName).text
                    let typeText = param.type.description.trimmingCharacters(in: .whitespaces)
                    let isOptional = param.type.is(OptionalTypeSyntax.self) ||
                                     param.type.is(ImplicitlyUnwrappedOptionalTypeSyntax.self) ||
                                     param.defaultValue != nil

                    // Skip id and createdAt - these are auto-generated
                    if name == "id" || name == "createdAt" {
                        continue
                    }

                    properties.append(PropertyInfo(
                        name: name,
                        type: typeText,
                        isOptional: isOptional,
                        hasDefault: param.defaultValue != nil
                    ))
                }
                break // Use first init found
            }
        }

        // Fallback to stored properties if no init found
        if properties.isEmpty {
            for member in structDecl.memberBlock.members {
                guard let varDecl = member.decl.as(VariableDeclSyntax.self) else { continue }

                for binding in varDecl.bindings {
                    if let accessor = binding.accessorBlock {
                        switch accessor.accessors {
                        case .getter:
                            continue
                        case .accessors(let accessorList):
                            let hasGetter = accessorList.contains { $0.accessorSpecifier.tokenKind == .keyword(.get) }
                            let hasDidSetOrWillSet = accessorList.contains {
                                $0.accessorSpecifier.tokenKind == .keyword(.didSet) ||
                                $0.accessorSpecifier.tokenKind == .keyword(.willSet)
                            }
                            if hasGetter && !hasDidSetOrWillSet {
                                continue
                            }
                            if hasDidSetOrWillSet && !hasGetter {
                                // Fall through
                            } else if hasGetter {
                                continue
                            }
                        }
                    }

                    guard let identifier = binding.pattern.as(IdentifierPatternSyntax.self) else { continue }
                    let name = identifier.identifier.text

                    // Skip id and createdAt for intent properties
                    if name == "id" || name == "createdAt" {
                        continue
                    }

                    var typeName = "Any"
                    var isOptional = false

                    if let typeAnnotation = binding.typeAnnotation {
                        let typeString = typeAnnotation.type.trimmedDescription
                        typeName = typeString

                        if typeAnnotation.type.is(OptionalTypeSyntax.self) ||
                           typeString.hasSuffix("?") ||
                           typeString.hasPrefix("Optional<") {
                            isOptional = true
                        }
                    }

                    properties.append(PropertyInfo(
                        name: name,
                        type: typeName,
                        isOptional: isOptional,
                        hasDefault: binding.initializer != nil
                    ))
                }
            }
        }

        return properties
    }

    /// Extract ALL properties including id (for Columns enum)
    static func extractAllProperties(from structDecl: StructDeclSyntax) -> [PropertyInfo] {
        var properties: [PropertyInfo] = []

        for member in structDecl.memberBlock.members {
            guard let varDecl = member.decl.as(VariableDeclSyntax.self) else { continue }

            for binding in varDecl.bindings {
                if let accessor = binding.accessorBlock {
                    switch accessor.accessors {
                    case .getter:
                        continue
                    case .accessors(let accessorList):
                        let hasGetter = accessorList.contains { $0.accessorSpecifier.tokenKind == .keyword(.get) }
                        let hasDidSetOrWillSet = accessorList.contains {
                            $0.accessorSpecifier.tokenKind == .keyword(.didSet) ||
                            $0.accessorSpecifier.tokenKind == .keyword(.willSet)
                        }
                        if hasGetter && !hasDidSetOrWillSet {
                            continue
                        }
                        if hasDidSetOrWillSet && !hasGetter {
                            // Fall through
                        } else if hasGetter {
                            continue
                        }
                    }
                }

                guard let identifier = binding.pattern.as(IdentifierPatternSyntax.self) else { continue }
                let name = identifier.identifier.text

                var typeName = "Any"
                var isOptional = false

                if let typeAnnotation = binding.typeAnnotation {
                    let typeString = typeAnnotation.type.trimmedDescription
                    typeName = typeString

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

    // MARK: - MemberMacro

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

        // Check for required nonisolated modifier
        let hasNonisolated = structDecl.modifiers.contains { modifier in
            modifier.name.tokenKind == .keyword(.nonisolated)
        }
        guard hasNonisolated else {
            throw DiagnosticsError(diagnostics: [
                Diagnostic(node: Syntax(structDecl.structKeyword), message: PersistableDiagnostic.missingNonisolated)
            ])
        }

        // Check for required Sendable conformance
        let existingConformances = getExistingConformances(structDecl)
        guard existingConformances.contains("Sendable") else {
            throw DiagnosticsError(diagnostics: [
                Diagnostic(node: Syntax(structDecl.name), message: PersistableDiagnostic.missingSendable)
            ])
        }

        // Extract properties with schema attributes
        let schemaProperties = extractSchemaProperties(from: structDecl)

        guard !schemaProperties.isEmpty else {
            throw DiagnosticsError(diagnostics: [
                Diagnostic(node: Syntax(node), message: PersistableDiagnostic.noProperties)
            ])
        }

        let typeName = structDecl.name.text
        let config = parseConfig(from: node, typeName: typeName)
        let tableName = config.tableName ?? typeName.lowercased()

        // Check if struct declares AppEntity conformance (reuse existingConformances from above)
        let hasAppEntityConformance = existingConformances.contains("AppEntity")
        let hasDisplayName = config.displayName != nil

        var members: [DeclSyntax] = []

        // Generate Columns enum (excluding @Transient properties)
        let persistedProperties = schemaProperties.filter { !$0.isTransient }
        let columnDeclarations = persistedProperties.map { prop in
            "static let \(prop.name) = Column(CodingKeys.\(prop.name))"
        }.joined(separator: "\n        ")

        let columnsEnum = """
        enum Columns {
            \(columnDeclarations)
        }
        """

        // Generate databaseTableName
        let tableNameDecl = """
        static let databaseTableName = "\(tableName)"
        """

        members.append(DeclSyntax(stringLiteral: columnsEnum))
        members.append(DeclSyntax(stringLiteral: tableNameDecl))

        // Generate createTableMigration
        let migrationDecl = generateMigration(
            tableName: tableName,
            properties: schemaProperties,
            primaryKey: config.primaryKey
        )
        members.append(DeclSyntax(stringLiteral: migrationDecl))

        // Generate AppEntity members INLINE when struct declares AppEntity + displayName provided
        // This avoids Swift 6 actor isolation conflicts between AppEntity (MainActor) and FetchableRecord (Sendable)
        if hasAppEntityConformance && hasDisplayName {
            let displayName = config.displayName!
            let titleProperty = config.titleProperty

            // Generate AppEntity required members inline
            let appEntityMembers = generateAppEntityMembersInline(
                typeName: typeName,
                displayName: displayName,
                titleProperty: titleProperty
            )
            members.append(DeclSyntax(stringLiteral: appEntityMembers))

            // Generate EntityQuery as nested type
            let entityQueryCode = generateEntityQueryCode(typeName: typeName)
            members.append(DeclSyntax(stringLiteral: entityQueryCode))

            // Note: Intent types are generated by the PeerMacro as top-level types
            // (e.g., TaskItemEntityListIntent, TaskItemEntityDeleteIntent)
        }

        return members
    }

    // MARK: - ExtensionMacro

    public static func expansion(
        of node: AttributeSyntax,
        attachedTo declaration: some DeclGroupSyntax,
        providingExtensionsOf type: some TypeSyntaxProtocol,
        conformingTo protocols: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [ExtensionDeclSyntax] {
        guard let structDecl = declaration.as(StructDeclSyntax.self) else {
            return []
        }

        let typeName = structDecl.name.text
        var extensions: [ExtensionDeclSyntax] = []

        // Check which conformances are already declared on the struct
        let existingConformances = getExistingConformances(structDecl)

        // Generate conformances via extension with nonisolated.
        // Even though the struct is nonisolated, Swift 6's default actor isolation
        // still applies MainActor to extension conformances unless explicitly nonisolated.
        var conformances: [String] = []

        // Core conformances - generate if not already declared
        if !existingConformances.contains("Codable") {
            conformances.append("nonisolated Codable")
        }
        if !existingConformances.contains("Identifiable") {
            conformances.append("nonisolated Identifiable")
        }
        if !existingConformances.contains("Hashable") {
            conformances.append("nonisolated Hashable")
        }
        if !existingConformances.contains("FetchableRecord") {
            conformances.append("nonisolated FetchableRecord")
        }
        if !existingConformances.contains("PersistableRecord") {
            conformances.append("nonisolated PersistableRecord")
        }

        // Generate all conformances in a single extension
        if !conformances.isEmpty {
            let conformanceList = conformances.joined(separator: ", ")
            let conformanceExtension = try ExtensionDeclSyntax(
                "extension \(raw: typeName): \(raw: conformanceList) {}"
            )
            extensions.append(conformanceExtension)
        }

        // Always generate AutoMigrating conformance for migration support
        let autoMigratingExtension = try ExtensionDeclSyntax(
            "extension \(raw: typeName): AutoMigrating {}"
        )
        extensions.append(autoMigratingExtension)

        // Generate HasTimestamps conformance if both @CreatedAt and @UpdatedAt are present
        let schemaProps = extractSchemaProperties(from: structDecl)
        let hasCreatedAt = schemaProps.contains { $0.isCreatedAt }
        let hasUpdatedAt = schemaProps.contains { $0.isUpdatedAt }

        if hasCreatedAt && hasUpdatedAt {
            let timestampsExtension = try ExtensionDeclSyntax(
                "extension \(raw: typeName): HasTimestamps {}"
            )
            extensions.append(timestampsExtension)
        } else if hasCreatedAt {
            let createdAtExtension = try ExtensionDeclSyntax(
                "extension \(raw: typeName): HasCreatedAt {}"
            )
            extensions.append(createdAtExtension)
        } else if hasUpdatedAt {
            let updatedAtExtension = try ExtensionDeclSyntax(
                "extension \(raw: typeName): HasUpdatedAt {}"
            )
            extensions.append(updatedAtExtension)
        }

        return extensions
    }
}

// MARK: - PeerMacro

extension PersistableMacro: PeerMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingPeersOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        guard let structDecl = declaration.as(StructDeclSyntax.self) else {
            return []
        }

        let typeName = structDecl.name.text
        let config = parseConfig(from: node, typeName: typeName)

        // Only generate Entity peer when displayName is provided
        guard let displayName = config.displayName else {
            return []
        }

        // Match the access level of the source type
        let accessLevel = getAccessLevel(from: structDecl)

        let titleProperty = config.titleProperty
        let entityTypeName = "\(typeName)Entity"
        let displayNamePlural = displayName + "s"

        // Generate the Entity struct that wraps the database type for App Intents
        var declarations: [DeclSyntax] = []

        let entityCode = generateEntityCode(
            typeName: typeName,
            entityTypeName: entityTypeName,
            displayName: displayName,
            titleProperty: titleProperty,
            accessLevel: accessLevel
        )
        declarations.append(DeclSyntax(stringLiteral: entityCode))

        // Generate intents if enabled (as separate peer declarations)
        if config.generateIntents {
            let listIntentCode = generateListIntentPeer(
                typeName: typeName,
                entityTypeName: entityTypeName,
                displayNamePlural: displayNamePlural,
                accessLevel: accessLevel
            )
            declarations.append(DeclSyntax(stringLiteral: listIntentCode))

            let deleteIntentCode = generateDeleteIntentPeer(
                typeName: typeName,
                entityTypeName: entityTypeName,
                displayName: displayName,
                accessLevel: accessLevel
            )
            declarations.append(DeclSyntax(stringLiteral: deleteIntentCode))
        }

        return declarations
    }

    /// Extracts the access level from a struct declaration
    private static func getAccessLevel(from structDecl: StructDeclSyntax) -> String {
        for modifier in structDecl.modifiers {
            switch modifier.name.tokenKind {
            case .keyword(.public):
                return "public "
            case .keyword(.internal):
                return ""  // internal is the default, no keyword needed
            case .keyword(.fileprivate):
                return "fileprivate "
            case .keyword(.private):
                return "private "
            case .keyword(.package):
                return "package "
            default:
                continue
            }
        }
        return ""  // Default is internal (no keyword)
    }

    /// Generates the Entity struct for App Intents integration
    private static func generateEntityCode(
        typeName: String,
        entityTypeName: String,
        displayName: String,
        titleProperty: String,
        accessLevel: String
    ) -> String {
        return """
/// App Intents entity wrapper for \(typeName)
/// Generated by @Persistable macro
\(accessLevel)struct \(entityTypeName): AppIntents.AppEntity {
    \(accessLevel)let wrapped: \(typeName)

    \(accessLevel)init(_ wrapped: \(typeName)) {
        self.wrapped = wrapped
    }

    \(accessLevel)var id: String { wrapped.id }

    \(accessLevel)static var typeDisplayRepresentation: AppIntents.TypeDisplayRepresentation {
        AppIntents.TypeDisplayRepresentation(name: "\(displayName)")
    }

    \(accessLevel)var displayRepresentation: AppIntents.DisplayRepresentation {
        AppIntents.DisplayRepresentation(title: "\\(wrapped.\(titleProperty))")
    }

    \(accessLevel)static var defaultQuery: \(entityTypeName)Query { \(entityTypeName)Query() }

    /// Query for fetching \(typeName) entities
    \(accessLevel)struct \(entityTypeName)Query: AppIntents.EntityQuery {
        \(accessLevel)init() {}

        \(accessLevel)func entities(for identifiers: [String]) async throws -> [\(entityTypeName)] {
            try await Archery.OperationTracer.trace(
                "EntityQuery.entities",
                category: .query,
                attributes: ["type": "\(typeName)", "count": "\\(identifiers.count)"]
            ) {
                guard let container = PersistenceContainer.current else {
                    return []
                }
                return try await container.read { db in
                    try \(typeName)
                        .filter(ids: identifiers)
                        .fetchAll(db)
                        .map { \(entityTypeName)($0) }
                }
            }
        }

        \(accessLevel)func suggestedEntities() async throws -> [\(entityTypeName)] {
            try await Archery.OperationTracer.trace(
                "EntityQuery.suggestedEntities",
                category: .query,
                attributes: ["type": "\(typeName)"]
            ) {
                guard let container = PersistenceContainer.current else {
                    return []
                }
                return try await container.read { db in
                    try \(typeName)
                        .limit(10)
                        .fetchAll(db)
                        .map { \(entityTypeName)($0) }
                }
            }
        }
    }
}
"""
    }

    /// Generates the ListIntent peer struct
    private static func generateListIntentPeer(
        typeName: String,
        entityTypeName: String,
        displayNamePlural: String,
        accessLevel: String
    ) -> String {
        return """
/// List intent for \(displayNamePlural)
\(accessLevel)struct \(entityTypeName)ListIntent: AppIntents.AppIntent {
    \(accessLevel)static var title: LocalizedStringResource { "List \(displayNamePlural)" }
    \(accessLevel)static var description: AppIntents.IntentDescription { "Lists all \(displayNamePlural.lowercased())" }

    \(accessLevel)init() {}

    @MainActor
    \(accessLevel)func perform() async throws -> some AppIntents.IntentResult & AppIntents.ReturnsValue<[\(entityTypeName)]> {
        guard let container = PersistenceContainer.current else {
            return .result(value: [])
        }
        let items = try await container.read { db in
            try \(typeName).fetchAll(db)
        }
        return .result(value: items.map { \(entityTypeName)($0) })
    }
}
"""
    }

    /// Generates the DeleteIntent peer struct
    private static func generateDeleteIntentPeer(
        typeName: String,
        entityTypeName: String,
        displayName: String,
        accessLevel: String
    ) -> String {
        return """
/// Delete intent for \(displayName)
\(accessLevel)struct \(entityTypeName)DeleteIntent: AppIntents.AppIntent {
    \(accessLevel)static var title: LocalizedStringResource { "Delete \(displayName)" }
    \(accessLevel)static var description: AppIntents.IntentDescription { "Deletes a \(displayName.lowercased())" }

    @Parameter(title: "\(displayName)")
    \(accessLevel)var entity: \(entityTypeName)

    \(accessLevel)init() {}

    @MainActor
    \(accessLevel)func perform() async throws -> some AppIntents.IntentResult {
        guard let container = PersistenceContainer.current else {
            throw NSError(domain: "AppIntents", code: -1, userInfo: [NSLocalizedDescriptionKey: "Database not available"])
        }
        _ = try await container.write { db in
            try \(typeName).deleteOne(db, id: entity.id)
        }
        return .result()
    }
}
"""
    }
}

// MARK: - Conformance Detection

extension PersistableMacro {
    /// Get all conformances already declared on the struct
    private static func getExistingConformances(_ structDecl: StructDeclSyntax) -> Set<String> {
        guard let inheritanceClause = structDecl.inheritanceClause else {
            return []
        }

        var conformances = Set<String>()
        for inheritedType in inheritanceClause.inheritedTypes {
            let typeName = inheritedType.type.trimmedDescription
            conformances.insert(typeName)
        }
        return conformances
    }

    // MARK: - App Entity Member Generation

    private static func generateAppEntityMembersInline(
        typeName: String,
        displayName: String,
        titleProperty: String
    ) -> String {
        // All properties must be nonisolated for Swift 6 Sendable compatibility
        // Use unique query type name to avoid App Intents identifier conflicts
        """
            /// Default query for App Intents
            public nonisolated static var defaultQuery: \(typeName)EntityQuery { \(typeName)EntityQuery() }

            /// Type display representation for App Intents
            public nonisolated static var typeDisplayRepresentation: TypeDisplayRepresentation {
                TypeDisplayRepresentation(name: "\(displayName)")
            }

            /// Display representation for this instance
            public nonisolated var displayRepresentation: DisplayRepresentation {
                DisplayRepresentation(title: "\\(self.\(titleProperty))")
            }
        """
    }

    // MARK: - Entity Query Generation

    private static func generateEntityQueryCode(typeName: String) -> String {
        // EntityQuery must be nonisolated and work with async contexts
        // Use unique struct name to avoid App Intents identifier conflicts
        // Wrap database operations with OperationTracer for performance tracing
        """
        /// EntityQuery for \(typeName) - fetches from database
            public struct \(typeName)EntityQuery: AppIntents.EntityQuery, Sendable {
                public init() {}

                public func entities(for identifiers: [String]) async throws -> [\(typeName)] {
                    try await Archery.OperationTracer.trace(
                        "EntityQuery.entities",
                        category: .query,
                        attributes: ["type": "\(typeName)", "count": "\\(identifiers.count)"]
                    ) {
                        guard let container = PersistenceContainer.current else { return [] }
                        return try await container.read { db in
                            try \(typeName).filter(ids: identifiers).fetchAll(db)
                        }
                    }
                }

                public func suggestedEntities() async throws -> [\(typeName)] {
                    try await Archery.OperationTracer.trace(
                        "EntityQuery.suggestedEntities",
                        category: .query,
                        attributes: ["type": "\(typeName)"]
                    ) {
                        guard let container = PersistenceContainer.current else { return [] }
                        return try await container.read { db in
                            try \(typeName).limit(10).fetchAll(db)
                        }
                    }
                }
            }
        """
    }

    // Note: Intent types (ListIntent, DeleteIntent) are generated by the PeerMacro
    // as top-level peer types, not nested members
}
