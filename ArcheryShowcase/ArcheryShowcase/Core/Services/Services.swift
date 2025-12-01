import Foundation
import Archery
import SwiftUI

// MARK: - Network Service

class NetworkService: ObservableObject {
    static let shared = NetworkService()
    
    private let baseURL = URL(string: "https://api.archery-showcase.app")!
    private let session = URLSession.shared
    
    var authToken: String?
    
    func request<T: Decodable>(
        _ endpoint: String,
        method: String = "GET",
        body: Data? = nil,
        headers: [String: String] = [:]
    ) async throws -> T {
        let url = baseURL.appendingPathComponent(endpoint)
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = body
        
        // Add default headers
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token = authToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        
        // Add custom headers
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NetworkError.invalidResponse
        }
        
        guard (200...299).contains(httpResponse.statusCode) else {
            throw NetworkError.httpError(httpResponse.statusCode)
        }
        
        return try JSONDecoder().decode(T.self, from: data)
    }
}

enum NetworkError: LocalizedError {
    case invalidResponse
    case httpError(Int)
    case decodingError
    
    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Invalid server response"
        case .httpError(let code):
            return "HTTP error: \(code)"
        case .decodingError:
            return "Failed to decode response"
        }
    }
}

// MARK: - Persistence Service

class PersistenceService: ObservableObject {
    static let shared = PersistenceService()
    
    private let container: NSPersistentContainer
    
    init() {
        container = NSPersistentContainer(name: "ArcheryShowcase")
        container.loadPersistentStores { _, error in
            if let error = error {
                fatalError("Core Data failed to load: \(error)")
            }
        }
    }
    
    func save() throws {
        let context = container.viewContext
        if context.hasChanges {
            try context.save()
        }
    }
    
    func fetch<T: NSManagedObject>(_ type: T.Type, predicate: NSPredicate? = nil) throws -> [T] {
        let request = NSFetchRequest<T>(entityName: String(describing: type))
        request.predicate = predicate
        return try container.viewContext.fetch(request)
    }
    
    func delete(_ object: NSManagedObject) throws {
        container.viewContext.delete(object)
        try save()
    }
}

// MARK: - Analytics Service

class AnalyticsService: ObservableObject {
    static let shared = AnalyticsService()
    
    private var providers: [AnalyticsProvider] = []
    
    func configure(providers: [AnalyticsProvider]) {
        self.providers = providers
    }
    
    func track(_ event: AnalyticsEvent) {
        for provider in providers {
            provider.track(event)
        }
    }
    
    func setUser(_ userId: String, properties: [String: Any] = [:]) {
        for provider in providers {
            provider.setUser(userId, properties: properties)
        }
    }
}

enum AnalyticsProvider {
    case amplitude(apiKey: String)
    case segment(writeKey: String)
    case firebase
    case mixpanel(token: String)
    
    func track(_ event: AnalyticsEvent) {
        // Implementation would call actual SDK methods
        print("[Analytics] Tracking event: \(event)")
    }
    
    func setUser(_ userId: String, properties: [String: Any]) {
        print("[Analytics] Setting user: \(userId)")
    }
}

// MARK: - Notification Service

class NotificationService: ObservableObject {
    static let shared = NotificationService()
    
    @Published var pendingNotifications: [Notification] = []
    @Published var unreadCount = 0
    
    func requestPermission() async throws {
        // Request notification permissions
    }
    
    func scheduleNotification(
        title: String,
        body: String,
        date: Date,
        identifier: String
    ) async throws {
        // Schedule local notification
    }
    
    func cancelNotification(identifier: String) {
        // Cancel scheduled notification
    }
    
    func getUnreadCount() async -> Int {
        // In real app, fetch from repository
        return unreadCount
    }
    
    func markAsRead(_ notification: Notification) {
        unreadCount = max(0, unreadCount - 1)
    }
}

// MARK: - Theme Manager

class ThemeManager: ObservableObject {
    static let shared = ThemeManager()
    
    @Published var currentTheme: AppTheme = .system
    @Published var currentTokens: DesignTokens = .default
    
    func applyTheme(_ theme: AppTheme) {
        currentTheme = theme
        updateTokens()
    }
    
    private func updateTokens() {
        // Update design tokens based on theme
        switch currentTheme {
        case .system:
            currentTokens = .default
        case .light:
            currentTokens = .light
        case .dark:
            currentTokens = .dark
        }
    }
}

// MARK: - Feature Flags

class FeatureFlags: ObservableObject {
    static let shared = FeatureFlags()
    
    private var provider: FeatureFlagProvider?
    private var flags: [String: Bool] = [:]
    
    func configure(provider: FeatureFlagProvider) {
        self.provider = provider
        Task {
            await refreshFlags()
        }
    }
    
    func isEnabled(_ flag: String) -> Bool {
        return flags[flag] ?? false
    }
    
    func refreshFlags() async {
        // Fetch latest flags from provider
        // In demo mode, use hardcoded values
        flags = [
            "new_dashboard": true,
            "advanced_analytics": true,
            "team_collaboration": false,
            "ai_suggestions": false
        ]
    }
}

enum FeatureFlagProvider {
    case launchDarkly(key: String)
    case firebase
    case custom(url: URL)
}