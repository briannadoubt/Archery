import Foundation
import SwiftUI

#if canImport(AppIntents)
import AppIntents

// MARK: - App Intent Support

@available(iOS 16.0, macOS 13.0, watchOS 9.0, tvOS 16.0, *)
public protocol ArcheryAppIntent: AppIntent {
    associatedtype Repository: DataRepository

    var container: EnvContainer { get }

    func repository() -> Repository?
}

@available(iOS 16.0, macOS 13.0, watchOS 9.0, tvOS 16.0, *)
public extension ArcheryAppIntent {
    var container: EnvContainer {
        .shared
    }

    func repository() -> Repository? {
        container.resolve()
    }
}

// MARK: - Intent Result Builders

@available(iOS 16.0, macOS 13.0, watchOS 9.0, tvOS 16.0, *)
public struct IntentResultBuilder {

    /// Success result with message
    public static func success(_ message: String) -> some IntentResult {
        .result(value: message)
    }

    /// Success result with dialog
    public static func success(_ dialog: IntentDialog) -> some IntentResult {
        .result(dialog: dialog)
    }
}

// MARK: - Intent Parameters

@available(iOS 16.0, macOS 13.0, watchOS 9.0, tvOS 16.0, *)
public protocol ArcheryIntentEntity: AppEntity {
    associatedtype Value

    var value: Value { get }
}

// MARK: - Common Intent Entities

@available(iOS 16.0, macOS 13.0, watchOS 9.0, tvOS 16.0, *)
public struct TextEntity: ArcheryIntentEntity {
    public let id: String
    public let displayString: String
    public let value: String

    public init(id: String = UUID().uuidString, displayString: String, value: String) {
        self.id = id
        self.displayString = displayString
        self.value = value
    }

    public static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Text")

    public var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(displayString)")
    }

    public static var defaultQuery: TextEntityQuery { TextEntityQuery() }
}

@available(iOS 16.0, macOS 13.0, watchOS 9.0, tvOS 16.0, *)
public struct TextEntityQuery: EntityQuery {
    public init() {}

    public func entities(for identifiers: [String]) async throws -> [TextEntity] {
        []
    }

    public func suggestedEntities() async throws -> [TextEntity] {
        []
    }
}

@available(iOS 16.0, macOS 13.0, watchOS 9.0, tvOS 16.0, *)
public struct NumberEntity: ArcheryIntentEntity {
    public let id: String
    public let displayString: String
    public let value: Double

    public init(id: String = UUID().uuidString, displayString: String, value: Double) {
        self.id = id
        self.displayString = displayString
        self.value = value
    }

    public static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Number")

    public var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(displayString)")
    }

    public static var defaultQuery: NumberEntityQuery { NumberEntityQuery() }
}

@available(iOS 16.0, macOS 13.0, watchOS 9.0, tvOS 16.0, *)
public struct NumberEntityQuery: EntityQuery {
    public init() {}

    public func entities(for identifiers: [String]) async throws -> [NumberEntity] {
        []
    }

    public func suggestedEntities() async throws -> [NumberEntity] {
        []
    }
}

// MARK: - Intent Validation

@available(iOS 16.0, macOS 13.0, watchOS 9.0, tvOS 16.0, *)
public struct IntentValidator {
    
    public static func validate<T>(
        parameter: T?,
        name: String,
        required: Bool = true
    ) throws -> T? {
        if required && parameter == nil {
            throw IntentError.missingParameter(name)
        }
        return parameter
    }
    
    public static func validate(
        text: String?,
        name: String,
        minLength: Int = 0,
        maxLength: Int = Int.max
    ) throws -> String? {
        guard let text = text else {
            return nil
        }
        
        if text.count < minLength {
            throw IntentError.invalidParameter("\(name) must be at least \(minLength) characters")
        }
        
        if text.count > maxLength {
            throw IntentError.invalidParameter("\(name) must be no more than \(maxLength) characters")
        }
        
        return text
    }
    
    public static func validate(
        number: Double?,
        name: String,
        min: Double = -Double.infinity,
        max: Double = Double.infinity
    ) throws -> Double? {
        guard let number = number else {
            return nil
        }
        
        if number < min {
            throw IntentError.invalidParameter("\(name) must be at least \(min)")
        }
        
        if number > max {
            throw IntentError.invalidParameter("\(name) must be no more than \(max)")
        }
        
        return number
    }
}

// MARK: - Intent Errors

@available(iOS 16.0, macOS 13.0, watchOS 9.0, tvOS 16.0, *)
public enum IntentError: Error, LocalizedError {
    case missingParameter(String)
    case invalidParameter(String)
    case executionFailed(reason: String)
    case repositoryUnavailable
    case networkError
    case authenticationRequired
    
    public var errorDescription: String? {
        switch self {
        case .missingParameter(let name):
            return "Missing required parameter: \(name)"
        case .invalidParameter(let message):
            return "Invalid parameter: \(message)"
        case .executionFailed(let reason):
            return "Execution failed: \(reason)"
        case .repositoryUnavailable:
            return "Data repository is not available"
        case .networkError:
            return "Network connection error"
        case .authenticationRequired:
            return "Authentication is required"
        }
    }
    
    public var failureReason: String? {
        switch self {
        case .missingParameter:
            return "A required parameter was not provided"
        case .invalidParameter:
            return "The provided parameter is not valid"
        case .executionFailed:
            return "The intent could not be executed"
        case .repositoryUnavailable:
            return "Data access is not available"
        case .networkError:
            return "Network connectivity issue"
        case .authenticationRequired:
            return "User needs to sign in"
        }
    }
}

// MARK: - Intent Macro

/// Generates App Intent with repository integration
@attached(extension, conformances: ArcheryAppIntent, names: named(performAction), named(Repository))
@attached(member, names: arbitrary)
public macro AppIntent(
    title: String,
    description: String,
    repository: String? = nil,
    needsAuth: Bool = false
) = #externalMacro(module: "ArcheryMacros", type: "AppIntentMacro")

// MARK: - Common Intent Types

@available(iOS 16.0, macOS 13.0, watchOS 9.0, tvOS 16.0, *)
public struct OpenAppIntent: AppIntent {
    public static let title: LocalizedStringResource = "Open App"
    public static let description = IntentDescription("Opens the main application")
    public static let openAppWhenRun: Bool = true

    public init() {}

    public func perform() async throws -> some IntentResult {
        .result()
    }
}

@available(iOS 16.0, macOS 13.0, watchOS 9.0, tvOS 16.0, *)
public struct OpenURLIntent: AppIntent {
    public static let title: LocalizedStringResource = "Open URL"
    public static let description = IntentDescription("Opens a specific URL in the app")
    public static let openAppWhenRun: Bool = true

    @Parameter(title: "URL")
    public var url: URL

    public init(url: URL) {
        self.url = url
    }

    public init() {
        self.url = URL(string: "archery://")!
    }

    public func perform() async throws -> some IntentResult {
        .result()
    }
}

// MARK: - Intent Shortcuts Provider

@available(iOS 16.0, macOS 13.0, watchOS 9.0, tvOS 16.0, *)
public struct IntentShortcutsProvider: AppShortcutsProvider {
    public static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: OpenAppIntent(),
            phrases: [
                "Open \(.applicationName)",
                "Launch \(.applicationName)",
                "Start \(.applicationName)"
            ],
            shortTitle: "Open App",
            systemImageName: "app.badge"
        )
    }
}

// MARK: - Intent Analytics

@available(iOS 16.0, macOS 13.0, watchOS 9.0, tvOS 16.0, *)
public struct IntentAnalytics {

    public static func track(intent: String, parameters: [String: Any] = [:]) {
        var sanitizedParams = parameters

        // Remove PII
        for (key, value) in sanitizedParams {
            if isPII(key: key, value: value) {
                sanitizedParams[key] = "[REDACTED]"
            }
        }

        // Log the intent execution - actual analytics would be sent here
        #if DEBUG
        print("[IntentAnalytics] Executed: \(intent), params: \(sanitizedParams)")
        #endif
    }

    private static func isPII(key: String, value: Any) -> Bool {
        let piiKeys = ["email", "phone", "name", "address", "ssn", "password", "token"]
        return piiKeys.contains { key.lowercased().contains($0) }
    }
}

// MARK: - Siri Integration Helpers

@available(iOS 16.0, macOS 13.0, watchOS 9.0, tvOS 16.0, *)
public extension View {
    func addToSiri<Intent: AppIntent>(_ intent: Intent, phrase: String) -> some View {
        self.contextMenu {
            Button("Add to Siri") {
                // Implementation would use INVoiceShortcutCenter for iOS 15 and earlier
                #if canImport(Intents)
                if #available(iOS 12.0, *) {
                    // Legacy Siri integration
                }
                #endif
            }
        }
    }
}

#endif