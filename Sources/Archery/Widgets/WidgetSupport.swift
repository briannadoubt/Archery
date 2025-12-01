import Foundation
import WidgetKit
import SwiftUI

#if canImport(WidgetKit)

// MARK: - Widget Support

/// Base protocol for widgets that integrate with Archery ViewModels
@available(iOS 14.0, macOS 11.0, watchOS 9.0, *)
public protocol ArcheryWidget: Widget {
    associatedtype Provider: ArcheryTimelineProvider
    associatedtype Entry: ArcheryTimelineEntry
    
    var provider: Provider { get }
}

/// Timeline provider that integrates with Archery dependency injection
@available(iOS 14.0, macOS 11.0, watchOS 9.0, *)
public protocol ArcheryTimelineProvider: TimelineProvider where Entry: ArcheryTimelineEntry {
    var container: EnvContainer { get }
    
    func createEntry(for configuration: Intent?, at date: Date) async -> Entry
    func nextUpdateDate(after date: Date) -> Date
}

/// Timeline entry with ViewModel integration
@available(iOS 14.0, macOS 11.0, watchOS 9.0, *)
public protocol ArcheryTimelineEntry: TimelineEntry {
    associatedtype ViewModel: ObservableObject
    
    var viewModel: ViewModel { get }
    var configuration: Intent? { get }
}

// MARK: - Default Implementation

@available(iOS 14.0, macOS 11.0, watchOS 9.0, *)
public extension ArcheryTimelineProvider {
    func placeholder(in context: Context) -> Entry {
        Task {
            return await createEntry(for: nil, at: Date())
        }
        // Synchronous fallback
        return createPlaceholderEntry(in: context)
    }
    
    func getSnapshot(for configuration: Intent?, in context: Context, completion: @escaping (Entry) -> Void) {
        Task {
            let entry = await createEntry(for: configuration, at: Date())
            completion(entry)
        }
    }
    
    func getTimeline(for configuration: Intent?, in context: Context, completion: @escaping (Timeline<Entry>) -> Void) {
        Task {
            let currentDate = Date()
            let entries = await createTimelineEntries(for: configuration, starting: currentDate)
            let nextUpdate = nextUpdateDate(after: currentDate)
            
            let timeline = Timeline(entries: entries, policy: .after(nextUpdate))
            completion(timeline)
        }
    }
    
    func createTimelineEntries(for configuration: Intent?, starting date: Date) async -> [Entry] {
        var entries: [Entry] = []
        let currentEntry = await createEntry(for: configuration, at: date)
        entries.append(currentEntry)
        
        // Create entries for the next few hours
        for minuteOffset in [15, 30, 60, 120] {
            let entryDate = Calendar.current.date(byAdding: .minute, value: minuteOffset, to: date) ?? date
            let entry = await createEntry(for: configuration, at: entryDate)
            entries.append(entry)
        }
        
        return entries
    }
    
    func createPlaceholderEntry(in context: Context) -> Entry {
        fatalError("Subclasses must implement createPlaceholderEntry or override placeholder(in:)")
    }
    
    func nextUpdateDate(after date: Date) -> Date {
        // Default to 15 minutes
        Calendar.current.date(byAdding: .minute, value: 15, to: date) ?? date.addingTimeInterval(900)
    }
}

// MARK: - Widget Configuration

@available(iOS 14.0, macOS 11.0, watchOS 9.0, *)
public struct WidgetConfiguration<Provider: ArcheryTimelineProvider> {
    public let kind: String
    public let displayName: String
    public let description: String
    public let supportedFamilies: [WidgetFamily]
    public let provider: Provider
    
    public init(
        kind: String,
        displayName: String,
        description: String,
        supportedFamilies: [WidgetFamily],
        provider: Provider
    ) {
        self.kind = kind
        self.displayName = displayName
        self.description = description
        self.supportedFamilies = supportedFamilies
        self.provider = provider
    }
}

// MARK: - Widget View Helpers

@available(iOS 14.0, macOS 11.0, watchOS 9.0, *)
public struct WidgetViewBuilder<Entry: ArcheryTimelineEntry, Content: View> {
    private let content: (Entry) -> Content
    
    public init(@ViewBuilder content: @escaping (Entry) -> Content) {
        self.content = content
    }
    
    @ViewBuilder
    public func build(entry: Entry, family: WidgetFamily) -> some View {
        content(entry)
            .widgetBackground()
            .environment(\.widgetFamily, family)
    }
}

@available(iOS 14.0, macOS 11.0, watchOS 9.0, *)
public extension View {
    func widgetBackground() -> some View {
        if #available(iOS 17.0, macOS 14.0, watchOS 10.0, *) {
            return containerBackground(.fill.tertiary, for: .widget)
        } else {
            return background()
        }
    }
    
    func widgetDeepLink<T: Hashable>(to route: T) -> some View {
        widgetURL(URL(string: "archery://widget/\(route)"))
    }
    
    func widgetAccentable(_ isAccentable: Bool = true) -> some View {
        if #available(iOS 16.0, macOS 13.0, watchOS 9.0, *) {
            return self.widgetAccentable(isAccentable)
        } else {
            return self
        }
    }
}

// MARK: - Widget Macro

/// Generates a complete widget with timeline provider and entry types
@attached(extension, conformances: Widget, names: named(Provider), named(Entry), named(body))
@attached(member, names: arbitrary)
public macro WidgetDefinition(
    kind: String,
    displayName: String,
    description: String,
    families: [String] = ["systemSmall", "systemMedium", "systemLarge"]
) = #externalMacro(module: "ArcheryMacros", type: "WidgetDefinitionMacro")

// MARK: - Widget Store Integration

/// Allows widgets to access repository data through the DI container
@available(iOS 14.0, macOS 11.0, watchOS 9.0, *)
public final class WidgetStore: ObservableObject {
    private let container: EnvContainer
    
    public init(container: EnvContainer = .shared) {
        self.container = container
    }
    
    /// Resolve a repository for use in widgets
    public func repository<T>(_ type: T.Type) -> T? {
        container.resolve(type)
    }
    
    /// Create a ViewModel instance for widgets
    public func viewModel<T: ObservableObject>(_ type: T.Type) -> T? {
        container.resolve(type)
    }
    
    /// Fetch data for widget timeline
    public func fetchData<T, Repository: DataRepository>(
        from repository: Repository,
        id: T.ID
    ) async throws -> T where Repository.Model == T, T: Identifiable {
        try await repository.fetch(id: id)
    }
    
    /// Fetch multiple items for widget display
    public func fetchItems<T, Repository: DataRepository>(
        from repository: Repository,
        limit: Int = 5
    ) async throws -> [T] where Repository.Model == T {
        try await repository.fetchAll().prefix(limit).map { $0 }
    }
}

// MARK: - Widget Timeline Manager

@available(iOS 14.0, macOS 11.0, watchOS 9.0, *)
public final class WidgetTimelineManager {
    private let store = WidgetStore()
    
    public static let shared = WidgetTimelineManager()
    
    private init() {}
    
    /// Reload all widgets
    public func reloadAll() {
        #if !os(macOS) && !targetEnvironment(macCatalyst)
        WidgetCenter.shared.reloadAllTimelines()
        #endif
    }
    
    /// Reload specific widget kind
    public func reload(kind: String) {
        #if !os(macOS) && !targetEnvironment(macCatalyst)
        WidgetCenter.shared.reloadTimelines(ofKind: kind)
        #endif
    }
    
    /// Get current widget configurations
    public func getCurrentConfigurations() async -> [WidgetInfo] {
        #if !os(macOS) && !targetEnvironment(macCatalyst)
        do {
            let configurations = try await WidgetCenter.shared.getCurrentConfigurations()
            return configurations.map { config in
                WidgetInfo(
                    kind: config.kind,
                    family: config.family,
                    configuration: config.configuration
                )
            }
        } catch {
            return []
        }
        #else
        return []
        #endif
    }
    
    /// Schedule widget update based on data changes
    public func scheduleUpdate(for kinds: [String] = [], delay: TimeInterval = 1.0) {
        Task {
            try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            
            if kinds.isEmpty {
                reloadAll()
            } else {
                for kind in kinds {
                    reload(kind: kind)
                }
            }
        }
    }
}

public struct WidgetInfo {
    public let kind: String
    public let family: WidgetFamily
    public let configuration: Any?
    
    public init(kind: String, family: WidgetFamily, configuration: Any?) {
        self.kind = kind
        self.family = family
        self.configuration = configuration
    }
}

// MARK: - Widget Data Helpers

@available(iOS 14.0, macOS 11.0, watchOS 9.0, *)
public struct WidgetDataLoader {
    private let store: WidgetStore
    
    public init(store: WidgetStore = WidgetStore()) {
        self.store = store
    }
    
    /// Load data with fallback for offline scenarios
    public func loadData<T>(
        loader: () async throws -> T,
        fallback: T
    ) async -> T {
        do {
            return try await loader()
        } catch {
            return fallback
        }
    }
    
    /// Load data with caching
    public func loadCachedData<T: Codable>(
        key: String,
        loader: () async throws -> T,
        fallback: T
    ) async -> T {
        // Try cache first
        if let cached = UserDefaults.standard.data(forKey: "widget_cache_\(key)"),
           let decoded = try? JSONDecoder().decode(T.self, from: cached) {
            
            // Load fresh data in background
            Task {
                if let fresh = try? await loader() {
                    let encoded = try? JSONEncoder().encode(fresh)
                    UserDefaults.standard.set(encoded, forKey: "widget_cache_\(key)")
                }
            }
            
            return decoded
        }
        
        // Load fresh data
        do {
            let data = try await loader()
            let encoded = try? JSONEncoder().encode(data)
            UserDefaults.standard.set(encoded, forKey: "widget_cache_\(key)")
            return data
        } catch {
            return fallback
        }
    }
}

// MARK: - Widget Environment Values

@available(iOS 14.0, macOS 11.0, watchOS 9.0, *)
public extension EnvironmentValues {
    var widgetStore: WidgetStore {
        get { self[WidgetStoreKey.self] }
        set { self[WidgetStoreKey.self] = newValue }
    }
}

@available(iOS 14.0, macOS 11.0, watchOS 9.0, *)
private struct WidgetStoreKey: EnvironmentKey {
    static let defaultValue = WidgetStore()
}

#endif