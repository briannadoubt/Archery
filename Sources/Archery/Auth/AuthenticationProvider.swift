import Foundation

public protocol AuthenticationProvider: Sendable {
    associatedtype Token: AuthToken
    
    func authenticate() async throws -> Token
    func refresh(using refreshToken: String) async throws -> Token
    func signOut() async
}

public struct OAuth2Provider<T: AuthToken>: AuthenticationProvider {
    public typealias Token = T
    
    private let configuration: OAuth2Configuration
    private let session: URLSession
    private let pkceGenerator: PKCEGenerator
    
    public init(
        configuration: OAuth2Configuration,
        session: URLSession = .shared,
        pkceGenerator: PKCEGenerator = .default
    ) {
        self.configuration = configuration
        self.session = session
        self.pkceGenerator = pkceGenerator
    }
    
    public func authenticate() async throws -> T {
        let pkce = pkceGenerator.generate()
        
        var components = URLComponents(url: configuration.authorizationEndpoint, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: configuration.clientId),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: configuration.redirectURI),
            URLQueryItem(name: "code_challenge", value: pkce.challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "state", value: UUID().uuidString),
            URLQueryItem(name: "nonce", value: UUID().uuidString)
        ]
        
        if let scope = configuration.scope {
            components.queryItems?.append(URLQueryItem(name: "scope", value: scope))
        }
        
        let authorizationCode = try await performAuthorization(with: components.url!)
        
        return try await exchangeCodeForToken(
            code: authorizationCode,
            verifier: pkce.verifier
        )
    }
    
    public func refresh(using refreshToken: String) async throws -> T {
        var request = URLRequest(url: configuration.tokenEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        
        var bodyComponents = URLComponents()
        bodyComponents.queryItems = [
            URLQueryItem(name: "grant_type", value: "refresh_token"),
            URLQueryItem(name: "refresh_token", value: refreshToken),
            URLQueryItem(name: "client_id", value: configuration.clientId)
        ]
        
        if let clientSecret = configuration.clientSecret {
            bodyComponents.queryItems?.append(
                URLQueryItem(name: "client_secret", value: clientSecret)
            )
        }
        
        request.httpBody = bodyComponents.query?.data(using: .utf8)
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              200..<300 ~= httpResponse.statusCode else {
            throw AuthError.invalidResponse
        }
        
        let tokenResponse = try JSONDecoder().decode(OAuth2TokenResponse.self, from: data)
        
        return tokenResponse.toAuthToken() as! T
    }
    
    public func signOut() async {
        if let revocationEndpoint = configuration.revocationEndpoint {
            var request = URLRequest(url: revocationEndpoint)
            request.httpMethod = "POST"
            _ = try? await session.data(for: request)
        }
    }
    
    private func performAuthorization(with url: URL) async throws -> String {
        fatalError("Platform-specific implementation required")
    }
    
    private func exchangeCodeForToken(code: String, verifier: String) async throws -> T {
        var request = URLRequest(url: configuration.tokenEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        
        var bodyComponents = URLComponents()
        bodyComponents.queryItems = [
            URLQueryItem(name: "grant_type", value: "authorization_code"),
            URLQueryItem(name: "code", value: code),
            URLQueryItem(name: "redirect_uri", value: configuration.redirectURI),
            URLQueryItem(name: "client_id", value: configuration.clientId),
            URLQueryItem(name: "code_verifier", value: verifier)
        ]
        
        if let clientSecret = configuration.clientSecret {
            bodyComponents.queryItems?.append(
                URLQueryItem(name: "client_secret", value: clientSecret)
            )
        }
        
        request.httpBody = bodyComponents.query?.data(using: .utf8)
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              200..<300 ~= httpResponse.statusCode else {
            throw AuthError.invalidResponse
        }
        
        let tokenResponse = try JSONDecoder().decode(OAuth2TokenResponse.self, from: data)
        
        return tokenResponse.toAuthToken() as! T
    }
}

public struct OAuth2Configuration: Sendable {
    public let authorizationEndpoint: URL
    public let tokenEndpoint: URL
    public let revocationEndpoint: URL?
    public let clientId: String
    public let clientSecret: String?
    public let redirectURI: String
    public let scope: String?
    
    public init(
        authorizationEndpoint: URL,
        tokenEndpoint: URL,
        revocationEndpoint: URL? = nil,
        clientId: String,
        clientSecret: String? = nil,
        redirectURI: String,
        scope: String? = nil
    ) {
        self.authorizationEndpoint = authorizationEndpoint
        self.tokenEndpoint = tokenEndpoint
        self.revocationEndpoint = revocationEndpoint
        self.clientId = clientId
        self.clientSecret = clientSecret
        self.redirectURI = redirectURI
        self.scope = scope
    }
}

struct OAuth2TokenResponse: Codable {
    let accessToken: String
    let tokenType: String
    let expiresIn: Int?
    let refreshToken: String?
    let scope: String?
    
    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case tokenType = "token_type"
        case expiresIn = "expires_in"
        case refreshToken = "refresh_token"
        case scope
    }
    
    func toAuthToken() -> any AuthToken {
        let expiresAt = Date().addingTimeInterval(TimeInterval(expiresIn ?? 3600))
        return StandardAuthToken(
            accessToken: accessToken,
            refreshToken: refreshToken,
            expiresAt: expiresAt,
            scope: scope
        )
    }
}

public struct MockAuthProvider: AuthenticationProvider {
    public typealias Token = StandardAuthToken
    
    private let delay: TimeInterval
    private let shouldFail: Bool
    
    public init(delay: TimeInterval = 0.5, shouldFail: Bool = false) {
        self.delay = delay
        self.shouldFail = shouldFail
    }
    
    public func authenticate() async throws -> StandardAuthToken {
        try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        
        if shouldFail {
            throw AuthError.invalidCredentials
        }
        
        return StandardAuthToken(
            accessToken: "mock-access-token-\(UUID().uuidString)",
            refreshToken: "mock-refresh-token-\(UUID().uuidString)",
            expiresAt: Date().addingTimeInterval(3600),
            scope: "read write"
        )
    }
    
    public func refresh(using refreshToken: String) async throws -> StandardAuthToken {
        try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        
        if shouldFail {
            throw AuthError.tokenExpired
        }
        
        return StandardAuthToken(
            accessToken: "refreshed-access-token-\(UUID().uuidString)",
            refreshToken: refreshToken,
            expiresAt: Date().addingTimeInterval(3600),
            scope: "read write"
        )
    }
    
    public func signOut() async {
        try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
    }
}