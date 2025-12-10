import SwiftCompilerPlugin
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros
import SwiftDiagnostics

public struct SharedModelMacro: MemberMacro, ExtensionMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingMembersOf declaration: some DeclGroupSyntax,
        conformingTo protocols: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        guard let structDecl = declaration.as(StructDeclSyntax.self) else {
            throw MacroError.notAStruct
        }
        
        var members: [DeclSyntax] = []
        
        // Parse configuration
        let config = try parseConfiguration(from: node)
        
        // Generate widget-specific members if needed
        if config.supportsWidget {
            members.append(contentsOf: generateWidgetMembers(for: structDecl))
        }
        
        // Generate intent-specific members if needed  
        if config.supportsIntent {
            members.append(contentsOf: generateIntentMembers(for: structDecl))
        }
        
        // Generate Live Activity members if needed
        if config.supportsLiveActivity {
            members.append(contentsOf: generateLiveActivityMembers(for: structDecl))
        }
        
        return members
    }
    
    public static func expansion(
        of node: AttributeSyntax,
        attachedTo declaration: some DeclGroupSyntax,
        providingExtensionsOf type: some TypeSyntaxProtocol,
        conformingTo protocols: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [ExtensionDeclSyntax] {
        guard let structDecl = declaration.as(StructDeclSyntax.self) else {
            throw MacroError.notAStruct
        }
        
        let config = try parseConfiguration(from: node)
        var extensions: [ExtensionDeclSyntax] = []
        
        // Generate TimelineEntry conformance for widgets
        if config.supportsWidget {
            let widgetExtension = try ExtensionDeclSyntax(
                """
                extension \(structDecl.name): TimelineEntry {
                    public var date: Date {
                        timestamp ?? Date()
                    }
                    
                    public var relevance: TimelineEntryRelevance? {
                        guard let score = relevanceScore else { return nil }
                        return TimelineEntryRelevance(score: score)
                    }
                }
                """
            )
            extensions.append(widgetExtension)
        }
        
        // Generate App Intent parameter conformance
        if config.supportsIntent {
            // First generate the EntityQuery struct
            let queryStruct = try ExtensionDeclSyntax(
                """
                extension \(structDecl.name) {
                    public struct Query: EntityQuery {
                        public init() {}

                        public func entities(for identifiers: [String]) async throws -> [\(structDecl.name)] {
                            // Override this in your implementation
                            return []
                        }

                        public func suggestedEntities() async throws -> [\(structDecl.name)] {
                            // Override this in your implementation
                            return []
                        }
                    }
                }
                """
            )
            extensions.append(queryStruct)

            let intentExtension = try ExtensionDeclSyntax(
                """
                extension \(structDecl.name): AppEntity {
                    public static var typeDisplayRepresentation: TypeDisplayRepresentation {
                        TypeDisplayRepresentation(name: "\(structDecl.name)")
                    }

                    public static var defaultQuery: Query { Query() }

                    public var displayRepresentation: DisplayRepresentation {
                        DisplayRepresentation(title: "\\(self.title ?? "Untitled")")
                    }
                }
                """
            )
            extensions.append(intentExtension)
        }
        
        // Generate ActivityAttributes conformance for Live Activities
        if config.supportsLiveActivity {
            let activityExtension = try ExtensionDeclSyntax(
                """
                extension \(structDecl.name): ActivityAttributes {
                    public struct ContentState: Codable, Hashable {
                        public var status: String
                        public var progress: Double
                        public var updatedAt: Date
                        
                        public init(status: String, progress: Double = 0, updatedAt: Date = Date()) {
                            self.status = status
                            self.progress = progress
                            self.updatedAt = updatedAt
                        }
                    }
                }
                """
            )
            extensions.append(activityExtension)
        }
        
        return extensions
    }
    
    private static func parseConfiguration(from node: AttributeSyntax) throws -> SharedModelConfig {
        var config = SharedModelConfig()
        
        if let arguments = node.arguments?.as(LabeledExprListSyntax.self) {
            for argument in arguments {
                guard let label = argument.label?.text else { continue }
                
                switch label {
                case "widget":
                    config.supportsWidget = argument.expression.description == "true"
                case "intent":
                    config.supportsIntent = argument.expression.description == "true"
                case "liveActivity":
                    config.supportsLiveActivity = argument.expression.description == "true"
                default:
                    break
                }
            }
        }
        
        return config
    }
    
    private static func generateWidgetMembers(for structDecl: StructDeclSyntax) -> [DeclSyntax] {
        return [
            """
            public var timestamp: Date?
            public var relevanceScore: Float?
            """
        ]
    }
    
    private static func generateIntentMembers(for structDecl: StructDeclSyntax) -> [DeclSyntax] {
        return [
            """
            public var id: String = UUID().uuidString
            public var title: String?
            """
        ]
    }
    
    private static func generateLiveActivityMembers(for structDecl: StructDeclSyntax) -> [DeclSyntax] {
        return [
            """
            public var activityId: String?
            public var isStale: Bool = false
            """
        ]
    }
}

struct SharedModelConfig {
    var supportsWidget: Bool = true
    var supportsIntent: Bool = true
    var supportsLiveActivity: Bool = false
}

enum MacroError: Error, CustomStringConvertible {
    case notAStruct
    
    var description: String {
        switch self {
        case .notAStruct:
            return "@SharedModel can only be applied to structs"
        }
    }
}