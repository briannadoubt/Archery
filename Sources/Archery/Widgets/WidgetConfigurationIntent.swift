import AppIntents
import WidgetKit

// MARK: - Widget Configuration Intent

/// Base configuration intent for widgets
@available(iOS 16.0, macOS 13.0, watchOS 9.0, *)
public struct WidgetConfigurationIntent: AppIntent {
    public static nonisolated(unsafe) var title: LocalizedStringResource = "Widget Configuration"
    public static nonisolated(unsafe) var description = IntentDescription("Configure widget settings")
    
    // Add any configuration parameters here
    public var showHeader: Bool
    public var refreshInterval: Int
    
    public func perform() async throws -> some IntentResult {
        return .result()
    }
    
    public init() {
        self.showHeader = true
        self.refreshInterval = 15
    }
    
    public init(showHeader: Bool, refreshInterval: Int) {
        self.showHeader = showHeader
        self.refreshInterval = refreshInterval
    }
}

// MARK: - Data Repository Protocol

/// Protocol for repositories that can provide data to widgets
public protocol DataRepository {
    associatedtype Model: Identifiable
    
    func fetch(id: Model.ID) async throws -> Model
    func fetchAll() async throws -> [Model]
}

// MARK: - Analytics Manager Extension

extension AnalyticsManager {
    /// Track events with string-based event names (for widgets)
    @MainActor
    public func trackEvent(_ eventName: String, properties: [String: Any] = [:]) {
        // Convert string event to proper AnalyticsEvent
        struct StringEvent: AnalyticsEvent {
            let name: String
            let props: [String: Any]
            
            var eventName: String { name }
            var properties: [String: Any] { props }
            
            func validate() throws {
                // Basic validation
            }
            
            func track(with provider: AnalyticsProvider) {
                provider.track(eventName: eventName, properties: properties)
            }
            
            func redactedProperties() -> [String: Any] {
                props
            }
        }
        
        track(StringEvent(name: eventName, props: properties))
    }
}
