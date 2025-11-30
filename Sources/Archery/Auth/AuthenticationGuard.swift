import SwiftUI

public struct AuthenticationGuard<Content: View, DeniedContent: View>: View {
    @Environment(\.authManager) private var authManager
    private let requirement: AuthRequirement
    private let content: () -> Content
    private let deniedContent: () -> DeniedContent
    
    public init(
        requirement: AuthRequirement = .required,
        @ViewBuilder content: @escaping () -> Content,
        @ViewBuilder denied: @escaping () -> DeniedContent
    ) {
        self.requirement = requirement
        self.content = content
        self.deniedContent = denied
    }
    
    public var body: some View {
        Group {
            if requirement.isSatisfied(by: authManager.state) {
                content()
            } else {
                deniedContent()
            }
        }
        .animation(.default, value: authManager.state.isAuthenticated)
    }
}

public extension AuthenticationGuard where DeniedContent == DefaultDeniedView {
    init(
        requirement: AuthRequirement = .required,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.requirement = requirement
        self.content = content
        self.deniedContent = { DefaultDeniedView(requirement: requirement) }
    }
}

public struct DefaultDeniedView: View {
    @Environment(\.authManager) private var authManager
    let requirement: AuthRequirement
    
    public var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "lock.shield")
                .font(.system(size: 60))
                .foregroundColor(.secondary)
            
            Text("Authentication Required")
                .font(.title)
                .fontWeight(.semibold)
            
            Text(deniedMessage)
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            
            Button("Sign In") {
                Task {
                    try? await authManager.authenticate()
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(authManager.state == .authenticating)
            
            if case .failed(let error) = authManager.state {
                Text(error.localizedDescription)
                    .font(.caption)
                    .foregroundColor(.red)
                    .padding(.horizontal)
            }
        }
        .padding()
    }
    
    private var deniedMessage: String {
        switch requirement {
        case .none, .optional:
            return "This content requires authentication."
        case .required:
            return "Please sign in to access this content."
        case .requiredWithScope(let scope):
            return "This content requires \(scope) permission."
        }
    }
}

public struct AuthenticatedView<Content: View>: View {
    @Environment(\.authManager) private var authManager
    private let requirement: AuthRequirement
    private let content: (any AuthToken) -> Content
    
    public init(
        requirement: AuthRequirement = .required,
        @ViewBuilder content: @escaping (any AuthToken) -> Content
    ) {
        self.requirement = requirement
        self.content = content
    }
    
    public var body: some View {
        AuthenticationGuard(requirement: requirement) {
            if let token = authManager.state.token {
                content(token)
            } else {
                EmptyView()
            }
        }
    }
}

private struct AuthManagerKey: EnvironmentKey {
    static let defaultValue = AuthenticationManager(
        provider: MockAuthProvider()
    )
}

public extension EnvironmentValues {
    var authManager: AuthenticationManager {
        get { self[AuthManagerKey.self] }
        set { self[AuthManagerKey.self] = newValue }
    }
}

public extension View {
    func authenticationManager(_ manager: AuthenticationManager) -> some View {
        environment(\.authManager, manager)
    }
    
    func requiresAuthentication(
        _ requirement: AuthRequirement = .required
    ) -> some View {
        AuthenticationGuard(requirement: requirement) {
            self
        }
    }
}

@ViewModifier
public struct ConditionalAuthModifier: ViewModifier {
    @Environment(\.authManager) private var authManager
    let requirement: AuthRequirement
    
    public func body(content: Content) -> some View {
        content
            .disabled(!requirement.isSatisfied(by: authManager.state))
            .opacity(requirement.isSatisfied(by: authManager.state) ? 1.0 : 0.6)
    }
}