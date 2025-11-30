import SwiftCompilerPlugin
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

public struct AuthenticatedMacro: PeerMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingPeersOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        let scope = extractScope(from: node)
        
        if let classDecl = declaration.as(ClassDeclSyntax.self) {
            return try expandForClass(classDecl, scope: scope, in: context)
        } else if let funcDecl = declaration.as(FunctionDeclSyntax.self) {
            return try expandForFunction(funcDecl, scope: scope, in: context)
        } else if let structDecl = declaration.as(StructDeclSyntax.self) {
            return try expandForStruct(structDecl, scope: scope, in: context)
        }
        
        return []
    }
    
    private static func extractScope(from node: AttributeSyntax) -> String? {
        guard let arguments = node.arguments?.as(LabeledExprListSyntax.self) else {
            return nil
        }
        
        for argument in arguments {
            if argument.label?.text == "scope",
               let stringLiteral = argument.expression.as(StringLiteralExprSyntax.self),
               let segment = stringLiteral.segments.first?.as(StringSegmentSyntax.self) {
                return segment.content.text
            }
        }
        
        return nil
    }
    
    private static func expandForClass(
        _ classDecl: ClassDeclSyntax,
        scope: String?,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        let className = classDecl.name.text
        let authRequirement: String
        
        if let scope = scope {
            authRequirement = ".requiredWithScope(\"\(scope)\")"
        } else {
            authRequirement = ".required"
        }
        
        let authExtension = """
        extension \(className) {
            static let authRequirement: AuthRequirement = \(authRequirement)
            
            @MainActor
            func checkAuthentication(with manager: AuthenticationManager) throws {
                guard Self.authRequirement.isSatisfied(by: manager.state) else {
                    throw AuthError.notAuthenticated
                }
            }
        }
        """
        
        return [DeclSyntax(stringLiteral: authExtension)]
    }
    
    private static func expandForFunction(
        _ funcDecl: FunctionDeclSyntax,
        scope: String?,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        let funcName = funcDecl.name.text
        let authRequirement: String
        
        if let scope = scope {
            authRequirement = ".requiredWithScope(\"\(scope)\")"
        } else {
            authRequirement = ".required"
        }
        
        let guardedFuncName = "_authenticated_\(funcName)"
        var guardedFunc = funcDecl
        guardedFunc.name = .identifier(guardedFuncName)
        
        let originalParams = funcDecl.signature.parameterClause.parameters
        let paramCall = originalParams.map { param in
            let paramName = param.secondName?.text ?? param.firstName.text
            if param.firstName.text != "_" {
                return "\(param.firstName.text): \(paramName)"
            } else {
                return paramName
            }
        }.joined(separator: ", ")
        
        let isAsync = funcDecl.signature.effectSpecifiers?.asyncSpecifier != nil
        let isThrowing = funcDecl.signature.effectSpecifiers != nil && 
                         funcDecl.signature.effectSpecifiers?.description.contains("throws") == true
        
        let authCheckCode = """
        @available(*, deprecated, message: "Use authenticated version")
        \(funcDecl.modifiers)\(funcDecl.signature) {
            guard let authManager = ProcessInfo.processInfo.environment["AUTH_MANAGER"] as? AuthenticationManager else {
                fatalError("AuthenticationManager not found in environment")
            }
            
            let requirement: AuthRequirement = \(authRequirement)
            guard requirement.isSatisfied(by: authManager.state) else {
                \(isThrowing ? "throw AuthError.notAuthenticated" : "fatalError(\"Authentication required\")")
            }
            
            \(isAsync ? "return await" : "return") \(guardedFuncName)(\(paramCall))
        }
        """
        
        return [
            DeclSyntax(guardedFunc),
            DeclSyntax(stringLiteral: authCheckCode)
        ]
    }
    
    private static func expandForStruct(
        _ structDecl: StructDeclSyntax,
        scope: String?,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        let structName = structDecl.name.text
        let authRequirement: String
        
        if let scope = scope {
            authRequirement = ".requiredWithScope(\"\(scope)\")"
        } else {
            authRequirement = ".required"
        }
        
        let authExtension = """
        extension \(structName) {
            static let authRequirement: AuthRequirement = \(authRequirement)
            
            func checkAuthentication(with manager: AuthenticationManager) throws {
                guard Self.authRequirement.isSatisfied(by: manager.state) else {
                    throw AuthError.notAuthenticated
                }
            }
        }
        """
        
        return [DeclSyntax(stringLiteral: authExtension)]
    }
}

extension AuthenticatedMacro: MemberMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingMembersOf declaration: some DeclGroupSyntax,
        conformingTo protocols: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        let scope = extractScope(from: node)
        let authRequirement: String
        
        if let scope = scope {
            authRequirement = ".requiredWithScope(\"\(scope)\")"
        } else {
            authRequirement = ".required"
        }
        
        return [
            DeclSyntax(stringLiteral: """
            private let _authManager: AuthenticationManager?
            
            init(authManager: AuthenticationManager? = nil) {
                self._authManager = authManager
                super.init()
                
                if let authManager = authManager ?? ProcessInfo.processInfo.environment["AUTH_MANAGER"] as? AuthenticationManager {
                    let requirement: AuthRequirement = \(authRequirement)
                    if !requirement.isSatisfied(by: authManager.state) {
                        fatalError("Authentication required with requirement: \\(requirement)")
                    }
                }
            }
            """)
        ]
    }
}