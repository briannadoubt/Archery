#if canImport(AppIntents)
import AppIntents
#endif
import Foundation

#if canImport(AppIntents)
@available(iOS 16.0, macOS 13.0, *)
public protocol ArcheryAppIntent: AppIntent {
    associatedtype Result
    func perform() async throws -> Result
}

@available(iOS 16.0, macOS 13.0, *)
public struct IntentParameter<Value> {
    public let title: String
    public let description: String?
    public let defaultValue: Value?
    public let isRequired: Bool
    
    public init(
        title: String,
        description: String? = nil,
        defaultValue: Value? = nil,
        isRequired: Bool = true
    ) {
        self.title = title
        self.description = description
        self.defaultValue = defaultValue
        self.isRequired = isRequired
    }
}

@available(iOS 16.0, macOS 13.0, *)
public struct IntentBuilder {
    public let intentId: String
    public let title: String
    public let description: String?
    public let category: IntentCategory
    
    public init(
        id: String,
        title: String,
        description: String? = nil,
        category: IntentCategory = .information
    ) {
        self.intentId = id
        self.title = title
        self.description = description
        self.category = category
    }
    
    public func build<T: AppIntent>(_ type: T.Type) -> T? {
        nil
    }
}

@available(iOS 16.0, macOS 13.0, *)
public enum IntentCategory {
    case information
    case navigation
    case productivity
    case media
    case social
    case health
    case finance
    case weather
    case travel
    case food
    case shopping
    case custom(String)
}

@available(iOS 16.0, macOS 13.0, *)
public struct IntentResult<Value> {
    public let value: Value
    public let dialog: IntentDialog?
    
    public init(
        value: Value,
        dialog: IntentDialog? = nil
    ) {
        self.value = value
        self.dialog = dialog
    }
}

@available(iOS 16.0, macOS 13.0, *)
public struct EntityQueryImpl<Entity: AppEntity>: EntityQuery {
    public init() {}
    
    public func entities(for identifiers: [Entity.ID]) async throws -> [Entity] {
        []
    }
    
    public func suggestedEntities() async throws -> [Entity] {
        []
    }
}

@available(iOS 16.0, macOS 13.0, *)
public struct IntentFixture {
    public let name: String
    public let parameters: [String: Any]
    public let expectedResult: Any?
    
    public init(
        name: String,
        parameters: [String: Any] = [:],
        expectedResult: Any? = nil
    ) {
        self.name = name
        self.parameters = parameters
        self.expectedResult = expectedResult
    }
}

@available(iOS 16.0, macOS 13.0, *)
public protocol IntentHandlerProtocol {
    associatedtype Intent: AppIntent
    func handle(_ intent: Intent) async throws -> Intent.PerformResult
}

@available(iOS 16.0, macOS 13.0, *)
public struct IntentRegistry {
    private var handlers: [String: any IntentHandlerProtocol] = [:]
    
    public init() {}
    
    public mutating func register<Handler: IntentHandlerProtocol>(
        _ handler: Handler,
        for intentType: Handler.Intent.Type
    ) {
        let key = String(describing: intentType)
        handlers[key] = handler
    }
    
    public func handler<Intent: AppIntent>(for intent: Intent) -> (any IntentHandlerProtocol)? {
        let key = String(describing: type(of: intent))
        return handlers[key]
    }
}
#endif