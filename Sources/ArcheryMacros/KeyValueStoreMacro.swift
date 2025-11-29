import Foundation
import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

enum KeyValueStoreDiagnostic: String, DiagnosticMessage {
    case mustBeEnum
    case missingAssociatedValue
    case multipleAssociatedValues

    var message: String {
        switch self {
        case .mustBeEnum: return "@KeyValueStore can only be applied to an enum"
        case .missingAssociatedValue: return "Each case must have a single associated value"
        case .multipleAssociatedValues: return "Cases may have only one associated value"
        }
    }

    var diagnosticID: MessageID { .init(domain: "ArcheryMacros", id: rawValue) }
    var severity: DiagnosticSeverity { .error }
}

public enum KeyValueStoreMacro: MemberMacro {
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
            .map { "        case .\($0.name)(let value):\n            storage[\"\(enumName).\($0.name)\"] = try encoder.encode(value)\n            notify(key: key)" }
            .joined(separator: "\n")

        let typedGetters = cases.map {
            """
    func \($0.name)(default defaultValue: \($0.type)? = nil) async throws -> \($0.type)? {
        guard let data = storage["\(enumName).\($0.name)"] else { return defaultValue }
        return try decoder.decode(\($0.type).self, from: data)
    }
"""
        }.joined(separator: "\n")

        let typedSetters = cases.map {
            let cap = $0.name.prefix(1).uppercased() + String($0.name.dropFirst())
            return """
    mutating func set\(cap)(_ value: \($0.type)) async throws {
        storage["\(enumName).\($0.name)"] = try encoder.encode(value)
        notify(key: .\($0.name)(value))
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

        let storeDecl = """
\(access)struct Store {
    private var storage: [String: Data] = [:]
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let migrations: [String: String]
    private var changeContinuation: AsyncStream<Change>.Continuation?

    struct Change {
        let key: \(enumName)
        let data: Data?
    }

    \(access)init(initialValues: [String: Data] = [:], migrations: [String: String] = [:]) {
        self.storage = initialValues
        self.migrations = migrations
        applyMigrations()
    }

    mutating func set(_ key: \(enumName)) async throws {
        switch key {
\(setSwitch)
        }
    }

    func get<T: Codable>(_ key: \(enumName), as type: T.Type = T.self, default defaultValue: T? = nil) async throws -> T? {
        guard let data = storage[key.keyName] else { return defaultValue }
        return try decoder.decode(T.self, from: data)
    }

    mutating func remove(_ key: \(enumName)) async {
        storage[key.keyName] = nil
        notify(key: key)
    }

    mutating func migrate(_ mapping: [String: String]) {
        for (old, new) in mapping {
            if let data = storage.removeValue(forKey: old) {
                storage[new] = data
            }
        }
    }

    mutating func changes() -> AsyncStream<Change> {
        var captured: AsyncStream<Change>.Continuation!
        let stream = AsyncStream<Change> { continuation in
            captured = continuation
        }
        self.changeContinuation = captured
        return stream
    }

    private mutating func applyMigrations() {
        migrate(migrations)
    }

    private func notify(key: \(enumName)) {
        if let continuation = changeContinuation {
            continuation.yield(Change(key: key, data: storage[key.keyName]))
        }
    }

\(typedGetters)

\(typedSetters)
}
"""

        return [DeclSyntax(stringLiteral: keyNameDecl), DeclSyntax(stringLiteral: storeDecl)]
    }

    private static func paramsCountDiagnostic(for node: some SyntaxProtocol) -> KeyValueStoreDiagnostic {
        if let decl = node.as(EnumCaseDeclSyntax.self),
           let elem = decl.elements.first,
           elem.parameterClause?.parameters.count ?? 0 == 0 {
            return .missingAssociatedValue
        }
        return .multipleAssociatedValues
    }

    private static func diagnostic(for node: some SyntaxProtocol, kind: KeyValueStoreDiagnostic) -> Diagnostic {
        Diagnostic(node: Syntax(node), message: kind)
    }
}

private extension SyntaxProtocol {
    var trimmedDescription: String { description.trimmingCharacters(in: .whitespacesAndNewlines) }
}
