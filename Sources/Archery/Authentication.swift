import Foundation

@attached(peer, names: arbitrary)
@attached(member, names: named(_authManager), named(init))
public macro Authenticated(scope: String? = nil) = #externalMacro(
    module: "ArcheryMacros",
    type: "AuthenticatedMacro"
)