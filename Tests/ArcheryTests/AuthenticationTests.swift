import XCTest
import SwiftUI
@testable import Archery

final class AuthenticationTests: XCTestCase {
    var authManager: AuthenticationManager!
    var mockProvider: MockAuthProvider!
    
    override func setUp() async throws {
        mockProvider = MockAuthProvider(delay: 0.1)
        authManager = await AuthenticationManager(
            provider: mockProvider,
            tokenStorage: .inMemory()
        )
    }
    
    func testInitialStateIsUnauthenticated() async {
        await MainActor.run {
            XCTAssertEqual(authManager.state.isAuthenticated, false)
        }
    }
    
    func testSuccessfulAuthentication() async throws {
        try await authManager.authenticate()
        
        await MainActor.run {
            XCTAssertTrue(authManager.state.isAuthenticated)
            XCTAssertNotNil(authManager.state.token)
        }
    }
    
    func testFailedAuthentication() async {
        let failingProvider = MockAuthProvider(delay: 0.1, shouldFail: true)
        let failingManager = await AuthenticationManager(
            provider: failingProvider,
            tokenStorage: .inMemory()
        )
        
        do {
            try await failingManager.authenticate()
            XCTFail("Authentication should have failed")
        } catch {
            await MainActor.run {
                if case .failed(let authError) = failingManager.state {
                    XCTAssertNotNil(authError)
                } else {
                    XCTFail("State should be failed")
                }
            }
        }
    }
    
    func testTokenRefresh() async throws {
        try await authManager.authenticate()
        
        guard let initialToken = await authManager.state.token else {
            XCTFail("No initial token")
            return
        }
        
        try await authManager.refreshToken()
        
        await MainActor.run {
            guard let refreshedToken = authManager.state.token else {
                XCTFail("No refreshed token")
                return
            }
            
            XCTAssertNotEqual(initialToken.accessToken, refreshedToken.accessToken)
            XCTAssertEqual(initialToken.refreshToken, refreshedToken.refreshToken)
        }
    }
    
    func testSignOut() async throws {
        try await authManager.authenticate()
        
        await MainActor.run {
            XCTAssertTrue(authManager.state.isAuthenticated)
        }
        
        await authManager.signOut()
        
        await MainActor.run {
            XCTAssertFalse(authManager.state.isAuthenticated)
            XCTAssertNil(authManager.state.token)
        }
    }
    
    func testAuthRequirements() async {
        let noneReq = AuthRequirement.none
        let optionalReq = AuthRequirement.optional
        let requiredReq = AuthRequirement.required
        let scopedReq = AuthRequirement.requiredWithScope("admin")
        
        let unauthState = AuthenticationState.unauthenticated
        let authToken = StandardAuthToken(
            accessToken: "test",
            refreshToken: nil,
            expiresAt: Date().addingTimeInterval(3600),
            scope: "read write"
        )
        let authState = AuthenticationState.authenticated(authToken)
        let adminToken = StandardAuthToken(
            accessToken: "admin",
            refreshToken: nil,
            expiresAt: Date().addingTimeInterval(3600),
            scope: "admin read write"
        )
        let adminState = AuthenticationState.authenticated(adminToken)
        
        XCTAssertTrue(noneReq.isSatisfied(by: unauthState))
        XCTAssertTrue(noneReq.isSatisfied(by: authState))
        
        XCTAssertTrue(optionalReq.isSatisfied(by: unauthState))
        XCTAssertTrue(optionalReq.isSatisfied(by: authState))
        
        XCTAssertFalse(requiredReq.isSatisfied(by: unauthState))
        XCTAssertTrue(requiredReq.isSatisfied(by: authState))
        
        XCTAssertFalse(scopedReq.isSatisfied(by: unauthState))
        XCTAssertFalse(scopedReq.isSatisfied(by: authState))
        XCTAssertTrue(scopedReq.isSatisfied(by: adminState))
    }
}

final class PKCETests: XCTestCase {
    func testPKCEGeneration() {
        let generator = PKCEGenerator()
        let pair = generator.generate()
        
        XCTAssertFalse(pair.verifier.isEmpty)
        XCTAssertFalse(pair.challenge.isEmpty)
        XCTAssertNotEqual(pair.verifier, pair.challenge)
        
        XCTAssertGreaterThanOrEqual(pair.verifier.count, 43)
        XCTAssertLessThanOrEqual(pair.verifier.count, 128)
    }
    
    func testPKCEUniqueness() {
        let generator = PKCEGenerator()
        let pairs = (0..<100).map { _ in generator.generate() }
        
        let uniqueVerifiers = Set(pairs.map { $0.verifier })
        let uniqueChallenges = Set(pairs.map { $0.challenge })
        
        XCTAssertEqual(uniqueVerifiers.count, 100)
        XCTAssertEqual(uniqueChallenges.count, 100)
    }
    
    func testNonceGeneration() {
        let generator = NonceGenerator()
        let nonce = generator.generate()
        
        XCTAssertFalse(nonce.isEmpty)
        XCTAssertGreaterThan(nonce.count, 0)
    }
}

final class SecureLoggerTests: XCTestCase {
    func testPIIRedaction() {
        let redactor = PIIRedactor()
        
        let email = "user@example.com"
        XCTAssertTrue(redactor.shouldRedact(email))
        XCTAssertEqual(redactor.redact(email), "[REDACTED]")
        
        let phone = "555-123-4567"
        XCTAssertTrue(redactor.shouldRedact(phone))
        XCTAssertEqual(redactor.redact(phone), "[REDACTED]")
        
        let ssn = "123-45-6789"
        XCTAssertTrue(redactor.shouldRedact(ssn))
        XCTAssertEqual(redactor.redact(ssn), "[REDACTED]")
        
        let creditCard = "4111 1111 1111 1111"
        XCTAssertTrue(redactor.shouldRedact(creditCard))
        XCTAssertEqual(redactor.redact(creditCard), "[REDACTED]")
        
        let apiKey = "api_key: sk_test_1234567890"
        XCTAssertTrue(redactor.shouldRedact(apiKey))
        XCTAssertTrue(redactor.redact(apiKey).contains("[REDACTED]"))
        
        let password = "password: mysecretpass123"
        XCTAssertTrue(redactor.shouldRedact(password))
        XCTAssertTrue(redactor.redact(password).contains("[REDACTED]"))
        
        let safeText = "This is safe text without PII"
        XCTAssertFalse(redactor.shouldRedact(safeText))
        XCTAssertEqual(redactor.redact(safeText), safeText)
    }
    
    func testComplexRedaction() {
        let redactor = PIIRedactor()
        
        let complexMessage = """
        User john.doe@example.com logged in from 192.168.1.1
        Phone: 555-867-5309
        Authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9
        """
        
        let redacted = redactor.redact(complexMessage)
        
        XCTAssertFalse(redacted.contains("john.doe@example.com"))
        XCTAssertFalse(redacted.contains("192.168.1.1"))
        XCTAssertFalse(redacted.contains("555-867-5309"))
        XCTAssertFalse(redacted.contains("eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9"))
        XCTAssertTrue(redacted.contains("[REDACTED]"))
    }
}

final class TokenStorageTests: XCTestCase {
    func testInMemoryStorage() async throws {
        let storage = TokenStorage.inMemory()
        
        let token = StandardAuthToken(
            accessToken: "test-token",
            refreshToken: "refresh-token",
            expiresAt: Date().addingTimeInterval(3600),
            scope: "read"
        )
        
        let retrieved1 = await storage.retrieve()
        XCTAssertNil(retrieved1)
        
        try await storage.store(token)
        
        let retrieved2 = await storage.retrieve()
        XCTAssertNotNil(retrieved2)
        XCTAssertEqual(retrieved2?.accessToken, "test-token")
        
        await storage.clear()
        
        let retrieved3 = await storage.retrieve()
        XCTAssertNil(retrieved3)
    }
}

final class AuthenticationGuardTests: XCTestCase {
    @MainActor
    func testAuthenticationGuardView() {
        let authManager = AuthenticationManager(provider: MockAuthProvider())
        
        let view = AuthenticationGuard(requirement: .required) {
            Text("Authenticated Content")
        }
        .authenticationManager(authManager)
        
        XCTAssertNotNil(view)
    }
    
    @MainActor
    func testAuthenticatedView() {
        let authManager = AuthenticationManager(provider: MockAuthProvider())
        
        let view = AuthenticatedView { token in
            Text("Token: \(token.accessToken)")
        }
        .authenticationManager(authManager)
        
        XCTAssertNotNil(view)
    }
}