import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

enum APIClientDiagnostic: String, DiagnosticMessage {
    case mustBeClass

    var message: String {
        switch self {
        case .mustBeClass: return "@APIClient can only be applied to a class"
        }
    }

    var diagnosticID: MessageID { .init(domain: "ArcheryMacros", id: rawValue) }
    var severity: DiagnosticSeverity { .error }
}

private struct APIClientAsyncDiagnostic: DiagnosticMessage {
    let method: String

    var message: String { "@APIClient methods must be async: \(method)" }
    var diagnosticID: MessageID { .init(domain: "ArcheryMacros", id: "mustBeAsync") }
    var severity: DiagnosticSeverity { .warning }
}

public enum APIClientMacro: PeerMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingPeersOf decl: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        guard let classDecl = decl.as(ClassDeclSyntax.self) else {
            throw DiagnosticsError(diagnostics: [diagnostic(for: decl, kind: .mustBeClass)])
        }

        let isPublic = classDecl.modifiers.contains { $0.name.tokenKind == .keyword(.public) }
        let access = isPublic ? "public " : ""
        let className = classDecl.name.text
        let protocolName = "\(className)Protocol"
        let mockName = "Mock\(className)"
        let liveName = "\(className)Live"

        let methods = classDecl.memberBlock.members.compactMap { $0.decl.as(FunctionDeclSyntax.self) }

        for method in methods where !method.signature.isAsync {
            context.diagnose(Diagnostic(node: Syntax(method), message: APIClientAsyncDiagnostic(method: method.name.text)))
        }

        let methodInfos = methods.map(MethodInfo.init)

        let protocolFns = methodInfos.map { info in
            "    func \(info.name)\(info.signature)"
        }.joined(separator: "\n")

        let mockProps = methodInfos.map { info in
            "    var \(info.name)Handler: (\(info.handlerType))?"
        }.joined(separator: "\n")

        let mockFns = methodInfos.map { info in
            "    func \(info.name)\(info.signature) {\n        if let handler = \(info.name)Handler { \(info.returnPrefix)\(info.callPrefix)handler(\(info.callParams)) }\n        fatalError(\"Not implemented in mock\")\n    }"
        }.joined(separator: "\n\n")

        let liveFns = methodInfos.map { info in liveFunction(for: info) }.joined(separator: "\n\n")

        let protocolDecl = """

\(access)protocol \(protocolName) {
\(protocolFns)
}
"""

        let diHelpers = """
    static func live(
        cachePolicy: APICachePolicy = .disabled,
        retryPolicy: APIRetryPolicy = .default,
        decoding: APIDecodingConfiguration = .default
    ) -> \(protocolName) {
        \(liveName)(
            baseFactory: { \(className)() },
            retryPolicy: retryPolicy,
            decoding: decoding,
            cachePolicy: cachePolicy
        )
    }

    static func make(
        in container: EnvContainer,
        cachePolicy: APICachePolicy = .disabled,
        retryPolicy: APIRetryPolicy = .default,
        decoding: APIDecodingConfiguration = .default
    ) -> \(protocolName) {
        if let cached: \(protocolName) = container.resolve() {
            return cached
        }
        let client = live(
            cachePolicy: cachePolicy,
            retryPolicy: retryPolicy,
            decoding: decoding
        )
        container.register(client as \(protocolName))
        return client
    }

    static func makeChild(
        from container: EnvContainer,
        cachePolicy: APICachePolicy = .disabled,
        retryPolicy: APIRetryPolicy = .default,
        decoding: APIDecodingConfiguration = .default
    ) -> \(protocolName) {
        let child = EnvContainer()
        container.merge(into: child)
        let client = live(
            cachePolicy: cachePolicy,
            retryPolicy: retryPolicy,
            decoding: decoding
        )
        child.register(client as \(protocolName))
        return client
    }
"""

        let liveDecl = """

\(access)final class \(liveName): \(protocolName), @unchecked Sendable {
    private let base: BaseBox
    private let cachePolicy: APICachePolicy
    private let retryPolicy: APIRetryPolicy
    private let decoding: APIDecodingConfiguration
    private let decoder: JSONDecoder
    private let clock = ContinuousClock()
    struct BaseBox: @unchecked Sendable {
        let value: \(className)
    }
    struct Box: @unchecked Sendable {
        let value: Any
    }
    private let state = State()

    actor State {
        struct CacheEntry {
            let value: Box
            let expiry: ContinuousClock.Instant?
        }

        private var cache: [String: CacheEntry] = [:]

        func cachedValue(for key: String, now: ContinuousClock.Instant) -> Box? {
            guard let entry = cache[key] else { return nil }
            if let expiry = entry.expiry, expiry < now {
                cache[key] = nil
                return nil
            }
            return entry.value
        }
        func setCached(_ value: Box, for key: String, expiry: ContinuousClock.Instant?) {
            cache[key] = CacheEntry(value: value, expiry: expiry)
        }
    }

    \(access)init(
        baseFactory: @escaping () -> \(className) = { \(className)() },
        retryPolicy: APIRetryPolicy = .default,
        decoding: APIDecodingConfiguration = .default,
        cachePolicy: APICachePolicy = .disabled
    ) {
        self.base = BaseBox(value: baseFactory())
        self.retryPolicy = retryPolicy
        self.decoding = decoding
        self.decoder = decoding.makeDecoder()
        self.cachePolicy = cachePolicy
    }

    private func withRetry<T>(
        function: String,
        operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        var attempt = 0
        var lastError: Error?

        while attempt <= retryPolicy.maxRetries {
            if Task.isCancelled {
                throw CancellationError()
            }
            do {
                return try await operation()
            } catch {
                if !retryPolicy.shouldRetry(error) {
                    // Auto-track API error
                    await MainActor.run {
                        ArcheryErrorTracker.trackNetworkError(error, endpoint: function)
                    }
                    throw error
                }
                lastError = error
                if attempt == retryPolicy.maxRetries {
                    break
                }
                let delay = retryPolicy.delay(for: attempt)
                try? await Task.sleep(for: delay)
            }
            attempt += 1
        }

        let finalError = lastError ?? URLError(.unknown)
        // Auto-track API error after all retries exhausted
        await MainActor.run {
            ArcheryErrorTracker.trackNetworkError(finalError, endpoint: function)
        }
        throw finalError
    }

    func decode<T: Decodable>(_ data: Data, as type: T.Type = T.self) throws -> T {
        try decoder.decode(T.self, from: data)
    }

\(liveFns)

\(diHelpers)
}
"""

        let mockDecl = """

\(access)final class \(mockName): \(protocolName) {
\(mockProps)

    \(access)init() {}

\(mockFns)
}
"""

        return [
            DeclSyntax(stringLiteral: protocolDecl),
            DeclSyntax(stringLiteral: liveDecl),
            DeclSyntax(stringLiteral: mockDecl)
        ]
    }

    private static func liveFunction(for info: MethodInfo) -> String {
        let header = "func \(info.name)\(info.signature)"
        let baseCall = "self.base.value.\(info.name)(\(info.callArgs))"

        let cachePolicyExpr = info.cacheOverrideExpr ?? "cachePolicy"

        if info.isAsync && info.isThrowing && !info.returnsVoid {
            return """
    \(header) {
        let policy = \(cachePolicyExpr)
        let key = \(info.keyExpression)
        if policy.enabled, let cached = await state.cachedValue(for: key, now: clock.now)?.value as? \(info.returnType) {
            return cached
        }
        let result = try await withRetry(function: \(info.functionLabelLiteral)) {
            try await \(baseCall)
        }
        if policy.enabled {
            let expiry = policy.ttl.map { clock.now.advanced(by: $0) }
            await state.setCached(Box(value: result), for: key, expiry: expiry)
        }
        return result
    }
"""
        }

        if info.isAsync && info.isThrowing {
            return """
    \(header) {
        try await withRetry(function: \(info.functionLabelLiteral)) {
            try await \(baseCall)
        }
    }
"""
        }

        if info.isAsync {
            return """
    \(header) {
        \(info.returnsVoid ? "" : "let result = ")await \(baseCall)
        \(info.returnsVoid ? "return" : "return result")
    }
"""
        }

        if info.isThrowing {
            return """
    \(header) {
        \(info.returnsVoid ? "" : "let result = ")try \(baseCall)
        \(info.returnsVoid ? "return" : "return result")
    }
"""
        }

        return """
    \(header) {
        \(info.returnsVoid ? "" : "let result = ")\(baseCall)
        \(info.returnsVoid ? "return" : "return result")
    }
"""
    }

    private static func diagnostic(for node: some SyntaxProtocol, kind: APIClientDiagnostic) -> Diagnostic {
        Diagnostic(node: Syntax(node), message: kind)
    }
}

// MARK: - Helpers

private struct MethodInfo {
    let name: String
    let signature: String
    let handlerType: String
    let callParams: String
    let callArgs: String
    let isAsync: Bool
    let isThrowing: Bool
    let returnsVoid: Bool
    let returnType: String
    let keyExpression: String
    let functionLabelLiteral: String
    let cacheOverrideExpr: String?

    init(_ fn: FunctionDeclSyntax) {
        name = fn.name.text
        signature = fn.signature.description.trimmingCharacters(in: .whitespacesAndNewlines)
        isAsync = fn.signature.effectSpecifiers?.asyncSpecifier != nil
        isThrowing = fn.signature.effectSpecifiers?.throwsClause?.throwsSpecifier != nil
        returnType = fn.signature.returnClause?.type.trimmedDescription ?? "Void"
        returnsVoid = returnType == "Void" || returnType == "()"

        let params = fn.signature.parameterClause.parameters

        callParams = params.map { param in
            param.secondName?.text ?? param.firstName.text
        }.joined(separator: ", ")

        callArgs = params.map { param in
            let external = param.firstName.text
            let internalName = param.secondName?.text ?? external
            if external == "_" {
                return internalName
            }
            return "\(external): \(internalName)"
        }.joined(separator: ", ")

        let keyParts = params.map { param in
            let internalName = param.secondName?.text ?? param.firstName.text
            return "String(describing: \(internalName))"
        }
        if keyParts.isEmpty {
            keyExpression = "\"\(name)\""
        } else {
            let joined = keyParts.joined(separator: ", ")
            keyExpression = "\"\(name)|\" + [\(joined)].joined(separator: \"|\")"
        }

        functionLabelLiteral = "\"\(name)\(fn.signature.parameterClause.trimmed())\""

        handlerType = fn.handlerType

        // Parse optional @Cache attribute on method to override cache policy.
        let attrs = fn.attributes
        if let cacheAttr = attrs.compactMap({ $0.as(AttributeSyntax.self) })
            .first(where: { $0.attributeName.trimmedDescription == "Cache" }) {
            cacheOverrideExpr = MethodInfo.cachePolicyExpression(from: cacheAttr)
        } else {
            cacheOverrideExpr = nil
        }
    }

    var returnPrefix: String { returnsVoid ? "" : "return " }
    var callPrefix: String {
        if isAsync {
            return isThrowing ? "try await " : "await "
        }
        return isThrowing ? "try " : ""
    }
}

private extension MethodInfo {
    static func cachePolicyExpression(from attr: AttributeSyntax) -> String {
        guard let arguments = attr.arguments?.as(LabeledExprListSyntax.self) else {
            return "APICachePolicy(enabled: true, ttl: nil)"
        }

        var enabledExpr = "true"
        var ttlExpr = "nil"

        for arg in arguments {
            let label = arg.label?.text ?? ""
            let value = arg.expression.trimmedDescription
            switch label {
            case "enabled":
                enabledExpr = value
            case "ttl":
                ttlExpr = value
            default:
                break
            }
        }

        return "APICachePolicy(enabled: \(enabledExpr), ttl: \(ttlExpr))"
    }
}

private extension FunctionDeclSyntax {
    var handlerType: String {
        let params = signature.parameterClause.parameters.map { $0.type.trimmedDescription }.joined(separator: ", ")
        let asyncPart = signature.effectSpecifiers?.asyncSpecifier != nil ? " async" : ""
        let throwsPart = signature.effectSpecifiers?.throwsClause?.throwsSpecifier != nil ? " throws" : ""
        let returnType = signature.returnClause?.type.trimmedDescription ?? "Void"
        return "(\(params))\(asyncPart)\(throwsPart) -> \(returnType)"
    }
}

private extension FunctionSignatureSyntax {
    var isAsync: Bool { effectSpecifiers?.asyncSpecifier != nil }
}

private extension TypeSyntax {
    var trimmedDescription: String { description.trimmingCharacters(in: .whitespacesAndNewlines) }
}

private extension FunctionParameterClauseSyntax {
    func trimmed() -> String {
        description.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
