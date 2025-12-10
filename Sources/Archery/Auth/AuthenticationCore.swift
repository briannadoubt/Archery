import Foundation
import SwiftUI
import Observation

public protocol AuthToken: Codable, Sendable {
    var accessToken: String { get }
    var refreshToken: String? { get }
    var expiresAt: Date { get }
    var scope: String? { get }
    
    var isExpired: Bool { get }
    func timeUntilExpiry() -> TimeInterval
}

extension AuthToken {
    public var isExpired: Bool {
        Date() >= expiresAt
    }
    
    public func timeUntilExpiry() -> TimeInterval {
        expiresAt.timeIntervalSince(Date())
    }
}

public struct StandardAuthToken: AuthToken {
    public let accessToken: String
    public let refreshToken: String?
    public let expiresAt: Date
    public let scope: String?
    
    public init(
        accessToken: String,
        refreshToken: String? = nil,
        expiresAt: Date,
        scope: String? = nil
    ) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresAt = expiresAt
        self.scope = scope
    }
}

public enum AuthenticationState: Sendable, Equatable {
    case unauthenticated
    case authenticating
    case authenticated(any AuthToken)
    case refreshing(any AuthToken)
    case failed(Error)
    
    public static func == (lhs: AuthenticationState, rhs: AuthenticationState) -> Bool {
        switch (lhs, rhs) {
        case (.unauthenticated, .unauthenticated),
             (.authenticating, .authenticating):
            return true
        case (.authenticated, .authenticated),
             (.refreshing, .refreshing):
            return true
        case (.failed, .failed):
            return true
        default:
            return false
        }
    }
    
    public var isAuthenticated: Bool {
        switch self {
        case .authenticated, .refreshing:
            return true
        default:
            return false
        }
    }
    
    public var token: (any AuthToken)? {
        switch self {
        case .authenticated(let token), .refreshing(let token):
            return token
        default:
            return nil
        }
    }
}

public enum AuthRequirement: Sendable {
    case none
    case required
    case requiredWithScope(String)
    case optional
    
    public func isSatisfied(by state: AuthenticationState) -> Bool {
        switch self {
        case .none:
            return true
        case .optional:
            return true
        case .required:
            return state.isAuthenticated
        case .requiredWithScope(let requiredScope):
            guard let token = state.token else { return false }
            guard let tokenScope = token.scope else { return false }
            return tokenScope.contains(requiredScope)
        }
    }
}

@MainActor
@Observable
public final class AuthenticationManager {
    public private(set) var state: AuthenticationState = .unauthenticated
    private var provider: any AuthenticationProvider
    private var tokenStorage: TokenStorage
    private var refreshTask: Task<Void, Never>?
    private var refreshTimer: Timer?
    
    public init(
        provider: any AuthenticationProvider,
        tokenStorage: TokenStorage = .keychain()
    ) {
        self.provider = provider
        self.tokenStorage = tokenStorage
        Task {
            await loadStoredToken()
        }
    }
    
    public func authenticate() async throws {
        state = .authenticating

        // Auto-track auth started
        let providerName = String(describing: type(of: provider))
        ArcheryAnalyticsConfiguration.shared.track(
            .authStarted(method: providerName)
        )

        do {
            let token = try await provider.authenticate()
            try await tokenStorage.store(token)
            state = .authenticated(token)
            scheduleTokenRefresh(for: token)

            // Auto-track auth completed
            ArcheryAnalyticsConfiguration.shared.track(
                .authCompleted(method: providerName, hasRefreshToken: token.refreshToken != nil)
            )
        } catch {
            state = .failed(error)

            // Auto-track auth failed
            let nsError = error as NSError
            ArcheryAnalyticsConfiguration.shared.track(
                .authFailed(
                    method: providerName,
                    errorCode: String(nsError.code),
                    errorMessage: error.localizedDescription
                )
            )

            throw error
        }
    }
    
    public func refreshToken() async throws {
        guard case .authenticated(let currentToken) = state else {
            throw AuthError.notAuthenticated
        }

        guard let refreshToken = currentToken.refreshToken else {
            throw AuthError.noRefreshToken
        }

        state = .refreshing(currentToken)

        do {
            let newToken = try await provider.refresh(using: refreshToken)
            try await tokenStorage.store(newToken)
            state = .authenticated(newToken)
            scheduleTokenRefresh(for: newToken)

            // Auto-track token refreshed
            ArcheryAnalyticsConfiguration.shared.track(.authTokenRefreshed)
        } catch {
            state = .failed(error)

            // Auto-track refresh failed
            let nsError = error as NSError
            ArcheryAnalyticsConfiguration.shared.track(
                .authRefreshFailed(
                    errorCode: String(nsError.code),
                    errorMessage: error.localizedDescription
                )
            )

            throw error
        }
    }

    public func signOut() async {
        refreshTimer?.invalidate()
        refreshTimer = nil
        refreshTask?.cancel()
        refreshTask = nil

        await tokenStorage.clear()
        await provider.signOut()
        state = .unauthenticated

        // Auto-track sign out
        ArcheryAnalyticsConfiguration.shared.track(.authSignedOut)
    }
    
    private func loadStoredToken() async {
        if let token = await tokenStorage.retrieve() {
            if !token.isExpired {
                state = .authenticated(token)
                scheduleTokenRefresh(for: token)
            } else if token.refreshToken != nil {
                try? await refreshToken()
            }
        }
    }
    
    private func scheduleTokenRefresh(for token: any AuthToken) {
        refreshTimer?.invalidate()
        
        let timeUntilRefresh = max(0, token.timeUntilExpiry() - 60)
        
        guard timeUntilRefresh > 0 else {
            Task { try? await refreshToken() }
            return
        }
        
        refreshTimer = Timer.scheduledTimer(withTimeInterval: timeUntilRefresh, repeats: false) { _ in
            Task { @MainActor in
                try? await self.refreshToken()
            }
        }
    }
}

public enum AuthError: LocalizedError {
    case notAuthenticated
    case noRefreshToken
    case invalidCredentials
    case tokenExpired
    case scopeInsufficient(required: String, actual: String?)
    case networkError(Error)
    case invalidResponse
    
    public var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "User is not authenticated"
        case .noRefreshToken:
            return "No refresh token available"
        case .invalidCredentials:
            return "Invalid username or password"
        case .tokenExpired:
            return "Authentication token has expired"
        case .scopeInsufficient(let required, let actual):
            return "Insufficient permissions. Required: \(required), Actual: \(actual ?? "none")"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .invalidResponse:
            return "Invalid authentication response"
        }
    }
}