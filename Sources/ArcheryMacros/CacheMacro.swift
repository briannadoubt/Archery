import SwiftSyntax
import SwiftSyntaxMacros

/// Marker macro used to annotate APIClient endpoints with cache overrides.
/// No code is emitted; the presence + arguments are inspected by APIClientMacro.
public enum CacheMacro: PeerMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingPeersOf decl: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        // No-op expansion; APIClientMacro inspects the attribute directly.
        return []
    }
}
