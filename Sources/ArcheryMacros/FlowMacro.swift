import SwiftCompilerPlugin
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

// MARK: - @Flow Macro

/// Macro that generates NavigationFlow conformance for enum types.
///
/// Usage:
/// ```swift
/// @Flow(path: "onboarding", persists: true)
/// enum OnboardingFlow {
///     case welcome
///     case permissions
///     case accountSetup
///     case complete
///
///     @branch(replacing: .accountSetup, when: .hasExistingAccount)
///     case signIn
///
///     @skip(when: .permissionsAlreadyGranted)
///     case permissions
/// }
/// ```
///
/// Generates:
/// - NavigationFlow protocol conformance
/// - `flowPath` static property
/// - `persists` static property
/// - `steps` computed property accounting for branches
/// - `flowConfiguration` static property with branch/skip info
public struct FlowMacro: ExtensionMacro {
    public static func expansion(
        of node: AttributeSyntax,
        attachedTo declaration: some DeclGroupSyntax,
        providingExtensionsOf type: some TypeSyntaxProtocol,
        conformingTo protocols: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [ExtensionDeclSyntax] {
        guard let enumDecl = declaration.as(EnumDeclSyntax.self) else {
            throw FlowMacroError.mustBeEnum
        }

        // Extract macro arguments
        let config = extractFlowConfig(from: node)
        let flowPath = config.path
        let persists = config.persists

        // Extract cases and their attributes
        let caseInfos = extractCaseInfos(from: enumDecl)
        let regularCases = caseInfos.filter { $0.branch == nil && $0.skip == nil }
        let branchCases = caseInfos.filter { $0.branch != nil }
        let skipCases = caseInfos.filter { $0.skip != nil }

        // Generate steps array (regular cases only)
        let stepsArray = regularCases.map { ".\($0.name)" }.joined(separator: ", ")

        // Generate branch configurations
        let branchConfigs = branchCases.compactMap { info -> String? in
            guard let branch = info.branch else { return nil }
            return """
                FlowBranch(replacing: "\(branch.replacing)", with: "\(info.name)", when: "\(branch.condition)")
            """
        }.joined(separator: ",\n            ")

        // Generate skip configurations
        let skipConfigs = skipCases.compactMap { info -> String? in
            guard let skip = info.skip else { return nil }
            return """
                FlowSkipCondition(step: "\(info.name)", when: "\(skip.condition)")
            """
        }.joined(separator: ",\n            ")

        let branchArray = branchConfigs.isEmpty ? "[]" : "[\n            \(branchConfigs)\n        ]"
        let skipArray = skipConfigs.isEmpty ? "[]" : "[\n            \(skipConfigs)\n        ]"

        // Generate extension
        let extensionDecl: DeclSyntax = """
        extension \(type.trimmed): NavigationFlow {
            public static var flowPath: String { "\(raw: flowPath)" }

            public static var persists: Bool { \(raw: persists) }

            public static var steps: [Self] { [\(raw: stepsArray)] }

            public static var flowConfiguration: FlowConfiguration {
                FlowConfiguration(
                    flowPath: flowPath,
                    persists: persists,
                    steps: steps.map(\\.stepPath),
                    branches: \(raw: branchArray),
                    skipConditions: \(raw: skipArray)
                )
            }
        }
        """

        guard let extensionSyntax = extensionDecl.as(ExtensionDeclSyntax.self) else {
            return []
        }

        return [extensionSyntax]
    }
}

// MARK: - Flow Macro Helpers

private struct FlowConfig {
    let path: String
    let persists: Bool
}

private struct CaseInfo {
    let name: String
    let branch: BranchInfo?
    let skip: SkipInfo?
}

private struct BranchInfo {
    let replacing: String
    let condition: String
}

private struct SkipInfo {
    let condition: String
}

private func extractFlowConfig(from node: AttributeSyntax) -> FlowConfig {
    var path = "flow"
    var persists = false

    if let args = node.arguments?.as(LabeledExprListSyntax.self) {
        for arg in args {
            let label = arg.label?.text

            if label == "path" || label == nil {
                if let stringLiteral = arg.expression.as(StringLiteralExprSyntax.self),
                   let segment = stringLiteral.segments.first?.as(StringSegmentSyntax.self) {
                    path = segment.content.text
                }
            } else if label == "persists" {
                if let boolLiteral = arg.expression.as(BooleanLiteralExprSyntax.self) {
                    persists = boolLiteral.literal.tokenKind == .keyword(.true)
                }
            }
        }
    }

    return FlowConfig(path: path, persists: persists)
}

private func extractCaseInfos(from enumDecl: EnumDeclSyntax) -> [CaseInfo] {
    var infos: [CaseInfo] = []

    for member in enumDecl.memberBlock.members {
        guard let caseDecl = member.decl.as(EnumCaseDeclSyntax.self),
              let element = caseDecl.elements.first else { continue }

        let caseName = element.name.text
        var branch: BranchInfo?
        var skip: SkipInfo?

        // Check for @branch attribute
        for attr in caseDecl.attributes {
            guard let attrSyntax = attr.as(AttributeSyntax.self) else { continue }
            let attrName = attrSyntax.attributeName.trimmedDescription

            if attrName == "branch" {
                if let args = attrSyntax.arguments?.as(LabeledExprListSyntax.self) {
                    var replacing = ""
                    var condition = ""

                    for arg in args {
                        let label = arg.label?.text

                        if label == "replacing" {
                            if let memberAccess = arg.expression.as(MemberAccessExprSyntax.self) {
                                replacing = memberAccess.declName.baseName.text
                            }
                        } else if label == "when" {
                            if let memberAccess = arg.expression.as(MemberAccessExprSyntax.self) {
                                condition = memberAccess.declName.baseName.text
                            }
                        }
                    }

                    if !replacing.isEmpty && !condition.isEmpty {
                        branch = BranchInfo(replacing: replacing, condition: condition)
                    }
                }
            } else if attrName == "skip" {
                if let args = attrSyntax.arguments?.as(LabeledExprListSyntax.self) {
                    for arg in args {
                        let label = arg.label?.text
                        if label == "when" {
                            if let memberAccess = arg.expression.as(MemberAccessExprSyntax.self) {
                                skip = SkipInfo(condition: memberAccess.declName.baseName.text)
                            }
                        }
                    }
                }
            }
        }

        infos.append(CaseInfo(name: caseName, branch: branch, skip: skip))
    }

    return infos
}

// MARK: - Errors

enum FlowMacroError: Error, CustomStringConvertible {
    case mustBeEnum

    var description: String {
        switch self {
        case .mustBeEnum:
            return "@Flow can only be applied to enum types"
        }
    }
}
