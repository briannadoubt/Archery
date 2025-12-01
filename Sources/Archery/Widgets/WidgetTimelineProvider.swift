import Foundation
import WidgetKit
import SwiftUI
import AppIntents

public typealias Intent = WidgetConfigurationIntent

#if canImport(WidgetKit)

// MARK: - Enhanced Widget Timeline Provider

@available(iOS 14.0, macOS 11.0, watchOS 9.0, *)
public final class ArcheryWidgetTimelineProvider<Entry: ArcheryTimelineEntry>: ArcheryWidgetProvider {
    
    public let container: EnvContainer
    private let dataLoader: WidgetDataLoader
    private let cacheManager: WidgetCacheManager
    
    public init(container: EnvContainer = .shared) {
        self.container = container
        self.dataLoader = WidgetDataLoader(store: WidgetStore(container: container))
        self.cacheManager = WidgetCacheManager()
    }
    
    // MARK: - Timeline Creation
    
    public func createEntry(for configuration: Intent?, at date: Date) async -> Entry {
        // This is implemented by subclasses
        fatalError("Subclasses must implement createEntry(for:at:)")
    }
    
    public func createPlaceholderEntry(in context: Context) -> Entry {
        // Create a basic placeholder
        fatalError("Subclasses must implement createPlaceholderEntry(in:)")
    }
    
    // MARK: - Advanced Timeline Management
    
    /// Create a smart timeline that adapts based on user behavior
    public func createAdaptiveTimeline(
        for configuration: Intent?,
        starting date: Date,
        in context: Context
    ) async -> Timeline<Entry> {
        
        let userPatterns = await getUserUsagePatterns()
        let entries = await createAdaptiveEntries(
            for: configuration,
            starting: date,
            patterns: userPatterns,
            context: context
        )
        
        let nextUpdate = calculateOptimalUpdateTime(
            from: date,
            patterns: userPatterns,
            context: context
        )
        
        return Timeline(entries: entries, policy: .after(nextUpdate))
    }
    
    private func createAdaptiveEntries(
        for configuration: Intent?,
        starting date: Date,
        patterns: UserUsagePatterns,
        context: Context
    ) async -> [Entry] {
        
        var entries: [Entry] = []
        let calendar = Calendar.current
        
        // Current entry
        let currentEntry = await createEntry(for: configuration, at: date)
        entries.append(currentEntry)
        
        // Create entries based on usage patterns
        let intervals = calculateUpdateIntervals(patterns: patterns, context: context)
        
        for interval in intervals {
            guard let entryDate = calendar.date(byAdding: .minute, value: interval, to: date) else {
                continue
            }
            
            let entry = await createEntry(for: configuration, at: entryDate)
            entries.append(entry)
        }
        
        return entries
    }
    
    private func calculateUpdateIntervals(
        patterns: UserUsagePatterns,
        context: Context
    ) -> [Int] {
        
        let currentHour = Calendar.current.component(.hour, from: Date())
        
        // More frequent updates during active hours
        if patterns.activeHours.contains(currentHour) {
            return [5, 15, 30, 60] // Every 5, 15, 30 min, 1 hour
        } else {
            return [30, 60, 120, 240] // Every 30 min, 1, 2, 4 hours
        }
    }
    
    private func calculateOptimalUpdateTime(
        from date: Date,
        patterns: UserUsagePatterns,
        context: Context
    ) -> Date {
        
        let calendar = Calendar.current
        let currentHour = calendar.component(.hour, from: date)
        
        // If user is typically active in the next hour, update soon
        if patterns.activeHours.contains((currentHour + 1) % 24) {
            return calendar.date(byAdding: .minute, value: 15, to: date) ?? date
        }
        
        // Otherwise, update less frequently
        return calendar.date(byAdding: .hour, value: 1, to: date) ?? date
    }
    
    private func getUserUsagePatterns() async -> UserUsagePatterns {
        // Analyze user behavior from app usage
        let defaults = UserDefaults(suiteName: "group.archery.widgets")
        
        let activeHours = defaults?.array(forKey: "user_active_hours") as? [Int] ?? [7, 8, 9, 12, 13, 18, 19, 20]
        let lastAppOpen = defaults?.object(forKey: "last_app_open") as? Date ?? Date()
        let avgSessionLength = defaults?.double(forKey: "avg_session_length") ?? 300 // 5 minutes
        
        return UserUsagePatterns(
            activeHours: Set(activeHours),
            lastAppOpen: lastAppOpen,
            averageSessionLength: avgSessionLength
        )
    }
}

// MARK: - User Usage Patterns

@available(iOS 14.0, macOS 11.0, watchOS 9.0, *)
public struct UserUsagePatterns {
    public let activeHours: Set<Int> // Hours (0-23) when user is typically active
    public let lastAppOpen: Date
    public let averageSessionLength: TimeInterval
    
    public init(activeHours: Set<Int>, lastAppOpen: Date, averageSessionLength: TimeInterval) {
        self.activeHours = activeHours
        self.lastAppOpen = lastAppOpen
        self.averageSessionLength = averageSessionLength
    }
}

// MARK: - Widget Cache Manager

@available(iOS 14.0, macOS 11.0, watchOS 9.0, *)
public final class WidgetCacheManager {
    
    private let userDefaults: UserDefaults
    private let cacheTimeout: TimeInterval = 15 * 60 // 15 minutes
    
    public init(suiteName: String = "group.archery.widgets") {
        self.userDefaults = UserDefaults(suiteName: suiteName) ?? .standard
    }
    
    /// Cache data for widget use
    public func cache<T: Codable>(_ data: T, forKey key: String) {
        do {
            let encoded = try JSONEncoder().encode(data)
            let cacheEntry = CacheEntry(data: encoded, timestamp: Date())
            let entryData = try JSONEncoder().encode(cacheEntry)
            userDefaults.set(entryData, forKey: key)
        } catch {
            print("Failed to cache data: \(error)")
        }
    }
    
    /// Retrieve cached data
    public func retrieve<T: Codable>(_ type: T.Type, forKey key: String) -> T? {
        guard let entryData = userDefaults.data(forKey: key),
              let cacheEntry = try? JSONDecoder().decode(CacheEntry.self, from: entryData) else {
            return nil
        }
        
        // Check if cache is still valid
        if Date().timeIntervalSince(cacheEntry.timestamp) > cacheTimeout {
            userDefaults.removeObject(forKey: key)
            return nil
        }
        
        do {
            return try JSONDecoder().decode(type, from: cacheEntry.data)
        } catch {
            return nil
        }
    }
    
    /// Clear all cached data
    public func clearCache() {
        let keys = userDefaults.dictionaryRepresentation().keys
        for key in keys where key.hasPrefix("widget_cache_") {
            userDefaults.removeObject(forKey: key)
        }
    }
    
    /// Update cache timeout
    public func isCacheValid(forKey key: String) -> Bool {
        guard let entryData = userDefaults.data(forKey: key),
              let cacheEntry = try? JSONDecoder().decode(CacheEntry.self, from: entryData) else {
            return false
        }
        
        return Date().timeIntervalSince(cacheEntry.timestamp) <= cacheTimeout
    }
}

private struct CacheEntry: Codable {
    let data: Data
    let timestamp: Date
}

// MARK: - Widget Content Strategies

@available(iOS 14.0, macOS 11.0, watchOS 9.0, *)
public enum WidgetContentStrategy {
    case realTime // Always fetch fresh data
    case cached // Use cached data with fallback
    case hybrid // Cached with background refresh
    case placeholder // Show placeholder when data unavailable
}

@available(iOS 14.0, macOS 11.0, watchOS 9.0, *)
public final class WidgetContentManager<T: Codable> {
    
    private let strategy: WidgetContentStrategy
    private let cacheManager: WidgetCacheManager
    private let cacheKey: String
    
    public init(
        strategy: WidgetContentStrategy,
        cacheKey: String,
        cacheManager: WidgetCacheManager = WidgetCacheManager()
    ) {
        self.strategy = strategy
        self.cacheKey = cacheKey
        self.cacheManager = cacheManager
    }
    
    /// Load content according to strategy
    public func loadContent(
        fresh: () async throws -> T,
        placeholder: () -> T
    ) async -> T {
        
        switch strategy {
        case .realTime:
            do {
                return try await fresh()
            } catch {
                return placeholder()
            }
            
        case .cached:
            if let cached = cacheManager.retrieve(T.self, forKey: cacheKey) {
                return cached
            }
            
            do {
                let data = try await fresh()
                cacheManager.cache(data, forKey: cacheKey)
                return data
            } catch {
                return placeholder()
            }
            
        case .hybrid:
            // Return cached data immediately if available
            if let cached = cacheManager.retrieve(T.self, forKey: cacheKey) {
                // Refresh in background
                Task {
                    if let fresh = try? await fresh() {
                        cacheManager.cache(fresh, forKey: cacheKey)
                    }
                }
                return cached
            }
            
            // No cache, fetch fresh
            do {
                let data = try await fresh()
                cacheManager.cache(data, forKey: cacheKey)
                return data
            } catch {
                return placeholder()
            }
            
        case .placeholder:
            return placeholder()
        }
    }
}

// MARK: - Widget Analytics

@available(iOS 14.0, macOS 11.0, watchOS 9.0, *)
public final class WidgetAnalytics {
    
    public static let shared = WidgetAnalytics()
    
    private init() {}
    
    /// Track widget view
    public func trackWidgetView(kind: String, family: WidgetFamily, hasData: Bool) {
        let familyString = familyString(for: family)
        
        AnalyticsManager.shared.trackEvent(
            "widget_viewed",
            properties: [
                "widget_kind": kind,
                "widget_family": familyString,
                "has_data": hasData,
                "timestamp": Date().timeIntervalSince1970
            ]
        )
    }
    
    /// Track widget interaction
    public func trackWidgetTap(kind: String, family: WidgetFamily, action: String? = nil) {
        let familyString = familyString(for: family)
        
        var properties: [String: Any] = [
            "widget_kind": kind,
            "widget_family": familyString,
            "timestamp": Date().timeIntervalSince1970
        ]
        
        if let action = action {
            properties["action"] = action
        }
        
        AnalyticsManager.shared.trackEvent(
            "widget_tapped",
            properties: properties
        )
    }
    
    /// Track widget configuration
    public func trackWidgetConfigured(kind: String, family: WidgetFamily) {
        let familyString = familyString(for: family)
        
        AnalyticsManager.shared.trackEvent(
            "widget_configured",
            properties: [
                "widget_kind": kind,
                "widget_family": familyString,
                "timestamp": Date().timeIntervalSince1970
            ]
        )
    }
    
    private func familyString(for family: WidgetFamily) -> String {
        switch family {
        case .systemSmall:
            return "small"
        case .systemMedium:
            return "medium"
        case .systemLarge:
            return "large"
        case .systemExtraLarge:
            if #available(iOS 15.0, macOS 12.0, *) {
                return "extra_large"
            } else {
                return "large"
            }
        case .accessoryCircular:
            if #available(iOS 16.0, macOS 13.0, watchOS 9.0, *) {
                return "accessory_circular"
            } else {
                return "small"
            }
        case .accessoryRectangular:
            if #available(iOS 16.0, macOS 13.0, watchOS 9.0, *) {
                return "accessory_rectangular"
            } else {
                return "small"
            }
        case .accessoryInline:
            if #available(iOS 16.0, macOS 13.0, watchOS 9.0, *) {
                return "accessory_inline"
            } else {
                return "small"
            }
        @unknown default:
            return "unknown"
        }
    }
}

// MARK: - Widget Preview Helpers

@available(iOS 14.0, macOS 11.0, watchOS 9.0, *)
public struct WidgetPreviewHelper {
    
    /// Create preview data for development
    public static func createPreviewEntry<Entry: ArcheryTimelineEntry>(
        _ type: Entry.Type,
        with mockData: Entry.ViewModel
    ) -> Entry {
        // This would need to be implemented by each specific entry type
        fatalError("Use specific entry type initializer for previews")
    }
    
    /// Create preview timeline
    public static func createPreviewTimeline<Entry: ArcheryTimelineEntry>(
        _ type: Entry.Type,
        with entries: [Entry]
    ) -> Timeline<Entry> {
        Timeline(entries: entries, policy: .never)
    }
}

// MARK: - Widget Error Handling

@available(iOS 14.0, macOS 11.0, watchOS 9.0, *)
public enum WidgetError: Error, LocalizedError {
    case dataUnavailable
    case networkError
    case configurationError
    case cacheError
    
    public var errorDescription: String? {
        switch self {
        case .dataUnavailable:
            return "Data is not available"
        case .networkError:
            return "Network connection error"
        case .configurationError:
            return "Widget configuration error"
        case .cacheError:
            return "Cache operation failed"
        }
    }
    
    /// Create a fallback entry for error states
    public func createFallbackEntry<Entry: ArcheryTimelineEntry>(
        _ type: Entry.Type,
        at date: Date
    ) -> Entry? {
        // This would need to be implemented by each specific entry type
        return nil
    }
}

#endif