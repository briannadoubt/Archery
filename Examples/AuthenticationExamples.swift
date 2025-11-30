import SwiftUI
import Archery

struct AuthenticationExamplesApp: App {
    @StateObject private var authManager = AuthenticationManager(
        provider: MockAuthProvider(),
        tokenStorage: .keychain()
    )
    
    @StateObject private var securityMonitor = SecurityMonitor()
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .authenticationManager(authManager)
                .environmentObject(securityMonitor)
                .onAppear {
                    SecurityDetection.shared.performAllChecks()
                }
        }
    }
}

struct ContentView: View {
    @Environment(\.authManager) private var authManager
    @EnvironmentObject private var securityMonitor: SecurityMonitor
    
    var body: some View {
        TabView {
            HomeView()
                .tabItem {
                    Label("Home", systemImage: "house")
                }
            
            ProfileView()
                .requiresAuthentication()
                .tabItem {
                    Label("Profile", systemImage: "person")
                }
            
            AdminView()
                .requiresAuthentication(.requiredWithScope("admin"))
                .tabItem {
                    Label("Admin", systemImage: "gear")
                }
            
            SecurityView()
                .tabItem {
                    Label("Security", systemImage: "lock.shield")
                }
        }
    }
}

struct HomeView: View {
    @Environment(\.authManager) private var authManager
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Text("Welcome to Archery Auth")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                
                StatusCard(authManager: authManager)
                
                if !authManager.state.isAuthenticated {
                    Button("Sign In") {
                        Task {
                            try? await authManager.authenticate()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(authManager.state == .authenticating)
                } else {
                    Button("Sign Out") {
                        Task {
                            await authManager.signOut()
                        }
                    }
                    .buttonStyle(.bordered)
                }
                
                Spacer()
            }
            .padding()
            .navigationTitle("Home")
        }
    }
}

struct StatusCard: View {
    let authManager: AuthenticationManager
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: authManager.state.isAuthenticated ? "checkmark.shield.fill" : "xmark.shield.fill")
                    .foregroundColor(authManager.state.isAuthenticated ? .green : .red)
                
                Text(statusText)
                    .font(.headline)
            }
            
            if let token = authManager.state.token {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Access Token: \(String(token.accessToken.prefix(20)))...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    if let scope = token.scope {
                        Text("Scope: \(scope)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Text("Expires: \(token.expiresAt, style: .relative)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
    
    private var statusText: String {
        switch authManager.state {
        case .unauthenticated:
            return "Not Authenticated"
        case .authenticating:
            return "Authenticating..."
        case .authenticated:
            return "Authenticated"
        case .refreshing:
            return "Refreshing Token..."
        case .failed(let error):
            return "Failed: \(error.localizedDescription)"
        }
    }
}

struct ProfileView: View {
    @Environment(\.authManager) private var authManager
    
    var body: some View {
        NavigationStack {
            AuthenticatedView { token in
                List {
                    Section("User Information") {
                        LabeledContent("Access Token", value: String(token.accessToken.prefix(20)) + "...")
                        
                        if let scope = token.scope {
                            LabeledContent("Permissions", value: scope)
                        }
                        
                        LabeledContent("Expires", value: token.expiresAt, format: .dateTime)
                        
                        LabeledContent("Time Until Expiry") {
                            Text(token.expiresAt, style: .relative)
                        }
                    }
                    
                    Section("Actions") {
                        Button("Refresh Token") {
                            Task {
                                try? await authManager.refreshToken()
                            }
                        }
                        .disabled(token.refreshToken == nil)
                        
                        Button("Sign Out", role: .destructive) {
                            Task {
                                await authManager.signOut()
                            }
                        }
                    }
                }
                .navigationTitle("Profile")
            }
        }
    }
}

struct AdminView: View {
    @Environment(\.authManager) private var authManager
    
    var body: some View {
        NavigationStack {
            VStack {
                Image(systemName: "crown.fill")
                    .font(.system(size: 60))
                    .foregroundColor(.yellow)
                
                Text("Admin Panel")
                    .font(.title)
                    .fontWeight(.bold)
                
                Text("You have admin privileges!")
                    .font(.body)
                    .foregroundColor(.secondary)
            }
            .navigationTitle("Admin")
        }
    }
}

struct SecurityView: View {
    @EnvironmentObject private var securityMonitor: SecurityMonitor
    
    var body: some View {
        NavigationStack {
            List {
                Section("Security Status") {
                    HStack {
                        Image(systemName: securityMonitor.isSecure ? "checkmark.shield.fill" : "exclamationmark.shield.fill")
                            .foregroundColor(securityMonitor.isSecure ? .green : .red)
                        
                        Text(securityMonitor.isSecure ? "Device is Secure" : "Security Issues Detected")
                            .fontWeight(.semibold)
                    }
                    
                    if let lastCheck = securityMonitor.lastCheckDate {
                        LabeledContent("Last Check", value: lastCheck, format: .dateTime)
                    }
                }
                
                if !securityMonitor.threats.isEmpty {
                    Section("Detected Threats") {
                        ForEach(Array(securityMonitor.threats), id: \.self) { threat in
                            HStack {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundColor(.red)
                                Text(threat.rawValue)
                            }
                        }
                    }
                }
                
                Section("Actions") {
                    Button("Run Security Check") {
                        securityMonitor.performCheck()
                    }
                    
                    Button("Clear Logs") {
                        Task {
                            await SecureLogger.shared.clearLogs()
                        }
                    }
                }
                
                Section("Security Features") {
                    LabeledContent("PII Redaction", value: "Enabled")
                    LabeledContent("Secure Logging", value: "Active")
                    LabeledContent("Jailbreak Detection", value: "Enabled")
                    LabeledContent("Debug Detection", value: "Enabled")
                    LabeledContent("Tampering Detection", value: "Enabled")
                }
            }
            .navigationTitle("Security")
        }
    }
}

@Authenticated
class SecureUserRepository {
    private let logger = SecureLogger.shared
    
    func fetchUserData() async throws -> UserData {
        logger.info("Fetching user data")
        
        return UserData(
            id: UUID(),
            email: "user@example.com",
            name: "John Doe",
            roles: ["user", "premium"]
        )
    }
    
    func updateProfile(name: String) async throws {
        logger.info("Updating profile name to: \(name)")
    }
}

@Authenticated(scope: "admin")
class AdminRepository {
    private let logger = SecureLogger.shared
    
    func fetchAllUsers() async throws -> [UserData] {
        logger.info("Admin fetching all users")
        
        return [
            UserData(id: UUID(), email: "admin@example.com", name: "Admin User", roles: ["admin"]),
            UserData(id: UUID(), email: "user1@example.com", name: "User One", roles: ["user"]),
            UserData(id: UUID(), email: "user2@example.com", name: "User Two", roles: ["user", "premium"])
        ]
    }
    
    func deleteUser(id: UUID) async throws {
        logger.warning("Admin deleting user: \(id)")
    }
}

struct UserData: Identifiable, Codable {
    let id: UUID
    let email: String
    let name: String
    let roles: [String]
}

@ViewModelBound
@ObservableViewModel
class AuthenticatedViewModel {
    @Published var userData: UserData?
    @Published var isLoading = false
    @Published var error: Error?
    
    @Authenticated
    private let repository = SecureUserRepository()
    
    func loadUserData() async {
        isLoading = true
        error = nil
        
        do {
            userData = try await repository.fetchUserData()
        } catch {
            self.error = error
            SecureLogger.shared.error("Failed to load user data: \(error.localizedDescription)")
        }
        
        isLoading = false
    }
}

struct SecureLoggingExample {
    func demonstrateSecureLogging() {
        let logger = SecureLogger.shared
        
        logger.info("Application started")
        
        logger.debug("User email: john.doe@example.com")
        
        logger.warning("Failed login attempt from IP: 192.168.1.100")
        
        logger.error("API Key exposed: sk_live_1234567890abcdef")
        
        let complexMessage = """
        User Profile:
        - Email: user@example.com
        - Phone: 555-123-4567
        - SSN: 123-45-6789
        - Credit Card: 4111 1111 1111 1111
        - API Token: Bearer eyJhbGciOiJIUzI1NiJ9
        """
        logger.info(complexMessage)
        
        logger.critical("Security breach detected!")
    }
}