import Foundation
import SwiftUI

// MARK: - Form Macro

@attached(member, names: named(formContainer), named(formFields), named(validate), named(submit), named(reset))
public macro Form() = #externalMacro(
    module: "ArcheryMacros",
    type: "FormMacro"
)

// MARK: - Field Attribute Macros

@attached(peer)
public macro Required() = #externalMacro(module: "ArcheryMacros", type: "RequiredMacro")

@attached(peer)
public macro Label(_ text: String) = #externalMacro(module: "ArcheryMacros", type: "LabelMacro")

@attached(peer)
public macro Placeholder(_ text: String) = #externalMacro(module: "ArcheryMacros", type: "PlaceholderMacro")

@attached(peer)
public macro HelpText(_ text: String) = #externalMacro(module: "ArcheryMacros", type: "HelpTextMacro")

@attached(peer)
public macro Email() = #externalMacro(module: "ArcheryMacros", type: "EmailMacro")

@attached(peer)
public macro URL() = #externalMacro(module: "ArcheryMacros", type: "URLMacro")

@attached(peer)
public macro Phone() = #externalMacro(module: "ArcheryMacros", type: "PhoneMacro")

@attached(peer)
public macro MinLength(_ length: Int) = #externalMacro(module: "ArcheryMacros", type: "MinLengthMacro")

@attached(peer)
public macro MaxLength(_ length: Int) = #externalMacro(module: "ArcheryMacros", type: "MaxLengthMacro")