import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

// MARK: - @QuerySources Macro

/// Macro that marks a type as a query source provider.
///
/// This macro adds conformance to the `QuerySourceProvider` protocol,
/// enabling the type to be registered with `QuerySourceRegistry` and
/// used with keypath-based `@Query` property wrappers.
///
/// Example:
/// ```swift
/// @QuerySources
/// struct TaskSources {
///     let api: TasksAPIProtocol
///
///     var all: QuerySource<Task> {
///         QuerySource(Task.all().order(by: .createdAt))
///             .remote { try await api.fetchAll() }
///             .cache(.staleWhileRevalidate(staleAfter: .minutes(5)))
///     }
/// }
/// ```
public enum QuerySourcesMacro: ExtensionMacro {
    public static func expansion(
        of attribute: AttributeSyntax,
        attachedTo declaration: some DeclGroupSyntax,
        providingExtensionsOf type: some TypeSyntaxProtocol,
        conformingTo protocols: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [ExtensionDeclSyntax] {
        // Validate: can only be applied to structs or classes
        let isValidTarget = declaration.is(StructDeclSyntax.self) || declaration.is(ClassDeclSyntax.self)
        guard isValidTarget else {
            throw QuerySourcesMacroError.invalidTarget
        }

        // Generate extension with QuerySourceProvider conformance
        let extensionDecl = DeclSyntax(stringLiteral: "extension \(type.trimmedDescription): QuerySourceProvider {}")

        guard let result = extensionDecl.as(ExtensionDeclSyntax.self) else {
            return []
        }

        return [result]
    }
}

// MARK: - Errors

enum QuerySourcesMacroError: Error, CustomStringConvertible {
    case invalidTarget

    var description: String {
        switch self {
        case .invalidTarget:
            return "@QuerySources can only be applied to structs or classes"
        }
    }
}
