import SwiftUI
import Archery

// MARK: - Authentication View with @ViewModelBound

@ViewModelBound(viewModel: AuthViewModel.self)
struct AuthenticationView: View {
    @StateObject var vm: AuthViewModel
    @State private var showingSignUp = false
    @State private var showingForgotPassword = false
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                // Logo and branding
                Image(systemName: "target")
                    .font(.system(size: 80))
                    .foregroundStyle(.accent)
                    .padding(.top, 60)
                
                Text("Archery Showcase")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                
                Text("Macro-powered SwiftUI Architecture")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                
                Spacer()
                
                // Login form
                VStack(spacing: 16) {
                    TextField("Email", text: $vm.email)
                        .textFieldStyle(.roundedBorder)
                        .textContentType(.emailAddress)
                        .autocapitalization(.none)
                        .disabled(vm.isLoading)
                    
                    SecureField("Password", text: $vm.password)
                        .textFieldStyle(.roundedBorder)
                        .textContentType(.password)
                        .disabled(vm.isLoading)
                    
                    if let error = vm.error {
                        Text(error.localizedDescription)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    
                    Button(action: { Task { await vm.login() } }) {
                        HStack {
                            if vm.isLoading {
                                ProgressView()
                                    .progressViewStyle(.circular)
                                    .scaleEffect(0.8)
                            } else {
                                Text("Sign In")
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(vm.isLoading || !vm.isValid)
                    
                    HStack {
                        Button("Forgot Password?") {
                            showingForgotPassword = true
                        }
                        .font(.caption)
                        
                        Spacer()
                        
                        Button("Create Account") {
                            showingSignUp = true
                        }
                        .font(.caption)
                    }
                    .padding(.horizontal, 4)
                }
                .padding(.horizontal, 32)
                
                Divider()
                    .padding(.vertical)
                
                // Social login options
                VStack(spacing: 12) {
                    Button(action: { Task { await vm.loginWithApple() } }) {
                        Label("Sign in with Apple", systemImage: "apple.logo")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                    .buttonStyle(.bordered)
                    
                    Button(action: { Task { await vm.loginWithGoogle() } }) {
                        Label("Sign in with Google", systemImage: "globe")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                    .buttonStyle(.bordered)
                }
                .padding(.horizontal, 32)
                
                Spacer()
                
                // Demo mode
                Button("Continue with Demo Account") {
                    Task { await vm.loginAsDemo() }
                }
                .font(.caption)
                .padding(.bottom, 32)
            }
            .navigationBarHidden(true)
            .sheet(isPresented: $showingSignUp) {
                SignUpView()
            }
            .sheet(isPresented: $showingForgotPassword) {
                ForgotPasswordView()
            }
        }
    }
}

// MARK: - Auth ViewModel with @ObservableViewModel

@ObservableViewModel
class AuthViewModel: ObservableObject {
    @Published var email = ""
    @Published var password = ""
    @Published var isLoading = false
    @Published var error: AuthError?
    
    @Injected private var authRepository: AuthRepository
    @Injected private var analyticsService: AnalyticsService
    @Injected private var keychainStore: KeychainStore
    
    var isValid: Bool {
        !email.isEmpty && !password.isEmpty && email.contains("@")
    }
    
    @MainActor
    func login() async {
        isLoading = true
        error = nil
        
        do {
            let credentials = try await authRepository.login(
                email: email,
                password: password
            )
            
            // Store tokens securely
            try await keychainStore.store(
                credentials.accessToken,
                for: .accessToken
            )
            try await keychainStore.store(
                credentials.refreshToken,
                for: .refreshToken
            )
            
            // Track successful login
            analyticsService.track(.userLoggedIn(method: "email"))
            
            // Update auth state
            await AuthManager.shared.setAuthenticated(true, user: credentials.user)
            
        } catch let authError as AuthError {
            error = authError
            analyticsService.track(.loginFailed(reason: authError.analyticsReason))
        } catch {
            self.error = .unknown(error)
        }
        
        isLoading = false
    }
    
    @MainActor
    func loginWithApple() async {
        isLoading = true
        error = nil
        
        do {
            let credentials = try await authRepository.loginWithApple()
            try await storeCredentials(credentials)
            analyticsService.track(.userLoggedIn(method: "apple"))
            await AuthManager.shared.setAuthenticated(true, user: credentials.user)
        } catch {
            error = .socialLoginFailed("Apple")
        }
        
        isLoading = false
    }
    
    @MainActor
    func loginWithGoogle() async {
        isLoading = true
        error = nil
        
        do {
            let credentials = try await authRepository.loginWithGoogle()
            try await storeCredentials(credentials)
            analyticsService.track(.userLoggedIn(method: "google"))
            await AuthManager.shared.setAuthenticated(true, user: credentials.user)
        } catch {
            error = .socialLoginFailed("Google")
        }
        
        isLoading = false
    }
    
    @MainActor
    func loginAsDemo() async {
        isLoading = true
        
        // Create demo credentials
        let demoUser = User(
            id: "demo-user",
            email: "demo@archery.app",
            name: "Demo User",
            avatar: nil,
            subscription: .premium
        )
        
        let demoCredentials = AuthCredentials(
            user: demoUser,
            accessToken: "demo-access-token",
            refreshToken: "demo-refresh-token"
        )
        
        try? await storeCredentials(demoCredentials)
        analyticsService.track(.userLoggedIn(method: "demo"))
        await AuthManager.shared.setAuthenticated(true, user: demoUser)
        
        isLoading = false
    }
    
    private func storeCredentials(_ credentials: AuthCredentials) async throws {
        try await keychainStore.store(credentials.accessToken, for: .accessToken)
        try await keychainStore.store(credentials.refreshToken, for: .refreshToken)
    }
}

// MARK: - Auth Manager

@MainActor
class AuthManager: ObservableObject {
    static let shared = AuthManager()
    
    @Published var isAuthenticated = false
    @Published var currentUser: User?
    
    @Injected private var authRepository: AuthRepository
    @Injected private var keychainStore: KeychainStore
    
    func setAuthenticated(_ authenticated: Bool, user: User? = nil) async {
        isAuthenticated = authenticated
        currentUser = user
    }
    
    func refreshTokenIfNeeded() async {
        guard let refreshToken = try? await keychainStore.retrieve(for: .refreshToken) else {
            return
        }
        
        do {
            let credentials = try await authRepository.refreshToken(refreshToken)
            try await keychainStore.store(credentials.accessToken, for: .accessToken)
            currentUser = credentials.user
        } catch {
            // Token refresh failed, log out
            await logout()
        }
    }
    
    func logout() async {
        try? await keychainStore.delete(for: .accessToken)
        try? await keychainStore.delete(for: .refreshToken)
        isAuthenticated = false
        currentUser = nil
    }
}