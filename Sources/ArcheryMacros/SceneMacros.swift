import SwiftCompilerPlugin
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

// MARK: - @Window Macro

/// Marker macro for window scene definitions.
/// The @AppShell macro reads this to generate WindowGroup scenes.
///
/// Usage:
/// ```swift
/// @AppShell
/// struct MyApp: App {
///     @Window(id: "preferences", title: "Preferences")
///     enum PreferencesScene {
///         case general
///         case accounts
///     }
/// }
/// ```
public struct WindowSceneMacro: PeerMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingPeersOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        // Marker macro - @AppShell reads this attribute
        []
    }
}

// MARK: - @ImmersiveSpace Macro

/// Marker macro for immersive space scene definitions (visionOS).
/// The @AppShell macro reads this to generate ImmersiveSpace scenes.
///
/// Usage:
/// ```swift
/// @AppShell
/// struct MyApp: App {
///     @ImmersiveSpace(id: "viewer", style: .mixed)
///     enum ViewerSpace {
///         case model(id: String)
///     }
/// }
/// ```
public struct ImmersiveSpaceMacro: PeerMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingPeersOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        // Marker macro - @AppShell reads this attribute
        []
    }
}

// MARK: - @Settings Macro

/// Marker macro for settings scene definitions (macOS).
/// The @AppShell macro reads this to generate Settings scenes.
///
/// Usage:
/// ```swift
/// @AppShell
/// struct MyApp: App {
///     @Settings
///     enum AppSettings {
///         case general
///         case advanced
///     }
/// }
/// ```
public struct SettingsSceneMacro: PeerMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingPeersOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        // Marker macro - @AppShell reads this attribute
        []
    }
}

// MARK: - Scene Info Extraction Helpers

/// Information about a Window scene
struct WindowSceneInfo {
    let enumName: String
    let id: String
    let title: String?
    let cases: [(name: String, params: [String])]
}

/// Information about an ImmersiveSpace scene
struct ImmersiveSpaceSceneInfo {
    let enumName: String
    let id: String
    let style: String
    let cases: [(name: String, params: [String])]
}

/// Information about a Settings scene
struct SettingsSceneInfo {
    let enumName: String
    let cases: [(name: String, params: [String])]
}

/// Extract Window scene info from an enum declaration with @Window attribute
func extractWindowSceneInfo(from enumDecl: EnumDeclSyntax) -> WindowSceneInfo? {
    var id: String?
    var title: String?

    for attr in enumDecl.attributes {
        guard let attrSyntax = attr.as(AttributeSyntax.self),
              attrSyntax.attributeName.trimmedDescription == "Window" else { continue }

        if let args = attrSyntax.arguments?.as(LabeledExprListSyntax.self) {
            for arg in args {
                let label = arg.label?.text

                if label == "id" || label == nil {
                    if let stringLiteral = arg.expression.as(StringLiteralExprSyntax.self),
                       let segment = stringLiteral.segments.first?.as(StringSegmentSyntax.self) {
                        id = segment.content.text
                    }
                } else if label == "title" {
                    if let stringLiteral = arg.expression.as(StringLiteralExprSyntax.self),
                       let segment = stringLiteral.segments.first?.as(StringSegmentSyntax.self) {
                        title = segment.content.text
                    }
                }
            }
        }
    }

    guard let windowId = id else { return nil }

    let cases = enumDecl.memberBlock.members.compactMap { member -> (String, [String])? in
        guard let caseDecl = member.decl.as(EnumCaseDeclSyntax.self),
              let element = caseDecl.elements.first else { return nil }
        let params = element.parameterClause?.parameters.map { $0.firstName?.text ?? "_" } ?? []
        return (element.name.text, params)
    }

    return WindowSceneInfo(
        enumName: enumDecl.name.text,
        id: windowId,
        title: title,
        cases: cases
    )
}

/// Extract ImmersiveSpace scene info from an enum declaration with @ImmersiveSpace attribute
func extractImmersiveSpaceSceneInfo(from enumDecl: EnumDeclSyntax) -> ImmersiveSpaceSceneInfo? {
    var id: String?
    var style: String = "mixed"

    for attr in enumDecl.attributes {
        guard let attrSyntax = attr.as(AttributeSyntax.self),
              attrSyntax.attributeName.trimmedDescription == "ImmersiveSpace" else { continue }

        if let args = attrSyntax.arguments?.as(LabeledExprListSyntax.self) {
            for arg in args {
                let label = arg.label?.text

                if label == "id" || label == nil {
                    if let stringLiteral = arg.expression.as(StringLiteralExprSyntax.self),
                       let segment = stringLiteral.segments.first?.as(StringSegmentSyntax.self) {
                        id = segment.content.text
                    }
                } else if label == "style" {
                    if let memberAccess = arg.expression.as(MemberAccessExprSyntax.self) {
                        style = memberAccess.declName.baseName.text
                    }
                }
            }
        }
    }

    guard let spaceId = id else { return nil }

    let cases = enumDecl.memberBlock.members.compactMap { member -> (String, [String])? in
        guard let caseDecl = member.decl.as(EnumCaseDeclSyntax.self),
              let element = caseDecl.elements.first else { return nil }
        let params = element.parameterClause?.parameters.map { $0.firstName?.text ?? "_" } ?? []
        return (element.name.text, params)
    }

    return ImmersiveSpaceSceneInfo(
        enumName: enumDecl.name.text,
        id: spaceId,
        style: style,
        cases: cases
    )
}

/// Extract Settings scene info from an enum declaration with @Settings attribute
func extractSettingsSceneInfo(from enumDecl: EnumDeclSyntax) -> SettingsSceneInfo? {
    let hasSettingsAttr = enumDecl.attributes.contains { attr in
        guard let attrSyntax = attr.as(AttributeSyntax.self) else { return false }
        return attrSyntax.attributeName.trimmedDescription == "Settings"
    }

    guard hasSettingsAttr else { return nil }

    let cases = enumDecl.memberBlock.members.compactMap { member -> (String, [String])? in
        guard let caseDecl = member.decl.as(EnumCaseDeclSyntax.self),
              let element = caseDecl.elements.first else { return nil }
        let params = element.parameterClause?.parameters.map { $0.firstName?.text ?? "_" } ?? []
        return (element.name.text, params)
    }

    return SettingsSceneInfo(enumName: enumDecl.name.text, cases: cases)
}
