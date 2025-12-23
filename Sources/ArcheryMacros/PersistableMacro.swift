import SwiftCompilerPlugin
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros
import SwiftDiagnostics

// MARK: - Diagnostics

enum PersistableDiagnostic: String, DiagnosticMessage {
    case mustBeStruct
    case noProperties

    var message: String {
        switch self {
        case .mustBeStruct:
            return "@Persistable can only be applied to structs"
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

/// Generates GRDB conformances, type-safe Columns enum, and optionally full App Intents integration.
///
/// Basic Usage (database only):
/// ```swift
/// @Persistable(table: "players")
/// struct Player: Codable, Identifiable, Sendable, FetchableRecord, PersistableRecord {
///     var id: String
///     var name: String
///     var score: Int
/// }
/// ```
///
/// Full Usage (database + App Intents):
/// ```swift
/// @Persistable(table: "tasks", displayName: "Task", titleProperty: "title")
/// struct TaskItem: Codable, Identifiable, Sendable, FetchableRecord, PersistableRecord {
///     var id: String
///     var title: String
///     var status: TaskStatus
/// }
/// ```
///
/// When `displayName` is provided, generates:
/// - `AppEntity` conformance with `EntityQuery`
/// - CRUD intents: `CreateIntent`, `ListIntent`, `DeleteIntent`
/// - `Shortcuts: AppShortcutsProvider` (unless `shortcuts: false`)
///
/// All generated App Intents code is Swift 6 concurrency-safe with proper `nonisolated` and `@MainActor` annotations.
public struct PersistableMacro: MemberMacro, ExtensionMacro {

    // MARK: - Configuration

    struct Config {
        var tableName: String?
        var primaryKey: String = "id"
        // App Intents configuration
        var displayName: String?
        var titleProperty: String = "title"
        var generateIntents: Bool = true
        var generateShortcuts: Bool = true
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
            case "shortcuts":
                config.generateShortcuts = argument.expression.description.trimmingCharacters(in: .whitespaces) == "true"
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

        // Note: App Intents members are generated in the extension, not as struct members
        // This allows proper isolation handling for Swift 6 concurrency

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
        let config = parseConfig(from: node, typeName: typeName)
        let properties = extractProperties(from: structDecl)
        var extensions: [ExtensionDeclSyntax] = []

        // Check which conformances are already declared
        let existingConformances = getExistingConformances(structDecl)

        // Mode selection based on displayName:
        // - No displayName: database-only mode (add Sendable, skip AppEntity)
        // - With displayName: App Intents mode (skip Sendable, add AppEntity)
        let isAppIntentsMode = config.displayName != nil

        // Note: We only generate Identifiable, Hashable, Sendable via extension.
        // Codable, FetchableRecord, PersistableRecord must be declared on the struct
        // because PersistableRecord requires Encodable to be visible at struct definition.
        var conformances: [String] = []

        // Swift standard library conformances (not Codable - must be on struct for GRDB)
        if !existingConformances.contains("Identifiable") {
            conformances.append("Identifiable")
        }
        if !existingConformances.contains("Hashable") {
            conformances.append("Hashable")
        }

        // Sendable only in database-only mode (not compatible with AppEntity in Swift 6)
        if !isAppIntentsMode && !existingConformances.contains("Sendable") {
            conformances.append("Sendable")
        }

        // Generate conformances extension
        if !conformances.isEmpty {
            let conformanceList = conformances.joined(separator: ", ")
            let conformanceExtension = try ExtensionDeclSyntax(
                "extension \(raw: typeName): \(raw: conformanceList) {}"
            )
            extensions.append(conformanceExtension)
        }

        // Generate App Intents extension if in App Intents mode
        if isAppIntentsMode {
            let displayName = config.displayName!
            let appEntityMembers = generateAppEntityMembersInline(
                typeName: typeName,
                displayName: displayName,
                titleProperty: config.titleProperty
            )
            let entityQueryCode = generateEntityQueryCode(typeName: typeName)
            let createIntentCode = config.generateIntents ? generateCreateIntentCode(
                typeName: typeName,
                displayName: displayName,
                titleProperty: config.titleProperty,
                properties: properties
            ) : ""
            let listIntentCode = config.generateIntents ? generateListIntentCode(
                typeName: typeName,
                displayName: displayName
            ) : ""
            let deleteIntentCode = config.generateIntents ? generateDeleteIntentCode(
                typeName: typeName,
                displayName: displayName,
                titleProperty: config.titleProperty
            ) : ""
            let shortcutsCode = config.generateShortcuts ? generateShortcutsProviderCode(
                typeName: typeName,
                displayName: displayName
            ) : ""

            // Use @preconcurrency to suppress Swift 6 actor isolation conflicts
            // AppEntity has complex isolation requirements that conflict with extension-added conformances
            let appEntityExtension = try ExtensionDeclSyntax(
                """
                extension \(raw: typeName): @preconcurrency AppEntity {
                    \(raw: appEntityMembers)

                    \(raw: entityQueryCode)

                    \(raw: createIntentCode)

                    \(raw: listIntentCode)

                    \(raw: deleteIntentCode)

                    \(raw: shortcutsCode)
                }
                """
            )
            extensions.append(appEntityExtension)
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

    // MARK: - Conformance Detection

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
        """
        /// EntityQuery for \(typeName) - fetches from database
            public struct \(typeName)EntityQuery: AppIntents.EntityQuery, Sendable {
                public init() {}

                public func entities(for identifiers: [String]) async throws -> [\(typeName)] {
                    guard let container = PersistenceContainer.current else { return [] }
                    return try await container.read { db in
                        try \(typeName).filter(ids: identifiers).fetchAll(db)
                    }
                }

                public func suggestedEntities() async throws -> [\(typeName)] {
                    guard let container = PersistenceContainer.current else { return [] }
                    return try await container.read { db in
                        try \(typeName).limit(10).fetchAll(db)
                    }
                }
            }
        """
    }

    // MARK: - Intent Generation

    private static func generateCreateIntentCode(
        typeName: String,
        displayName: String,
        titleProperty: String,
        properties: [PropertyInfo]
    ) -> String {
        // Build parameter declarations for supported types
        let supportedTypes = ["String", "Int", "Double", "Bool", "Date", "URL"]
        let parameterDecls = properties.compactMap { prop -> String? in
            let baseType = prop.type.replacingOccurrences(of: "?", with: "")
            let isEnum = !supportedTypes.contains(baseType) && baseType.first?.isUppercase == true

            if prop.isOptional || isEnum || supportedTypes.contains(baseType) {
                return """
                        @Parameter(title: "\(prop.displayName)")
                        var \(prop.name): \(prop.type)
                """
            }
            return nil
        }.joined(separator: "\n\n")

        // Build initializer assignments
        let initAssignments = properties.compactMap { prop -> String? in
            let baseType = prop.type.replacingOccurrences(of: "?", with: "")
            let isEnum = !supportedTypes.contains(baseType) && baseType.first?.isUppercase == true

            if prop.isOptional || isEnum || supportedTypes.contains(baseType) {
                return "\(prop.name): \(prop.name)"
            }
            return nil
        }.joined(separator: ",\n                    ")

        // perform() must be @MainActor for Swift 6 compatibility with AppEntity
        // Use unique struct name to avoid App Intents identifier conflicts
        return """
            /// Intent to create a new \(displayName)
            public struct \(typeName)CreateIntent: AppIntent {
                public static let title: LocalizedStringResource = "Create \(displayName)"
                public static let description = IntentDescription("Creates a new \(displayName.lowercased())")

        \(parameterDecls)

                public init() {}

                @MainActor
                public func perform() async throws -> some IntentResult & ReturnsValue<\(typeName)> & ProvidesDialog {
                    var item = \(typeName)(
                        \(initAssignments)
                    )

                    if let container = PersistenceContainer.current {
                        // Capture item by value to satisfy Swift 6 concurrency
                        item = try await container.write { [item] db in
                            var mutableItem = item
                            try mutableItem.insert(db)
                            return mutableItem
                        }
                    }

                    return .result(
                        value: item,
                        dialog: "Created \(displayName.lowercased()) '\\(item.\(titleProperty))'"
                    )
                }
            }
        """
    }

    private static func generateListIntentCode(
        typeName: String,
        displayName: String
    ) -> String {
        let displayNameLower = displayName.lowercased()

        // Use unique struct name to avoid App Intents identifier conflicts
        return """
            /// Intent to list all \(displayName)s
            public struct \(typeName)ListIntent: AppIntent {
                public static let title: LocalizedStringResource = "List \(displayName)s"
                public static let description = IntentDescription("Shows all \(displayNameLower)s")
                public static let openAppWhenRun: Bool = true

                @Parameter(title: "Limit", default: 10)
                var limit: Int

                public init() {}

                @MainActor
                public func perform() async throws -> some IntentResult & ReturnsValue<[\(typeName)]> & ProvidesDialog {
                    guard let container = PersistenceContainer.current else {
                        return .result(value: [], dialog: "Could not access database")
                    }

                    let items = try await container.read { db in
                        try \(typeName).limit(limit).fetchAll(db)
                    }

                    return .result(
                        value: items,
                        dialog: "Found \\(items.count) \(displayNameLower)\\(items.count == 1 ? "" : "s")"
                    )
                }
            }
        """
    }

    private static func generateDeleteIntentCode(
        typeName: String,
        displayName: String,
        titleProperty: String
    ) -> String {
        // Use unique struct name to avoid App Intents identifier conflicts
        return """
            /// Intent to delete a \(displayName)
            public struct \(typeName)DeleteIntent: AppIntent {
                public static let title: LocalizedStringResource = "Delete \(displayName)"
                public static let description = IntentDescription("Deletes a \(displayName.lowercased())")

                @Parameter(title: "\(displayName)")
                var item: \(typeName)

                public init() {}

                @MainActor
                public func perform() async throws -> some IntentResult & ProvidesDialog {
                    let itemToDelete = item
                    let title = itemToDelete.\(titleProperty)

                    if let container = PersistenceContainer.current {
                        try await container.write { [itemToDelete] db in
                            _ = try itemToDelete.delete(db)
                        }
                    }

                    return .result(dialog: "Deleted '\\(title)'")
                }
            }
        """
    }

    private static func generateShortcutsProviderCode(
        typeName: String,
        displayName: String
    ) -> String {
        let displayNameLower = displayName.lowercased()
        let displayNamePlural = displayName + "s"
        let displayNamePluralLower = displayNamePlural.lowercased()

        // Use unique struct name to avoid App Intents identifier conflicts
        return """
            /// App Shortcuts for \(typeName)
            public struct \(typeName)Shortcuts: AppShortcutsProvider {
                public static var appShortcuts: [AppShortcut] {
                    AppShortcut(
                        intent: \(typeName).\(typeName)CreateIntent(),
                        phrases: [
                            "Create a \(displayNameLower) in \\(.applicationName)",
                            "New \(displayNameLower) in \\(.applicationName)",
                            "Add \(displayNameLower) to \\(.applicationName)"
                        ],
                        shortTitle: "Create \(displayName)",
                        systemImageName: "plus.circle"
                    )
                    AppShortcut(
                        intent: \(typeName).\(typeName)ListIntent(),
                        phrases: [
                            "Show my \(displayNamePluralLower) in \\(.applicationName)",
                            "List \(displayNamePluralLower) in \\(.applicationName)",
                            "View \(displayNamePluralLower) in \\(.applicationName)"
                        ],
                        shortTitle: "List \(displayNamePlural)",
                        systemImageName: "list.bullet"
                    )
                    AppShortcut(
                        intent: \(typeName).\(typeName)DeleteIntent(),
                        phrases: [
                            "Delete \(displayNameLower) in \\(.applicationName)",
                            "Remove \(displayNameLower) from \\(.applicationName)"
                        ],
                        shortTitle: "Delete \(displayName)",
                        systemImageName: "trash"
                    )
                }
            }
        """
    }
}
