import SwiftUI
import Archery

// MARK: - Main App with @AppShell

@main
@AppShell(
    tabs: [
        .init(title: "Dashboard", systemImage: "chart.line.uptrend.xyaxis", view: DashboardView.self),
        .init(title: "Tasks", systemImage: "checklist", view: TaskListView.self),
        .init(title: "Forms", systemImage: "doc.text", view: FormExamplesView.self),
        .init(title: "Settings", systemImage: "gear", view: SettingsView.self)
    ],
    sheets: [
        .init(id: "taskDetail", view: TaskDetailView.self),
        .init(id: "profile", view: ProfileView.self)
    ],
    fullScreenCovers: [
        .init(id: "onboarding", view: OnboardingFlow.self),
        .init(id: "subscription", view: SubscriptionView.self)
    ]
)
struct ArcheryShowcaseApp: App {
    @StateObject private var container = EnvContainer()
    @StateObject private var authManager = AuthManager()
    @StateObject private var themeManager = ThemeManager()
    @StateObject private var analyticsManager = AnalyticsManager()
    
    init() {
        // Configure app-wide settings
        configureAppearance()
        configureAnalytics()
    }
    
    var body: some Scene {
        WindowGroup {
            Group {
                if authManager.isAuthenticated {
                    GeneratedAppShell()
                        .environmentObject(container)
                        .environmentObject(authManager)
                        .environmentObject(themeManager)
                        .task {
                            await authManager.refreshTokenIfNeeded()
                        }
                } else {
                    AuthenticationView()
                        .environmentObject(authManager)
                        .environmentObject(themeManager)
                }
            }
            .environment(\.designTokens, themeManager.currentTokens)
            .onAppear {
                Task {
                    await container.bootstrap()
                }
            }
        }
        #if os(macOS)
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unified)
        #endif
        
        #if os(iOS)
        // Widget configuration scene
        .widgetConfigurationDisplayName("Archery Widgets")
        #endif
    }
    
    private func configureAppearance() {
        #if os(iOS)
        UINavigationBar.appearance().largeTitleTextAttributes = [
            .font: UIFont.systemFont(ofSize: 34, weight: .bold)
        ]
        #endif
    }
    
    private func configureAnalytics() {
        analyticsManager.configure(
            providers: [
                .amplitude(apiKey: ProcessInfo.processInfo.environment["AMPLITUDE_KEY"] ?? "demo"),
                .segment(writeKey: ProcessInfo.processInfo.environment["SEGMENT_KEY"] ?? "demo")
            ]
        )
    }
}

// MARK: - Environment Container Setup

extension EnvContainer {
    func bootstrap() async {
        // Register repositories
        register(TaskRepository.self, TaskRepository())
        register(UserRepository.self, UserRepository())
        register(ProjectRepository.self, ProjectRepository())
        
        // Register stores
        register(UserPreferencesStore.self, UserPreferencesStore())
        register(CacheStore.self, CacheStore())
        
        // Register services
        register(NetworkService.self, NetworkService())
        register(PersistenceService.self, PersistenceService())
        register(NotificationService.self, NotificationService())
        
        // Configure feature flags
        FeatureFlags.shared.configure(
            provider: .launchDarkly(key: ProcessInfo.processInfo.environment["LAUNCHDARKLY_KEY"] ?? "demo")
        )
    }
}