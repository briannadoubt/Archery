import Foundation
import WidgetKit
import SwiftUI
import AppIntents

#if canImport(WidgetKit)

// MARK: - Widget Support

// Note: Intent typealias is defined in WidgetTimelineProvider.swift as ArcheryIntent

/// Base protocol for widgets that integrate with Archery ViewModels
@available(iOS 14.0, macOS 11.0, watchOS 9.0, *)
public protocol ArcheryWidget: Widget {
    associatedtype Provider: ArcheryWidgetProviderProtocol
    associatedtype Entry: ArcheryTimelineEntry

    var provider: Provider { get }
}

/// Timeline provider that integrates with Archery dependency injection
@available(iOS 14.0, macOS 11.0, watchOS 9.0, *)
public protocol ArcheryWidgetProviderProtocol where Entry: ArcheryTimelineEntry {
    associatedtype Entry: TimelineEntry

    var container: EnvContainer { get }

    func createEntry(for configuration: WidgetConfigurationIntent?, at date: Date) async -> Entry
    func createPlaceholderEntry(in context: TimelineProviderContext) -> Entry
    func nextUpdateDate(after date: Date) -> Date
}

/// Timeline entry with ViewModel integration
@available(iOS 14.0, macOS 11.0, watchOS 9.0, *)
public protocol ArcheryTimelineEntry: TimelineEntry {
    associatedtype ViewModel: ObservableObject
    
    var viewModel: ViewModel { get }
    var configuration: WidgetConfigurationIntent? { get }
}

// MARK: - Default Implementation

@available(iOS 14.0, macOS 11.0, watchOS 9.0, *)
public extension ArcheryWidgetProviderProtocol {
    func createTimelineEntries(for configuration: WidgetConfigurationIntent?, starting date: Date) async -> [Entry] {
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

    func nextUpdateDate(after date: Date) -> Date {
        // Default to 15 minutes
        Calendar.current.date(byAdding: .minute, value: 15, to: date) ?? date.addingTimeInterval(900)
    }
}

// MARK: - Widget Configuration

@available(iOS 14.0, macOS 11.0, watchOS 9.0, *)
public struct WidgetConfiguration<Provider: ArcheryWidgetProviderProtocol> {
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
@MainActor
public struct WidgetViewBuilder<Entry: ArcheryTimelineEntry, Content: View> {
    private let content: @MainActor (Entry) -> Content

    public init(@ViewBuilder content: @escaping @MainActor (Entry) -> Content) {
        self.content = content
    }

    @ViewBuilder
    public func build(entry: Entry, family: WidgetFamily) -> some View {
        content(entry)
            .widgetBackground()
            .environment(\.archeryWidgetFamily, family)
    }
}

// Custom environment key for widget family (since \.widgetFamily is read-only)
@available(iOS 14.0, macOS 11.0, watchOS 9.0, *)
private struct ArcheryWidgetFamilyKey: EnvironmentKey {
    static let defaultValue: WidgetFamily = .systemSmall
}

@available(iOS 14.0, macOS 11.0, watchOS 9.0, *)
public extension EnvironmentValues {
    var archeryWidgetFamily: WidgetFamily {
        get { self[ArcheryWidgetFamilyKey.self] }
        set { self[ArcheryWidgetFamilyKey.self] = newValue }
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
    
    @ViewBuilder
    func archeryWidgetAccentable(_ isAccentable: Bool = true) -> some View {
        if #available(iOS 16.0, macOS 13.0, watchOS 9.0, *) {
            self.modifier(WidgetAccentableModifier(isAccentable: isAccentable))
        } else {
            self
        }
    }
}

@available(iOS 16.0, macOS 13.0, watchOS 9.0, *)
private struct WidgetAccentableModifier: ViewModifier {
    let isAccentable: Bool

    func body(content: Content) -> some View {
        content.widgetAccentable(isAccentable)
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
public final class WidgetStore: ObservableObject, @unchecked Sendable {
    private let container: EnvContainer

    @MainActor
    public init(container: EnvContainer = .shared) {
        self.container = container
    }

    /// Resolve a repository for use in widgets
    @MainActor
    public func repository<T>(_ type: T.Type) -> T? {
        container.resolve()
    }

    /// Create a ViewModel instance for widgets
    @MainActor
    public func viewModel<T: ObservableObject>(_ type: T.Type) -> T? {
        container.resolve()
    }
}

// MARK: - Widget Timeline Manager

@available(iOS 14.0, macOS 11.0, watchOS 9.0, *)
@MainActor
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
            let configurations = try await withCheckedThrowingContinuation { continuation in
                WidgetCenter.shared.getCurrentConfigurations { result in
                    continuation.resume(with: result)
                }
            }
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
@MainActor
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
        loader: @escaping @Sendable () async throws -> T,
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
private struct WidgetStoreKey: @preconcurrency EnvironmentKey {
    @MainActor public static var defaultValue: WidgetStore { WidgetStore() }
}

#endif