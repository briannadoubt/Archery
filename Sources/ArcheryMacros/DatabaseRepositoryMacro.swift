import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

// MARK: - Diagnostics

enum DatabaseRepositoryDiagnostic: String, DiagnosticMessage {
    case mustBeClass
    case missingRecordType

    var message: String {
        switch self {
        case .mustBeClass:
            return "@DatabaseRepository can only be applied to a class"
        case .missingRecordType:
            return "@DatabaseRepository requires a record type parameter"
        }
    }

    var diagnosticID: MessageID {
        MessageID(domain: "ArcheryMacros", id: rawValue)
    }

    var severity: DiagnosticSeverity { .error }
}

// MARK: - @DatabaseRepository Macro

/// Generates a repository pattern for GRDB with protocol, live, and mock implementations.
/// Automatically generates CRUD methods for the specified record type.
public enum DatabaseRepositoryMacro: PeerMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingPeersOf decl: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        guard let classDecl = decl.as(ClassDeclSyntax.self) else {
            throw DiagnosticsError(diagnostics: [
                Diagnostic(node: Syntax(node), message: DatabaseRepositoryDiagnostic.mustBeClass)
            ])
        }

        let config = parseConfig(from: node)

        guard let recordType = config.recordType else {
            throw DiagnosticsError(diagnostics: [
                Diagnostic(node: Syntax(node), message: DatabaseRepositoryDiagnostic.missingRecordType)
            ])
        }

        let isPublic = classDecl.modifiers.contains { $0.name.tokenKind == .keyword(.public) }
        let access = isPublic ? "public " : ""
        let className = classDecl.name.text
        let protocolName = "\(className)Protocol"
        let mockName = "Mock\(className)"
        let liveName = "\(className)Live"

        // Extract custom methods from the class
        let customMethods = classDecl.memberBlock.members.compactMap { member -> GRDBMethodInfo? in
            guard let funcDecl = member.decl.as(FunctionDeclSyntax.self) else { return nil }
            return GRDBMethodInfo(funcDecl)
        }

        // Generate protocol
        let protocolDecl = generateProtocol(
            name: protocolName,
            recordType: recordType,
            customMethods: customMethods,
            access: access
        )

        // Generate live implementation
        let liveDecl = generateLiveImpl(
            name: liveName,
            protocolName: protocolName,
            recordType: recordType,
            customMethods: customMethods,
            className: className,
            access: access,
            enableTracing: config.tracing
        )

        // Generate mock implementation
        let mockDecl = generateMockImpl(
            name: mockName,
            protocolName: protocolName,
            recordType: recordType,
            customMethods: customMethods,
            access: access
        )

        // Note: PeerMacros cannot produce extensions, so DI helpers are provided
        // on the Live and Mock types directly via their initializers.
        // Users can access:
        //   - PlayerStoreLive(db: writer) or PlayerStoreLive(container: container)
        //   - MockPlayerStore()

        return [
            DeclSyntax(stringLiteral: protocolDecl),
            DeclSyntax(stringLiteral: liveDecl),
            DeclSyntax(stringLiteral: mockDecl)
        ]
    }

    // MARK: - Configuration Parsing

    struct Config {
        var recordType: String?
        var tracing: Bool = false
    }

    static func parseConfig(from node: AttributeSyntax) -> Config {
        var config = Config()

        guard let arguments = node.arguments?.as(LabeledExprListSyntax.self) else {
            return config
        }

        for argument in arguments {
            let label = argument.label?.text

            switch label {
            case "record", nil:
                // Handle Type.self expression
                if let memberAccess = argument.expression.as(MemberAccessExprSyntax.self),
                   memberAccess.declName.baseName.text == "self",
                   let base = memberAccess.base?.as(DeclReferenceExprSyntax.self) {
                    config.recordType = base.baseName.text
                }
            case "tracing":
                if let boolLiteral = argument.expression.as(BooleanLiteralExprSyntax.self) {
                    config.tracing = boolLiteral.literal.tokenKind == .keyword(.true)
                }
            default:
                break
            }
        }

        return config
    }

    // MARK: - Code Generation

    static func generateProtocol(
        name: String,
        recordType: String,
        customMethods: [GRDBMethodInfo],
        access: String
    ) -> String {
        let customMethodDecls = customMethods.map { method in
            "    func \(method.name)\(method.signature)"
        }.joined(separator: "\n")

        let customSection = customMethods.isEmpty ? "" : "\n\n    // Custom methods\n\(customMethodDecls)"

        return """

\(access)protocol \(name): Sendable {
    // CRUD operations
    func fetchAll() async throws -> [\(recordType)]
    func fetch(id: \(recordType).ID) async throws -> \(recordType)?
    func insert(_ record: \(recordType)) async throws -> \(recordType)
    func update(_ record: \(recordType)) async throws
    func upsert(_ record: \(recordType)) async throws -> \(recordType)
    func delete(id: \(recordType).ID) async throws -> Bool
    func deleteAll() async throws -> Int
    func count() async throws -> Int\(customSection)
}
"""
    }

    static func generateLiveImpl(
        name: String,
        protocolName: String,
        recordType: String,
        customMethods: [GRDBMethodInfo],
        className: String,
        access: String,
        enableTracing: Bool
    ) -> String {
        let customMethodImpls = customMethods.map { method in
            """
                func \(method.name)\(method.signature) {
                    \(method.returnPrefix)base.\(method.name)(\(method.callParams))
                }
            """
        }.joined(separator: "\n\n")

        let customSection = customMethods.isEmpty ? "" : "\n\n    // Custom methods\n\(customMethodImpls)"

        // Table name derived from record type (lowercase + 's')
        let tableName = recordType.lowercased() + "s"

        return """

\(access)final class \(name): \(protocolName), @unchecked Sendable {
    private let container: Archery.PersistenceContainer
    private let base: \(className)
    private let entityTypeName = "\(recordType)"
    private let tableName = "\(tableName)"

    \(access)init(container: Archery.PersistenceContainer) {
        self.container = container
        self.base = \(className)()
    }

    \(access)init(envContainer: Archery.EnvContainer) {
        guard let persistenceContainer = envContainer.grdb else {
            fatalError("PersistenceContainer not registered in EnvContainer")
        }
        self.container = persistenceContainer
        self.base = \(className)()
    }

    // CRUD operations with performance tracing

    \(access)func fetchAll() async throws -> [\(recordType)] {
        try await Archery.OperationTracer.traceDatabase("fetchAll", table: tableName) {
            let start = ContinuousClock.now
            let results = try await container.read { db in try \(recordType).fetchAll(db) }
            let duration = ContinuousClock.now - start
            let durationMs = Double(duration.components.attoseconds) / 1_000_000_000_000_000

            // Auto-track fetch
            await MainActor.run {
                ArcheryAnalyticsConfiguration.shared.track(
                    .entityFetched(entityType: entityTypeName, count: results.count, durationMs: durationMs)
                )
            }

            return results
        }
    }

    \(access)func fetch(id: \(recordType).ID) async throws -> \(recordType)? {
        try await Archery.OperationTracer.traceDatabase("fetch", table: tableName) {
            try await container.read { db in try \(recordType).fetchOne(db, id: id) }
        }
    }

    \(access)func insert(_ record: \(recordType)) async throws -> \(recordType) {
        try await Archery.OperationTracer.traceDatabase("insert", table: tableName) {
            let result = try await container.write { db in
                var record = record
                try record.insert(db)
                return record
            }

            // Auto-track entity created
            await MainActor.run {
                ArcheryAnalyticsConfiguration.shared.track(
                    .entityCreated(entityType: entityTypeName, entityId: String(describing: result.id))
                )
            }

            return result
        }
    }

    \(access)func update(_ record: \(recordType)) async throws {
        try await Archery.OperationTracer.traceDatabase("update", table: tableName) {
            try await container.write { db in try record.update(db) }

            // Auto-track entity updated
            await MainActor.run {
                ArcheryAnalyticsConfiguration.shared.track(
                    .entityUpdated(entityType: entityTypeName, entityId: String(describing: record.id))
                )
            }
        }
    }

    \(access)func upsert(_ record: \(recordType)) async throws -> \(recordType) {
        try await Archery.OperationTracer.traceDatabase("upsert", table: tableName) {
            let result = try await container.write { db in
                var record = record
                try record.save(db)
                return record
            }

            // Auto-track entity created/updated (upsert)
            await MainActor.run {
                ArcheryAnalyticsConfiguration.shared.track(
                    .entityUpdated(entityType: entityTypeName, entityId: String(describing: result.id))
                )
            }

            return result
        }
    }

    \(access)func delete(id: \(recordType).ID) async throws -> Bool {
        try await Archery.OperationTracer.traceDatabase("delete", table: tableName) {
            let deleted = try await container.write { db in try \(recordType).deleteOne(db, id: id) }

            if deleted {
                // Auto-track entity deleted
                await MainActor.run {
                    ArcheryAnalyticsConfiguration.shared.track(
                        .entityDeleted(entityType: entityTypeName, entityId: String(describing: id))
                    )
                }
            }

            return deleted
        }
    }

    \(access)func deleteAll() async throws -> Int {
        try await Archery.OperationTracer.traceDatabase("deleteAll", table: tableName) {
            try await container.write { db in try \(recordType).deleteAll(db) }
        }
    }

    \(access)func count() async throws -> Int {
        try await Archery.OperationTracer.traceDatabase("count", table: tableName) {
            try await container.read { db in try \(recordType).fetchCount(db) }
        }
    }\(customSection)
}
"""
    }

    static func generateMockImpl(
        name: String,
        protocolName: String,
        recordType: String,
        customMethods: [GRDBMethodInfo],
        access: String
    ) -> String {
        let customHandlerDecls = customMethods.map { method in
            "\(access)var \(method.name)Handler: (\(method.handlerType))?"
        }.joined(separator: "\n    ")

        let customMethodImpls = customMethods.map { method in
            """
                \(access)func \(method.name)\(method.signature) {
                    guard let handler = \(method.name)Handler else {
                        fatalError("\(method.name)Handler not set in mock")
                    }
                    \(method.returnPrefix)handler(\(method.handlerCallParams))
                }
            """
        }.joined(separator: "\n\n")

        let customHandlerSection = customMethods.isEmpty ? "" : "\n\n    // Custom method handlers\n    \(customHandlerDecls)"
        let customMethodSection = customMethods.isEmpty ? "" : "\n\n    // Custom methods\n\(customMethodImpls)"

        return """

\(access)final class \(name): \(protocolName), @unchecked Sendable {
    // CRUD handlers
    \(access)var fetchAllHandler: () async throws -> [\(recordType)] = { [] }
    \(access)var fetchHandler: (\(recordType).ID) async throws -> \(recordType)? = { _ in nil }
    \(access)var insertHandler: (\(recordType)) async throws -> \(recordType) = { $0 }
    \(access)var updateHandler: (\(recordType)) async throws -> Void = { _ in }
    \(access)var upsertHandler: (\(recordType)) async throws -> \(recordType) = { $0 }
    \(access)var deleteHandler: (\(recordType).ID) async throws -> Bool = { _ in true }
    \(access)var deleteAllHandler: () async throws -> Int = { 0 }
    \(access)var countHandler: () async throws -> Int = { 0 }\(customHandlerSection)

    \(access)init() {}

    // CRUD operations

    \(access)func fetchAll() async throws -> [\(recordType)] {
        try await fetchAllHandler()
    }

    \(access)func fetch(id: \(recordType).ID) async throws -> \(recordType)? {
        try await fetchHandler(id)
    }

    \(access)func insert(_ record: \(recordType)) async throws -> \(recordType) {
        try await insertHandler(record)
    }

    \(access)func update(_ record: \(recordType)) async throws {
        try await updateHandler(record)
    }

    \(access)func upsert(_ record: \(recordType)) async throws -> \(recordType) {
        try await upsertHandler(record)
    }

    \(access)func delete(id: \(recordType).ID) async throws -> Bool {
        try await deleteHandler(id)
    }

    \(access)func deleteAll() async throws -> Int {
        try await deleteAllHandler()
    }

    \(access)func count() async throws -> Int {
        try await countHandler()
    }\(customMethodSection)
}
"""
    }

}

// MARK: - Method Info Helper

struct GRDBMethodInfo {
    let name: String
    let signature: String
    let handlerType: String
    let callParams: String        // For calling methods with labels: "limit: limit"
    let handlerCallParams: String // For calling closures without labels: "limit"
    let returnPrefix: String

    init(_ funcDecl: FunctionDeclSyntax) {
        self.name = funcDecl.name.text

        // Build signature string
        let paramClause = funcDecl.signature.parameterClause.trimmedDescription
        let effectsString = funcDecl.signature.effectSpecifiers.map { effects in
            var parts: [String] = []
            if effects.asyncSpecifier != nil { parts.append("async") }
            if effects.throwsClause != nil { parts.append("throws") }
            return parts.isEmpty ? "" : " " + parts.joined(separator: " ")
        } ?? ""
        let returnClause = funcDecl.signature.returnClause.map { " -> \($0.type.trimmedDescription)" } ?? ""
        self.signature = "\(paramClause)\(effectsString)\(returnClause)"

        // Build handler type
        let params = funcDecl.signature.parameterClause.parameters
        let paramTypes = params.map { $0.type.trimmedDescription }.joined(separator: ", ")
        let returnType = funcDecl.signature.returnClause?.type.trimmedDescription ?? "Void"
        let throwsPrefix = funcDecl.signature.effectSpecifiers?.throwsClause != nil ? "throws " : ""
        let asyncPrefix = funcDecl.signature.effectSpecifiers?.asyncSpecifier != nil ? "async " : ""
        self.handlerType = "(\(paramTypes)) \(asyncPrefix)\(throwsPrefix)-> \(returnType)"

        // Build call params for calling the method (with labels)
        // e.g., for func topScorers(limit: Int) we need "limit: limit"
        self.callParams = params.map { param in
            let externalLabel = param.firstName.text  // Label used when calling
            let internalName = param.secondName?.text ?? externalLabel  // Name inside function

            if externalLabel == "_" {
                // For unlabeled params, just use the internal name
                return internalName
            } else {
                // For labeled params, use "label: value"
                return "\(externalLabel): \(internalName)"
            }
        }.joined(separator: ", ")

        // Build handler call params (without labels, for closure calls)
        // e.g., for func topScorers(limit: Int) we need just "limit"
        self.handlerCallParams = params.map { param in
            let externalLabel = param.firstName.text
            return param.secondName?.text ?? externalLabel
        }.joined(separator: ", ")

        // Return prefix
        let hasReturn = funcDecl.signature.returnClause != nil
        let isAsync = funcDecl.signature.effectSpecifiers?.asyncSpecifier != nil
        let isThrowing = funcDecl.signature.effectSpecifiers?.throwsClause != nil
        var prefix = ""
        if hasReturn { prefix += "return " }
        if isThrowing { prefix += "try " }
        if isAsync { prefix += "await " }
        self.returnPrefix = prefix
    }
}
