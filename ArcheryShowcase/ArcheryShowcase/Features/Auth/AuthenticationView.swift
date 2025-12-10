import SwiftUI
import Archery
import AuthenticationServices

// MARK: - Authentication View

struct AuthenticationView: View {
    @State private var email = ""
    @State private var password = ""
    @State private var isLoading = false
    @State private var showingSignUp = false
    @State private var showingForgotPassword = false
    @State private var error: AuthError?
    @EnvironmentObject var themeManager: ThemeManager

    var body: some View {
        ScrollView {
            VStack(spacing: 32) {
                // Logo/Header
                VStack(spacing: 8) {
                    Image(systemName: "target")
                        .font(.system(size: 60))
                        .foregroundStyle(Color.accentColor)

                    Text("Archery")
                        .font(.largeTitle)
                        .fontWeight(.bold)

                    Text("Macro-powered SwiftUI Architecture")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 40)

                // Login Form
                VStack(spacing: 16) {
                    TextField("Email", text: $email)
                        .textFieldStyle(.roundedBorder)
                        .textContentType(.emailAddress)
                        .autocapitalization(.none)
                        .keyboardType(.emailAddress)

                    SecureField("Password", text: $password)
                        .textFieldStyle(.roundedBorder)
                        .textContentType(.password)

                    // Error message
                    if let error = error {
                        Text(error.errorDescription ?? "An error occurred")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }

                    // Login button
                    Button(action: login) {
                        HStack {
                            if isLoading {
                                ProgressView()
                                    .tint(.white)
                            }
                            Text("Sign In")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(isLoading || email.isEmpty || password.isEmpty)

                    // Forgot password
                    Button("Forgot Password?") {
                        showingForgotPassword = true
                    }
                    .font(.caption)
                }
                .padding(.horizontal)

                // Divider
                HStack {
                    Rectangle()
                        .fill(Color.secondary.opacity(0.3))
                        .frame(height: 1)
                    Text("or continue with")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Rectangle()
                        .fill(Color.secondary.opacity(0.3))
                        .frame(height: 1)
                }
                .padding(.horizontal)

                // Social Login
                VStack(spacing: 12) {
                    SignInWithAppleButton(.signIn) { request in
                        request.requestedScopes = [.email, .fullName]
                    } onCompletion: { _ in
                        // Handle Apple sign in
                    }
                    .signInWithAppleButtonStyle(.black)
                    .frame(height: 50)
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                    Button(action: {}) {
                        HStack {
                            Image(systemName: "g.circle.fill")
                            Text("Sign in with Google")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                }
                .padding(.horizontal)

                // Sign up link
                HStack {
                    Text("Don't have an account?")
                        .foregroundStyle(.secondary)
                    Button("Sign Up") {
                        showingSignUp = true
                    }
                }
                .font(.callout)
            }
            .padding(.bottom, 32)
        }
        .navigationTitle("")
        .navigationBarHidden(true)
        .sheet(isPresented: $showingSignUp) {
            NavigationStack {
                SignUpView()
            }
        }
        .sheet(isPresented: $showingForgotPassword) {
            NavigationStack {
                ForgotPasswordView()
            }
        }
    }

    private func login() {
        isLoading = true
        error = nil

        // Simulate login
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            isLoading = false
            // For demo, just show success or error based on email
            if email.contains("@") {
                // Success - in real app would update auth state
            } else {
                error = .invalidCredentials
            }
        }
    }
}

// MARK: - Preview

#Preview {
    AuthenticationView()
        .environmentObject(ThemeManager())
}
