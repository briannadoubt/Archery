import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

enum ObservableViewModelDiagnostic: String, DiagnosticMessage {
    case mustBeClass
    case mustBeMainActor
    case mustConformToResettable

    var message: String {
        switch self {
        case .mustBeClass: return "@ObservableViewModel can only be applied to a class"
        case .mustBeMainActor: return "@ObservableViewModel requires the class to be annotated with @MainActor"
        case .mustConformToResettable: return "@ObservableViewModel requires the class to conform to Resettable"
        }
    }
    var diagnosticID: MessageID { .init(domain: "ArcheryMacros", id: rawValue) }
    var severity: DiagnosticSeverity { .error }
}

public enum ObservableViewModelMacro: MemberMacro, MemberAttributeMacro, ExtensionMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingMembersOf declaration: some DeclGroupSyntax,
        conformingTo _: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        guard let classDecl = declaration.as(ClassDeclSyntax.self) else {
            throw DiagnosticsError(diagnostics: [diagnostic(for: declaration, kind: .mustBeClass)])
        }

        var diagnostics: [Diagnostic] = []

        if !classDecl.isMainActorAnnotated {
            diagnostics.append(diagnostic(for: declaration, kind: .mustBeMainActor))
        }

        if !classDecl.conformsToResettable {
            diagnostics.append(diagnostic(for: declaration, kind: .mustConformToResettable))
        }

        if !diagnostics.isEmpty {
            throw DiagnosticsError(diagnostics: diagnostics)
        }

        let className = classDecl.name.text

        let resetDecl = """
@MainActor
func reset() {
    cancelTrackedTasks()
}
"""

        // Note: We no longer generate custom observation code.
        // The class should use @Observable macro from Swift's Observation framework.
        // This macro focuses on lifecycle management, debounce/throttle, and load state helpers.

        let hasAsyncLoad = classDecl.hasAsyncLoadMethod
        let willGenerateLoadStub = !hasAsyncLoad

        let onAppearDecl: String = """
@MainActor
func onAppear() {
    cancelTrackedTasks()
    let task = _Concurrency.Task { @MainActor in
        await load()
    }
    track(CancelableTask { task.cancel() })
}
"""

        let onDisappearDecl = """
@MainActor
func onDisappear() {
    cancelTrackedTasks()
}
"""

        let trackDecl = """
@MainActor
func track(_ task: CancelableTask) {
    __archeryCancelables.append(task)
}
"""

        let cancelDecl = """
@MainActor
func cancelTrackedTasks() {
    __archeryCancelables.forEach { $0.cancel() }
    __archeryCancelables.removeAll()
}
"""

        let debounceStorageDecl = """
@MainActor
private var __archeryDebounceTasks: [AnyHashable: _Concurrency.Task<Void, Never>] = [:]
"""

        let throttleStorageDecl = """
@MainActor
private var __archeryThrottleTasks: [AnyHashable: _Concurrency.Task<Void, Never>] = [:]
"""

        let debounceDecl = """
@MainActor
func debounce(
    id: AnyHashable = #function,
    dueTime: Duration,
    action: @escaping @Sendable () async -> Void
) {
    __archeryDebounceTasks[id]?.cancel()
    let task = _Concurrency.Task { @MainActor in
        try? await _Concurrency.Task.sleep(for: dueTime)
        guard !_Concurrency.Task.isCancelled else { return }
        await action()
    }
    __archeryDebounceTasks[id] = task
    track(CancelableTask { task.cancel() })
}
"""

        let throttleDecl = """
@MainActor
func throttle(
    id: AnyHashable = #function,
    interval: Duration,
    action: @escaping @Sendable () async -> Void
) {
    if let existing = __archeryThrottleTasks[id], !existing.isCancelled {
        return
    }

    let task = _Concurrency.Task { @MainActor in
        defer { __archeryThrottleTasks[id] = nil }
        await action()
        try? await _Concurrency.Task.sleep(for: interval)
    }

    __archeryThrottleTasks[id] = task
    track(CancelableTask { task.cancel() })
}
"""

        let beginLoadingDecl = """
@MainActor
func beginLoading<Value>(_ keyPath: ReferenceWritableKeyPath<\(className), LoadState<Value>>) {
    self[keyPath: keyPath] = .loading
}
"""

        let endSuccessDecl = """
@MainActor
func endSuccess<Value>(_ keyPath: ReferenceWritableKeyPath<\(className), LoadState<Value>>, value: Value) {
    self[keyPath: keyPath] = .success(value)
}
"""

        let endFailureDecl = """
@MainActor
func endFailure<Value>(_ keyPath: ReferenceWritableKeyPath<\(className), LoadState<Value>>, error: Error) {
    self[keyPath: keyPath] = .failure(error)
}
"""

        let setIdleDecl = """
@MainActor
func setIdle<Value>(_ keyPath: ReferenceWritableKeyPath<\(className), LoadState<Value>>) {
    self[keyPath: keyPath] = .idle
}
"""

        let storageDecl = """
@MainActor
private var __archeryCancelables: [CancelableTask] = []
"""

        let loadStubDecl = """
@MainActor
func load() async {}
"""

        var members: [DeclSyntax] = [
            DeclSyntax(stringLiteral: storageDecl),
            DeclSyntax(stringLiteral: debounceStorageDecl),
            DeclSyntax(stringLiteral: throttleStorageDecl),
            DeclSyntax(stringLiteral: trackDecl),
            DeclSyntax(stringLiteral: cancelDecl),
            DeclSyntax(stringLiteral: resetDecl),
            DeclSyntax(stringLiteral: onAppearDecl),
            DeclSyntax(stringLiteral: onDisappearDecl),
            DeclSyntax(stringLiteral: debounceDecl),
            DeclSyntax(stringLiteral: throttleDecl),
            DeclSyntax(stringLiteral: beginLoadingDecl),
            DeclSyntax(stringLiteral: endSuccessDecl),
            DeclSyntax(stringLiteral: endFailureDecl),
            DeclSyntax(stringLiteral: setIdleDecl)
        ]

        if willGenerateLoadStub {
            members.append(DeclSyntax(stringLiteral: loadStubDecl))
        }

        return members
    }

    private static func diagnostic(for node: some SyntaxProtocol, kind: ObservableViewModelDiagnostic) -> Diagnostic {
        Diagnostic(node: Syntax(node), message: kind)
    }
}

private extension ClassDeclSyntax {
    var isMainActorAnnotated: Bool {
        attributes.contains(where: { element in
            guard let attr = element.as(AttributeSyntax.self) else { return false }
            return attr.attributeName.as(IdentifierTypeSyntax.self)?.name.text == "MainActor"
        })
    }

    var conformsToResettable: Bool {
        guard let inheritance = inheritanceClause else { return false }
        return inheritance.inheritedTypes.contains { type in
            type.type.trimmedDescription == "Resettable"
        }
    }

    var hasAsyncLoadMethod: Bool {
        memberBlock.members.contains { member in
            guard let fn = member.decl.as(FunctionDeclSyntax.self) else { return false }
            guard fn.name.text == "load" else { return false }
            let params = fn.signature.parameterClause.parameters
            let isNoParams = params.isEmpty
            let isAsync = fn.signature.effectSpecifiers?.asyncSpecifier != nil
            return isNoParams && isAsync
        }
    }
}

private extension TypeSyntax {
    var trimmedDescription: String { description.trimmingCharacters(in: .whitespacesAndNewlines) }
}



// MARK: - MemberAttributeMacro

extension ObservableViewModelMacro {
    public static func expansion(
        of attribute: AttributeSyntax,
        attachedTo declaration: some DeclGroupSyntax,
        providingAttributesFor member: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [AttributeSyntax] {
        // No longer adding @ObservationTracked - use @Observable macro on class instead
        return []
    }
}

// MARK: - ExtensionMacro

extension ObservableViewModelMacro {
    public static func expansion(
        of attribute: AttributeSyntax,
        attachedTo declaration: some DeclGroupSyntax,
        providingExtensionsOf type: some TypeSyntaxProtocol,
        conformingTo protocols: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [ExtensionDeclSyntax] {
        // Only add ArcheryLoadable conformance
        // User should add @Observable to the class for observation support
        let loadable = DeclSyntax(stringLiteral: "extension \(type.trimmedDescription): ArcheryLoadable {}")
        return [loadable].compactMap { $0.as(ExtensionDeclSyntax.self) }
    }
}
