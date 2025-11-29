import Foundation
import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

enum PersistenceGatewayDiagnostic: String, DiagnosticMessage {
    case mustBeEnum
    case missingAssociatedValue
    case multipleAssociatedValues

    var message: String {
        switch self {
        case .mustBeEnum: return "@PersistenceGateway can only be applied to an enum"
        case .missingAssociatedValue: return "Each case must have a single associated value"
        case .multipleAssociatedValues: return "Cases may have only one associated value"
        }
    }

    var diagnosticID: MessageID { .init(domain: "ArcheryMacros", id: rawValue) }
    var severity: DiagnosticSeverity { .error }
}

public enum PersistenceGatewayMacro: MemberMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingMembersOf declaration: some DeclGroupSyntax,
        conformingTo _: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        guard let enumDecl = declaration.as(EnumDeclSyntax.self) else {
            throw DiagnosticsError(diagnostics: [diagnostic(for: declaration, kind: .mustBeEnum)])
        }

        let isPublic = enumDecl.modifiers.contains { $0.name.tokenKind == .keyword(.public) }
        let access = isPublic ? "public " : ""
        let enumName = enumDecl.name.text

        var cases: [(name: String, type: String)] = []
        for member in enumDecl.memberBlock.members {
            guard let caseDecl = member.decl.as(EnumCaseDeclSyntax.self) else { continue }
            for element in caseDecl.elements {
                guard let params = element.parameterClause?.parameters, params.count == 1, let param = params.first else {
                    throw DiagnosticsError(diagnostics: [diagnostic(for: member.decl, kind: paramsCountDiagnostic(for: member.decl))])
                }
                cases.append((element.name.text, param.type.trimmedDescription))
            }
        }

        let keySwitch = cases
            .map { "    case .\($0.name):\n        return \"\(enumName).\($0.name)\"" }
            .joined(separator: "\n")

        let setSwitch = cases
            .map { "        case .\($0.name)(let value):\n            try await store.set(data: encoder.encode(value), for: \"\(enumName).\($0.name)\")" }
            .joined(separator: "\n")

        let typedGetters = cases.map {
            """
    func \($0.name)(default defaultValue: \($0.type)? = nil) async throws -> \($0.type)? {
        guard let data = try await store.data(for: "\(enumName).\($0.name)") else { return defaultValue }
        return try decoder.decode(\($0.type).self, from: data)
    }
"""
        }.joined(separator: "\n")

        let typedSetters = cases.map {
            let cap = $0.name.prefix(1).uppercased() + String($0.name.dropFirst())
            return """
    func set\(cap)(_ value: \($0.type)) async throws {
        try await store.set(data: encoder.encode(value), for: "\(enumName).\($0.name)")
    }
"""
        }.joined(separator: "\n")

        let keyNameDecl = """
\(access)var keyName: String {
    switch self {
\(keySwitch)
    }
}
"""

        let gatewayDecl = """
\(access)struct Gateway {
    private let store: SQLiteKVStore
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    typealias Seed = (key: \(enumName), value: any Encodable)

    \(access)init(url: URL, migrations: [SQLiteMigration] = [], seeds: [Seed] = []) throws {
        self.store = try SQLiteKVStore(
            url: url,
            migrations: migrations,
            seed: try Self.encodeSeeds(seeds, encoder: encoder)
        )
    }

    \(access)init(inMemory seeds: [Seed] = [], migrations: [SQLiteMigration] = []) throws {
        self.store = try SQLiteKVStore.inMemory(
            migrations: migrations,
            seed: try Self.encodeSeeds(seeds, encoder: encoder)
        )
    }

    func get<T: Codable>(_ key: \(enumName), as type: T.Type = T.self, default defaultValue: T? = nil) async throws -> T? {
        guard let data = try await store.data(for: key.keyName) else { return defaultValue }
        return try decoder.decode(T.self, from: data)
    }

    func set(_ key: \(enumName)) async throws {
        switch key {
\(setSwitch)
        }
    }

    func remove(_ key: \(enumName)) async throws {
        try await store.remove(key.keyName)
    }

    func changes() -> AsyncStream<SQLiteKVStore.Change> {
        store.changes()
    }

\(typedGetters)

\(typedSetters)

    private static func encodeSeeds(_ seeds: [Seed], encoder: JSONEncoder) throws -> [String: Data] {
        try seeds.reduce(into: [String: Data]()) { partialResult, element in
            partialResult[element.key.keyName] = try encoder.encode(AnyEncodable(value: element.value))
        }
    }

    private struct AnyEncodable: Encodable {
        let value: any Encodable
        func encode(to encoder: Encoder) throws {
            try value.encode(to: encoder)
        }
    }
}
"""

        return [DeclSyntax(stringLiteral: keyNameDecl), DeclSyntax(stringLiteral: gatewayDecl)]
    }

    private static func paramsCountDiagnostic(for node: some SyntaxProtocol) -> PersistenceGatewayDiagnostic {
        if let decl = node.as(EnumCaseDeclSyntax.self),
           let elem = decl.elements.first,
           elem.parameterClause?.parameters.count ?? 0 == 0 {
            return .missingAssociatedValue
        }
        return .multipleAssociatedValues
    }

    private static func diagnostic(for node: some SyntaxProtocol, kind: PersistenceGatewayDiagnostic) -> Diagnostic {
        Diagnostic(node: Syntax(node), message: kind)
    }
}

private extension SyntaxProtocol {
    var trimmedDescription: String { description.trimmingCharacters(in: .whitespacesAndNewlines) }
}
