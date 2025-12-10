import Foundation

// @Authenticated macro adds authentication requirements to types and functions.
// For classes/structs: adds authRequirement static property and checkAuthentication method
// For functions: wraps the function with an authentication guard
@attached(member, names: named(authRequirement), named(checkAuthentication))
public macro Authenticated(scope: String? = nil) = #externalMacro(
    module: "ArcheryMacros",
    type: "AuthenticatedMacro"
)