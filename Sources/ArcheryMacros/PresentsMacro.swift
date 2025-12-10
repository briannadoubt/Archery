import SwiftCompilerPlugin
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

// MARK: - @presents Macro

/// Marker macro for specifying route presentation style.
/// The actual work is done by @Route macro which reads this attribute.
///
/// Usage:
/// ```swift
/// @Route(path: "tasks")
/// enum TasksRoute: NavigationRoute {
///     case list
///
///     @presents(.sheet)
///     case create
///
///     @presents(.sheet, detents: [.medium, .large])
///     case quickAction
///
///     @presents(.fullScreen)
///     case bulkEdit
/// }
/// ```
public struct PresentsMacro: PeerMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingPeersOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        // Marker macro - no code generation
        // @Route macro reads this attribute to determine presentation style
        []
    }
}

// MARK: - Flow Branch/Skip Macros

/// Marker macro for flow branching.
/// The actual work is done by @Flow macro which reads this attribute.
public struct FlowBranchMacro: PeerMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingPeersOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        // Marker macro - no code generation
        []
    }
}

/// Marker macro for flow step skipping.
/// The actual work is done by @Flow macro which reads this attribute.
public struct FlowSkipMacro: PeerMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingPeersOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        // Marker macro - no code generation
        []
    }
}
