import Foundation
import Archery
import SwiftUI

// MARK: - Network Service
//
// Now uses AppConfiguration for baseURL, timeout, and retry settings.
// This demonstrates how @Configuration integrates with existing services.

class NetworkService: ObservableObject {
    static let shared = NetworkService()

    private let session = URLSession.shared

    var authToken: String?

    // Configuration-driven properties
    private var baseURL: URL {
        URL(string: AppConfiguration.apiBaseURL)!
    }

    private var timeout: TimeInterval {
        TimeInterval(AppConfiguration.requestTimeout)
    }

    private var maxRetries: Int {
        AppConfiguration.maxRetries
    }

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
        request.timeoutInterval = timeout

        // Add default headers
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token = authToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        // Add API key from secrets if available
        let apiKey = await MainActor.run {
            AppConfiguration.resolvedApiKey
        }
        if let apiKey {
            request.setValue(apiKey, forHTTPHeaderField: "X-API-Key")
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
//
// NOTE: Analytics is now provided by Archery framework:
// - AnalyticsManager.shared (from Archery)
// - AnalyticsProvider protocol (from Archery)
// - Auto-configured by @AppShell via `analyticsProviders` property

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

// ThemeManager is defined in DesignTokens.swift

// MARK: - Feature Flags

class FeatureFlags: ObservableObject {
    static let shared = FeatureFlags()
    
    private var provider: FeatureFlagProvider?
    private var flags: [String: Bool] = [:]
    
    func configure(provider: FeatureFlagProvider) {
        self.provider = provider
        _Concurrency.Task {
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