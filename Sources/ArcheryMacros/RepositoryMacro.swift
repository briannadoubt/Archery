import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

enum RepositoryDiagnostic: String, DiagnosticMessage {
    case mustBeClass

    var message: String {
        switch self {
        case .mustBeClass: return "@Repository can only be applied to a class"
        }
    }

    var diagnosticID: MessageID { .init(domain: "ArcheryMacros", id: rawValue) }
    var severity: DiagnosticSeverity { .error }
}

private struct RepositoryAsyncDiagnostic: DiagnosticMessage {
    let method: String

    var message: String { "@Repository methods must be async: \(method)" }
    var diagnosticID: MessageID { .init(domain: "ArcheryMacros", id: "mustBeAsync") }
    var severity: DiagnosticSeverity { .warning }
}

public enum RepositoryMacro: PeerMacro {
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
            context.diagnose(Diagnostic(node: Syntax(method), message: RepositoryAsyncDiagnostic(method: method.name.text)))
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
        enableCaching: Bool = false,
        enableCoalescing: Bool = false,
        enableTracing: Bool = false,
        traceHandler: RepositoryTraceHandler? = nil
    ) -> \(protocolName) {
        \(liveName)(
            baseFactory: { \(className)() },
            enableCaching: enableCaching,
            enableCoalescing: enableCoalescing,
            enableTracing: enableTracing,
            traceHandler: traceHandler
        )
    }

    static func make(
        in container: EnvContainer,
        enableCaching: Bool = false,
        enableCoalescing: Bool = false,
        enableTracing: Bool = false,
        traceHandler: RepositoryTraceHandler? = nil
    ) -> \(protocolName) {
        if let cached: \(protocolName) = container.resolve() {
            return cached
        }
        let repo = live(
            enableCaching: enableCaching,
            enableCoalescing: enableCoalescing,
            enableTracing: enableTracing,
            traceHandler: traceHandler
        )
        container.register(repo as \(protocolName))
        return repo
    }

    static func makeChild(
        from container: EnvContainer,
        enableCaching: Bool = false,
        enableCoalescing: Bool = false,
        enableTracing: Bool = false,
        traceHandler: RepositoryTraceHandler? = nil
    ) -> \(protocolName) {
        let child = EnvContainer()
        container.merge(into: child)
        let repo = live(
            enableCaching: enableCaching,
            enableCoalescing: enableCoalescing,
            enableTracing: enableTracing,
            traceHandler: traceHandler
        )
        child.register(repo as \(protocolName))
        return repo
    }
"""

        let liveDecl = """

\(access)final class \(liveName): \(protocolName), @unchecked Sendable {
    private let base: BaseBox
    private let enableCaching: Bool
    private let enableCoalescing: Bool
    private let enableTracing: Bool
    private let traceHandler: RepositoryTraceHandler?
    struct BaseBox: @unchecked Sendable {
        let value: \(className)
    }
    struct Box: @unchecked Sendable {
        let value: Any
    }
    private let state = State()
    private let clock = ContinuousClock()

    actor State {
        private var cache: [String: Box] = [:]
        private var inflight: [String: Task<Box, Error>] = [:]

        func cachedValue(for key: String) -> Box? {
            cache[key]
        }
        func setCached(_ value: Box, for key: String) {
            cache[key] = value
        }
        func inflightTask(for key: String) -> Task<Box, Error>? {
            inflight[key]
        }
        func inflightOrCreate(for key: String, make: () -> Task<Box, Error>) -> Task<Box, Error> {
            if let existing = inflight[key] { return existing }
            let task = make()
            inflight[key] = task
            return task
        }
        func clearInflight(for key: String) {
            inflight[key] = nil
        }
    }

    \(access)init(
        baseFactory: @escaping () -> \(className) = { \(className)() },
        enableCaching: Bool = false,
        enableCoalescing: Bool = false,
        enableTracing: Bool = false,
        traceHandler: RepositoryTraceHandler? = nil
    ) {
        self.base = BaseBox(value: baseFactory())
        self.enableCaching = enableCaching
        self.enableCoalescing = enableCoalescing
        self.enableTracing = enableTracing
        self.traceHandler = traceHandler
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
        let baseCall = "base.value.\(info.name)(\(info.callArgs))"

        // Async + throwing + returning value -> caching & coalescing path.
        if info.isAsync && info.isThrowing && !info.returnsVoid {
            return """
    \(header) {
        let key = \(info.keyExpression)
        if enableCaching, let cached = await state.cachedValue(for: key)?.value as? \(info.returnType) {
            if enableTracing {
                let now = clock.now
                traceHandler?(RepositoryTraceEvent(
                    function: \(info.functionLabelLiteral),
                    key: key,
                    start: now,
                    end: now,
                    duration: .zero,
                    cacheHit: true,
                    coalesced: false,
                    error: nil,
                    metadata: nil
                ))
            }
            return cached
        }
        let start = enableTracing ? clock.now : nil
        let task: Task<Box, Error>

        if enableCoalescing {
            task = await state.inflightOrCreate(for: key) {
                Task<Box, Error> {
                    do {
                        let result = try await \(baseCall)
                        if enableCaching {
                            await state.setCached(Box(value: result), for: key)
                        }
                        if let start = start, enableTracing {
                            let end = clock.now
                            traceHandler?(RepositoryTraceEvent(
                                function: \(info.functionLabelLiteral),
                                key: key,
                                start: start,
                                end: end,
                                duration: start.duration(to: end),
                                cacheHit: false,
                                coalesced: false,
                                error: nil,
                                metadata: nil
                            ))
                        }
                        return Box(value: result)
                    } catch {
                        if let start = start, enableTracing {
                            let end = clock.now
                            traceHandler?(RepositoryTraceEvent(
                                function: \(info.functionLabelLiteral),
                                key: key,
                                start: start,
                                end: end,
                                duration: start.duration(to: end),
                                cacheHit: false,
                                coalesced: false,
                                error: error,
                                metadata: nil
                            ))
                        }
                        throw normalizeRepositoryError(error, function: \(info.functionLabelLiteral), file: #fileID, line: #line)
                    }
                }
            }
        } else {
            task = Task<Box, Error> {
                do {
                    let result = try await \(baseCall)
                    if enableCaching {
                        await state.setCached(Box(value: result), for: key)
                    }
                    if let start = start, enableTracing {
                        let end = clock.now
                        traceHandler?(RepositoryTraceEvent(
                            function: \(info.functionLabelLiteral),
                            key: key,
                            start: start,
                            end: end,
                            duration: start.duration(to: end),
                            cacheHit: false,
                            coalesced: false,
                            error: nil,
                            metadata: nil
                        ))
                    }
                    return Box(value: result)
                } catch {
                    if let start = start, enableTracing {
                        let end = clock.now
                        traceHandler?(RepositoryTraceEvent(
                            function: \(info.functionLabelLiteral),
                            key: key,
                            start: start,
                            end: end,
                            duration: start.duration(to: end),
                            cacheHit: false,
                            coalesced: false,
                            error: error,
                            metadata: nil
                        ))
                    }
                    throw normalizeRepositoryError(error, function: \(info.functionLabelLiteral), file: #fileID, line: #line)
                }
            }
        }

        let value = try await task.result.get()

        if enableCoalescing {
            await state.clearInflight(for: key)
        }

        guard let typed = value.value as? \(info.returnType) else {
            throw RepositoryError.decodingFailed
        }
        return typed
    }
"""
        }

        // Async fallback (no caching/coalescing)
        if info.isAsync {
            if info.isThrowing {
                return """
    \(header) {
        let start = enableTracing ? clock.now : nil
        do {
            let result = try await \(baseCall)
            if let start = start, enableTracing {
                let end = clock.now
                traceHandler?(RepositoryTraceEvent(
                    function: \(info.functionLabelLiteral),
                    key: nil,
                    start: start,
                    end: end,
                    duration: start.duration(to: end),
                    cacheHit: false,
                    coalesced: false,
                    error: nil
                ))
            }
            \(info.returnsVoid ? "return" : "return result")
        } catch {
            if let start = start, enableTracing {
                let end = clock.now
                traceHandler?(RepositoryTraceEvent(
                    function: \(info.functionLabelLiteral),
                    key: nil,
                    start: start,
                    end: end,
                    duration: start.duration(to: end),
                    cacheHit: false,
                    coalesced: false,
                    error: error
                ))
            }
            throw normalizeRepositoryError(error, function: \(info.functionLabelLiteral), file: #fileID, line: #line)
        }
    }
"""
            }

            return """
    \(header) {
        let start = enableTracing ? clock.now : nil
        \(info.returnsVoid ? "" : "let result = ")await \(baseCall)
        if let start = start, enableTracing {
            let end = clock.now
            traceHandler?(RepositoryTraceEvent(
                function: \(info.functionLabelLiteral),
                key: nil,
                start: start,
                end: end,
                duration: start.duration(to: end),
                cacheHit: false,
                coalesced: false,
                error: nil
            ))
        }
        \(info.returnsVoid ? "return" : "return result")
    }
"""
        }

        // Synchronous path
        if info.isThrowing {
            return """
    \(header) {
        let start = enableTracing ? clock.now : nil
        do {
            let result = try \(baseCall)
            if let start = start, enableTracing {
                let end = clock.now
                traceHandler?(RepositoryTraceEvent(
                    function: \(info.functionLabelLiteral),
                    key: nil,
                    start: start,
                    end: end,
                    duration: start.duration(to: end),
                    cacheHit: false,
                    coalesced: false,
                    error: nil
                ))
            }
            \(info.returnsVoid ? "return" : "return result")
        } catch {
            if let start = start, enableTracing {
                let end = clock.now
                traceHandler?(RepositoryTraceEvent(
                    function: \(info.functionLabelLiteral),
                    key: nil,
                    start: start,
                    end: end,
                    duration: start.duration(to: end),
                    cacheHit: false,
                    coalesced: false,
                    error: error
                ))
            }
            throw normalizeRepositoryError(error, function: \(info.functionLabelLiteral), file: #fileID, line: #line)
        }
    }
"""
        }

        return """
    \(header) {
        let start = enableTracing ? clock.now : nil
        \(info.returnsVoid ? "" : "let result = ")\(baseCall)
        if let start = start, enableTracing {
            let end = clock.now
            traceHandler?(RepositoryTraceEvent(
                function: \(info.functionLabelLiteral),
                key: nil,
                start: start,
                end: end,
                duration: start.duration(to: end),
                cacheHit: false,
                coalesced: false,
                error: nil
            ))
        }
        \(info.returnsVoid ? "return" : "return result")
    }
"""
    }

    private static func diagnostic(for node: some SyntaxProtocol, kind: RepositoryDiagnostic) -> Diagnostic {
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
    }

    var returnPrefix: String { returnsVoid ? "" : "return " }
    var callPrefix: String {
        if isAsync {
            return isThrowing ? "try await " : "await "
        }
        return isThrowing ? "try " : ""
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
