import Foundation

// MARK: - Macro Documentation Data

extension MacroDocumentation {
    
    static let keyValueStore = MacroDocumentation(
        name: "KeyValueStore",
        description: "Generates async/await key-value storage with Codable support and default values.",
        shortDescription: "Type-safe async key-value storage",
        overview: "The @KeyValueStore macro transforms a struct into a persistent storage layer with automatic Codable serialization, async/await API, and configurable backends (UserDefaults, Keychain, SQLite).",
        usage: """
        @KeyValueStore
        struct AppSettings {
            var theme: Theme = .system
            var notificationsEnabled: Bool = true
            var lastSyncDate: Date = .distantPast
        }
        """,
        parameters: [
            Parameter(name: "backend", type: "StorageBackend", description: "Storage backend to use (userDefaults, keychain, sqlite)", defaultValue: "userDefaults"),
            Parameter(name: "suiteName", type: "String?", description: "UserDefaults suite name for app groups", defaultValue: "nil"),
            Parameter(name: "encrypted", type: "Bool", description: "Whether to encrypt stored values", defaultValue: "false")
        ],
        generatedCode: [
            "Async getter/setter methods for each property",
            "Codable conformance for complex types", 
            "Default value initialization",
            "Storage backend abstraction",
            "Thread-safe access methods"
        ],
        examples: [
            Example(
                title: "Basic Usage",
                code: """
                @KeyValueStore
                struct UserPreferences {
                    var username: String = ""
                    var theme: Theme = .light
                    var notifications: Bool = true
                }
                
                // Usage
                let prefs = UserPreferences()
                await prefs.setTheme(.dark)
                let currentTheme = await prefs.theme
                """,
                explanation: "Creates a simple key-value store for user preferences with automatic persistence."
            ),
            Example(
                title: "Encrypted Storage",
                code: """
                @KeyValueStore(backend: .keychain, encrypted: true)
                struct SecureSettings {
                    var apiToken: String = ""
                    var biometricEnabled: Bool = false
                }
                """,
                explanation: "Stores sensitive data encrypted in the Keychain."
            )
        ],
        bestPractices: [
            "Use meaningful default values for all properties",
            "Group related settings in the same store",
            "Use encrypted backend for sensitive data",
            "Keep stores focused and avoid mixing concerns"
        ],
        commonIssues: [
            Issue(issue: "Values not persisting", solution: "Ensure your types conform to Codable or use primitive types"),
            Issue(issue: "App group sharing not working", solution: "Verify suiteName matches your App Group identifier")
        ],
        relatedMacros: ["APIClient"],
        category: .data
    )

    static let observableViewModel = MacroDocumentation(
        name: "ObservableViewModel",
        description: "Generates MainActor-bound ViewModels with lifecycle management and dependency injection.",
        shortDescription: "Type-safe ViewModels with lifecycle",
        overview: "The @ObservableViewModel macro creates ViewModels that are automatically MainActor-bound, include lifecycle methods, dependency injection, and error handling patterns.",
        usage: """
        @ObservableViewModel  
        class TaskListViewModel: ObservableObject {
            @Published var tasks: [Task] = []
            
            // Lifecycle methods and DI are generated
        }
        """,
        parameters: [
            Parameter(name: "dependencies", type: "[String]", description: "Repository dependencies to inject", defaultValue: "[]"),
            Parameter(name: "analytics", type: "Bool", description: "Enable automatic analytics tracking", defaultValue: "true"),
            Parameter(name: "errorHandling", type: "ErrorHandlingStrategy", description: "Error handling approach", defaultValue: ".automatic")
        ],
        generatedCode: [
            "MainActor conformance and thread safety",
            "Dependency injection methods",
            "Lifecycle hooks (onAppear, onDisappear)",
            "Error state management",
            "Analytics integration points"
        ],
        examples: [
            Example(
                title: "ViewModel with Repository",
                code: """
                @ObservableViewModel(dependencies: ["TaskRepository"])
                class TaskListViewModel: ObservableObject {
                    @Published var tasks: [Task] = []
                    @Published var isLoading = false
                    
                    func loadTasks() async {
                        // Repository automatically injected
                    }
                }
                """,
                explanation: "ViewModel with automatic TaskRepository injection and error handling."
            )
        ],
        bestPractices: [
            "Keep ViewModels focused on single responsibilities",
            "Use @Published for UI-bound state",
            "Handle loading and error states explicitly",
            "Leverage automatic analytics tracking"
        ],
        commonIssues: [
            Issue(issue: "Thread safety warnings", solution: "@ObservableViewModel ensures MainActor compliance automatically"),
            Issue(issue: "Dependencies not injected", solution: "Verify repository is registered in EnvContainer")
        ],
        relatedMacros: ["ViewModelBound", "Repository"],
        category: .ui
    )
    
    static let viewModelBound = MacroDocumentation(
        name: "ViewModelBound", 
        description: "Binds Views to ViewModels with automatic dependency injection and lifecycle management.",
        shortDescription: "Automatic View-ViewModel binding",
        overview: "The @ViewModelBound macro automatically creates ViewModel instances, injects dependencies, manages lifecycle, and provides strongly-typed access within Views.",
        usage: """
        @ViewModelBound(TaskListViewModel.self)
        struct TaskListView: View {
            var body: some View {
                // viewModel automatically available
                List(viewModel.tasks) { task in
                    Text(task.title)
                }
            }
        }
        """,
        parameters: [
            Parameter(name: "viewModelType", type: "ViewModel.Type", description: "ViewModel type to bind to this view", defaultValue: nil),
            Parameter(name: "scope", type: "ViewModelScope", description: "ViewModel lifecycle scope", defaultValue: ".view"),
            Parameter(name: "preload", type: "Bool", description: "Load ViewModel data on appear", defaultValue: "true")
        ],
        generatedCode: [
            "ViewModel instance creation and management",
            "Dependency injection wiring",
            "Automatic lifecycle binding",
            "Type-safe viewModel property",
            "Error boundary handling"
        ],
        examples: [
            Example(
                title: "Basic View Binding",
                code: """
                @ViewModelBound(UserProfileViewModel.self)
                struct UserProfileView: View {
                    var body: some View {
                        VStack {
                            Text(viewModel.user.name)
                            Button("Refresh") {
                                Task { await viewModel.refresh() }
                            }
                        }
                        .alert("Error", isPresented: $viewModel.hasError) {
                            Button("OK") { }
                        }
                    }
                }
                """,
                explanation: "View automatically bound to UserProfileViewModel with error handling."
            )
        ],
        bestPractices: [
            "Use specific ViewModel types, avoid generic ones",
            "Handle loading and error states in Views",
            "Leverage automatic lifecycle management",
            "Use appropriate scope for ViewModel lifetime"
        ],
        commonIssues: [
            Issue(issue: "ViewModel not updating", solution: "Ensure ViewModel uses @Published for UI-bound properties"),
            Issue(issue: "Memory leaks", solution: "ViewModelScope.view automatically manages lifecycle")
        ],
        relatedMacros: ["ObservableViewModel", "AppShell"],
        category: .ui
    )
    
    static let appShell = MacroDocumentation(
        name: "AppShell",
        description: "Generates root navigation structure with TabView, NavigationStacks, and deep linking.",
        shortDescription: "Root app navigation and structure",
        overview: "The @AppShell macro creates the main app navigation structure with tabs, navigation stacks, deep link routing, and state restoration.",
        usage: """
        @AppShell
        struct MainApp: App {
            var body: some Scene {
                WindowGroup {
                    // Navigation structure generated
                }
            }
        }
        """,
        parameters: [
            Parameter(name: "tabs", type: "[TabDefinition]", description: "Tab structure definition", defaultValue: "[]"),
            Parameter(name: "deepLinking", type: "Bool", description: "Enable deep link support", defaultValue: "true"),
            Parameter(name: "stateRestoration", type: "Bool", description: "Enable navigation state persistence", defaultValue: "true")
        ],
        generatedCode: [
            "TabView with NavigationStack hierarchy",
            "Deep link URL routing",
            "Navigation state persistence",
            "Tab badge and selection management",
            "Accessibility support"
        ],
        examples: [
            Example(
                title: "Multi-tab App",
                code: """
                @AppShell(tabs: [
                    .init(title: "Home", systemImage: "house", view: HomeView.self),
                    .init(title: "Profile", systemImage: "person", view: ProfileView.self)
                ])
                struct MyApp: App {
                    var body: some Scene {
                        WindowGroup {
                            // TabView automatically generated
                        }
                    }
                }
                """,
                explanation: "Creates a two-tab app with navigation and deep linking support."
            )
        ],
        bestPractices: [
            "Keep tab structure flat and intuitive",
            "Use meaningful system images for tabs",
            "Handle deep links gracefully",
            "Test navigation state restoration"
        ],
        commonIssues: [
            Issue(issue: "Deep links not working", solution: "Verify URL scheme registration in Info.plist"),
            Issue(issue: "State not restoring", solution: "Ensure navigationDestination modifiers are applied correctly")
        ],
        relatedMacros: ["ViewModelBound"],
        category: .ui
    )
    
    static let apiClient = MacroDocumentation(
        name: "APIClient", 
        description: "Generates type-safe API client with async/await, retry logic, and caching.",
        shortDescription: "Type-safe networking with retry",
        overview: "The @APIClient macro creates a complete API client implementation with automatic request/response handling, retry mechanisms, caching, and error recovery.",
        usage: """
        @APIClient(baseURL: "https://api.example.com")
        protocol TaskAPI {
            func getTasks() async throws -> [Task]
            func createTask(_ task: Task) async throws -> Task  
        }
        """,
        parameters: [
            Parameter(name: "baseURL", type: "String", description: "API base URL", defaultValue: nil),
            Parameter(name: "retryCount", type: "Int", description: "Number of retry attempts", defaultValue: "3"),
            Parameter(name: "caching", type: "CachingPolicy", description: "Response caching behavior", defaultValue: ".automatic"),
            Parameter(name: "timeout", type: "TimeInterval", description: "Request timeout", defaultValue: "30.0")
        ],
        generatedCode: [
            "Complete API client implementation",
            "Request/response serialization",
            "Retry logic with exponential backoff",
            "Response caching and invalidation", 
            "Error handling and recovery"
        ],
        examples: [
            Example(
                title: "REST API Client",
                code: """
                @APIClient(baseURL: "https://api.tasks.com", retryCount: 2)
                protocol TaskAPI {
                    func getTasks(page: Int = 0) async throws -> TaskResponse
                    func createTask(_ task: CreateTaskRequest) async throws -> Task
                    func updateTask(id: UUID, _ task: UpdateTaskRequest) async throws -> Task
                    func deleteTask(id: UUID) async throws
                }
                """,
                explanation: "Generates a complete REST API client with CRUD operations for tasks."
            )
        ],
        bestPractices: [
            "Use specific request/response types",
            "Handle network errors gracefully",
            "Implement appropriate caching policies",
            "Use authentication tokens securely"
        ],
        commonIssues: [
            Issue(issue: "Requests timing out", solution: "Adjust timeout parameter or check network conditions"),
            Issue(issue: "Authentication failing", solution: "Verify token handling in NetworkManager configuration")
        ],
        relatedMacros: ["Repository"],
        category: .system
    )
    
    static let designTokens = MacroDocumentation(
        name: "DesignTokens",
        description: "Generates design system tokens from Figma or Style Dictionary input.",
        shortDescription: "Design system token generation",
        overview: "The @DesignTokens macro transforms design tokens from various sources (Figma API, Style Dictionary JSON) into type-safe Swift constants and SwiftUI modifiers.",
        usage: """
        @DesignTokens(source: "design-tokens.json")
        struct AppTokens {
            // Generated from design system
        }
        """,
        parameters: [
            Parameter(name: "source", type: "String", description: "Source file or Figma file URL", defaultValue: nil),
            Parameter(name: "theme", type: "String?", description: "Specific theme to extract", defaultValue: "nil"),
            Parameter(name: "platforms", type: "[Platform]", description: "Target platforms for tokens", defaultValue: "[.iOS, .macOS]")
        ],
        generatedCode: [
            "Color constants from design tokens",
            "Typography styles and modifiers",
            "Spacing and sizing values",
            "SwiftUI view modifiers",
            "Dark mode variants"
        ],
        examples: [
            Example(
                title: "Design System Integration",
                code: """
                @DesignTokens(source: "tokens.json")
                struct DesignSystem {
                    // Auto-generated from design tokens
                }
                
                // Usage
                Text("Hello")
                    .foregroundColor(DesignSystem.Colors.primary)
                    .font(DesignSystem.Typography.headline)
                """,
                explanation: "Generates type-safe design tokens from a JSON file."
            )
        ],
        bestPractices: [
            "Keep design tokens in version control",
            "Use semantic color names",
            "Support both light and dark themes",
            "Validate tokens in CI pipeline"
        ],
        commonIssues: [
            Issue(issue: "Tokens not updating", solution: "Rebuild project after changing source files"),
            Issue(issue: "Figma import failing", solution: "Verify Figma API token and file permissions")
        ],
        relatedMacros: [],
        category: .design
    )
    
    static let formValidation = MacroDocumentation(
        name: "FormValidation",
        description: "Generates form validation with type-safe rules and error handling.",
        shortDescription: "Type-safe form validation",
        overview: "The @FormValidation macro creates comprehensive form validation with reusable rules, custom validators, and automatic error state management.",
        usage: """
        @FormValidation
        struct LoginForm {
            @Required @Email
            var email: String = ""
            
            @Required @MinLength(8)
            var password: String = ""
        }
        """,
        parameters: [
            Parameter(name: "validateOnChange", type: "Bool", description: "Validate as user types", defaultValue: "true"),
            Parameter(name: "showErrors", type: "ErrorDisplayMode", description: "When to show validation errors", defaultValue: ".onSubmit"),
            Parameter(name: "customValidators", type: "[Validator]", description: "Custom validation rules", defaultValue: "[]")
        ],
        generatedCode: [
            "Validation rule implementations",
            "Error state management", 
            "Form submission handling",
            "Field-level validation methods",
            "SwiftUI binding integration"
        ],
        examples: [
            Example(
                title: "Registration Form",
                code: """
                @FormValidation
                struct RegistrationForm {
                    @Required @MinLength(2)
                    var firstName: String = ""
                    
                    @Required @Email
                    var email: String = ""
                    
                    @Required @PasswordStrength
                    var password: String = ""
                    
                    @Required @Matches("password")
                    var confirmPassword: String = ""
                }
                """,
                explanation: "Complete registration form with comprehensive validation."
            )
        ],
        bestPractices: [
            "Provide clear error messages",
            "Validate on appropriate triggers",
            "Use semantic validation rules",
            "Handle async validation carefully"
        ],
        commonIssues: [
            Issue(issue: "Validation not triggering", solution: "Ensure validateOnChange is configured properly"),
            Issue(issue: "Custom validators not working", solution: "Verify validator implementation follows protocol requirements")
        ],
        relatedMacros: ["ObservableViewModel"],
        category: .validation
    )
    
    static let widgetDefinition = MacroDocumentation(
        name: "WidgetDefinition",
        description: "Generates complete WidgetKit integration with timeline providers and entries.",
        shortDescription: "WidgetKit integration generator", 
        overview: "The @WidgetDefinition macro creates all necessary WidgetKit components including timeline provider, entry types, configuration, and widget views.",
        usage: """
        @WidgetDefinition(
            kind: "TaskWidget",
            displayName: "Task Widget",
            description: "Shows your latest tasks"
        )
        struct TaskWidget {
            // Implementation generated
        }
        """,
        parameters: [
            Parameter(name: "kind", type: "String", description: "Widget identifier", defaultValue: nil),
            Parameter(name: "displayName", type: "String", description: "Human-readable widget name", defaultValue: nil),
            Parameter(name: "description", type: "String", description: "Widget description", defaultValue: nil),
            Parameter(name: "families", type: "[String]", description: "Supported widget families", defaultValue: "[\"systemSmall\", \"systemMedium\"]")
        ],
        generatedCode: [
            "Widget conformance implementation",
            "TimelineProvider with data loading",
            "TimelineEntry with ViewModel integration", 
            "Widget configuration handling",
            "Preview providers"
        ],
        examples: [
            Example(
                title: "Task List Widget",
                code: """
                @WidgetDefinition(
                    kind: "com.app.TaskWidget",
                    displayName: "My Tasks", 
                    description: "View your upcoming tasks",
                    families: ["systemSmall", "systemMedium", "systemLarge"]
                )
                struct TaskWidget {
                    // Complete widget implementation generated
                }
                """,
                explanation: "Creates a task widget supporting multiple sizes."
            )
        ],
        bestPractices: [
            "Use unique widget kinds",
            "Support appropriate widget families",
            "Handle data loading efficiently",
            "Provide meaningful preview data"
        ],
        commonIssues: [
            Issue(issue: "Widget not appearing", solution: "Verify widget kind matches configuration and target setup"),
            Issue(issue: "Data not loading", solution: "Check timeline provider implementation and data source availability")
        ],
        relatedMacros: ["Repository", "ObservableViewModel"],
        category: .system
    )
    
    static let appIntent = MacroDocumentation(
        name: "AppIntent",
        description: "Generates App Intents for Shortcuts and Siri integration with parameter validation.",
        shortDescription: "Shortcuts and Siri integration",
        overview: "The @AppIntent macro creates complete App Intent implementations with parameter extraction, validation, execution logic, and Siri phrase suggestions.",
        usage: """
        @AppIntent(
            title: "Add Task",
            description: "Create a new task"
        )
        struct AddTaskIntent {
            @Parameter var title: String
            @Parameter var priority: TaskPriority?
        }
        """,
        parameters: [
            Parameter(name: "title", type: "String", description: "Intent display name", defaultValue: nil),
            Parameter(name: "description", type: "String", description: "Intent description", defaultValue: nil),
            Parameter(name: "needsAuth", type: "Bool", description: "Requires user authentication", defaultValue: "false"),
            Parameter(name: "phrases", type: "[String]", description: "Siri trigger phrases", defaultValue: "[]")
        ],
        generatedCode: [
            "AppIntent protocol conformance",
            "Parameter validation and extraction",
            "Intent execution implementation",
            "Siri shortcut integration",
            "Error handling and user feedback"
        ],
        examples: [
            Example(
                title: "Task Management Intent",
                code: """
                @AppIntent(
                    title: "Complete Task",
                    description: "Mark a task as completed",
                    phrases: ["Complete my task", "Mark task done"]
                )
                struct CompleteTaskIntent {
                    @Parameter(title: "Task") 
                    var task: TaskEntity
                    
                    // Implementation generated with validation
                }
                """,
                explanation: "Creates an intent for completing tasks with Siri integration."
            )
        ],
        bestPractices: [
            "Use clear, natural language phrases",
            "Validate parameters appropriately",
            "Handle errors gracefully",
            "Provide meaningful user feedback"
        ],
        commonIssues: [
            Issue(issue: "Siri not recognizing intent", solution: "Verify phrases are natural and unique"),
            Issue(issue: "Parameter validation failing", solution: "Check parameter types match expected input format")
        ],
        relatedMacros: ["WidgetDefinition", "Repository"],
        category: .system
    )
    
    static let backgroundTask = MacroDocumentation(
        name: "BackgroundTask",
        description: "Generates background task handlers with scheduling and execution logic.",
        shortDescription: "Background task automation",
        overview: "The @BackgroundTask macro creates complete background task implementations with automatic scheduling, execution handling, and integration with the app lifecycle.",
        usage: """
        @BackgroundTask(
            identifier: "com.app.data-sync",
            interval: "hour",
            requiresNetwork: true
        )
        struct DataSyncTask {
            // Implementation generated
        }
        """,
        parameters: [
            Parameter(name: "identifier", type: "String", description: "Background task identifier", defaultValue: nil),
            Parameter(name: "interval", type: "String", description: "Execution interval", defaultValue: "hour"),
            Parameter(name: "requiresNetwork", type: "Bool", description: "Requires network connectivity", defaultValue: "false"),
            Parameter(name: "repositories", type: "[String]", description: "Required repository dependencies", defaultValue: "[]")
        ],
        generatedCode: [
            "BGTask handler implementation",
            "Automatic task scheduling",
            "Repository dependency injection",
            "Progress tracking and cancellation",
            "Error handling and retry logic"
        ],
        examples: [
            Example(
                title: "Data Synchronization",
                code: """
                @BackgroundTask(
                    identifier: "com.app.sync",
                    interval: "6hours",
                    requiresNetwork: true,
                    repositories: ["TaskRepository", "UserRepository"]
                )
                struct SyncTask {
                    // Automatic sync implementation
                }
                """,
                explanation: "Creates a background task that syncs data every 6 hours."
            )
        ],
        bestPractices: [
            "Use descriptive task identifiers",
            "Handle task expiration gracefully",
            "Minimize background execution time",
            "Test background task behavior"
        ],
        commonIssues: [
            Issue(issue: "Tasks not executing", solution: "Verify background modes are enabled in app capabilities"),
            Issue(issue: "Task expiring too quickly", solution: "Optimize task execution time and handle expiration callbacks")
        ],
        relatedMacros: ["Repository"],
        category: .system
    )
}

// MARK: - API Documentation Data

extension APIDocumentation {
    
    static let envContainer = APIDocumentation(
        name: "EnvContainer",
        description: "Dependency injection container for managing service lifecycle and dependencies.",
        shortDescription: "Dependency injection container",
        declaration: """
        public final class EnvContainer {
            public static var shared: EnvContainer
            public init()
        }
        """,
        overview: "EnvContainer provides a lightweight dependency injection system with automatic lifecycle management, scoped instances, and protocol-based registration.",
        methods: [
            Method(
                name: "register",
                signature: "func register<T>(_ type: T.Type, factory: @escaping () -> T)",
                description: "Registers a service factory for the given type.",
                parameters: [
                    Parameter(name: "type", description: "The service type to register"),
                    Parameter(name: "factory", description: "Factory closure that creates service instances")
                ],
                returnDescription: "Void",
                throwsDescription: nil,
                example: """
                container.register(UserRepository.self) { 
                    UserRepository() 
                }
                """
            ),
            Method(
                name: "resolve", 
                signature: "func resolve<T>(_ type: T.Type) -> T?",
                description: "Resolves a service instance of the specified type.",
                parameters: [
                    Parameter(name: "type", description: "The service type to resolve")
                ],
                returnDescription: "Service instance or nil if not registered",
                throwsDescription: nil,
                example: """
                let repository = container.resolve(UserRepository.self)
                """
            )
        ],
        properties: [
            Property(name: "shared", type: "EnvContainer", description: "Global shared container instance")
        ],
        relatedTypes: ["DataRepository", "ObservableViewModel"]
    )
    
    static let dataRepository = APIDocumentation(
        name: "DataRepository", 
        description: "Protocol defining standard CRUD operations for data repositories.",
        shortDescription: "Repository protocol for data access",
        declaration: """
        public protocol DataRepository {
            associatedtype Model: Identifiable & Codable
            
            func fetch(id: Model.ID) async throws -> Model
            func fetchAll() async throws -> [Model]
            func save(_ model: Model) async throws
            func delete(id: Model.ID) async throws
        }
        """,
        overview: "DataRepository provides a standard interface for data access with async/await support, error handling, and type safety.",
        methods: [
            Method(
                name: "fetch",
                signature: "func fetch(id: Model.ID) async throws -> Model",
                description: "Fetches a single entity by its identifier.",
                parameters: [
                    Parameter(name: "id", description: "Unique identifier for the entity")
                ],
                returnDescription: "The requested entity",
                throwsDescription: "RepositoryError if entity not found or network error",
                example: """
                let user = try await repository.fetch(id: userId)
                """
            ),
            Method(
                name: "fetchAll",
                signature: "func fetchAll() async throws -> [Model]",
                description: "Fetches all entities of this type.",
                parameters: [],
                returnDescription: "Array of all entities",
                throwsDescription: "RepositoryError for network or data errors",
                example: """
                let allTasks = try await repository.fetchAll()
                """
            )
        ],
        properties: [],
        relatedTypes: ["EnvContainer", "NetworkManager"]
    )
    
    static let networkManager = APIDocumentation(
        name: "NetworkManager",
        description: "HTTP networking layer with automatic retry, caching, and error handling.",
        shortDescription: "HTTP networking with retry and caching",
        declaration: """
        public final class NetworkManager {
            public static let shared: NetworkManager
            public func configure(baseURL: String, headers: [String: String] = [:])
        }
        """,
        overview: "NetworkManager provides a robust HTTP client with automatic retries, response caching, authentication handling, and comprehensive error recovery.",
        methods: [
            Method(
                name: "get",
                signature: "func get<T: Codable>(_ path: String, type: T.Type) async throws -> T",
                description: "Performs a GET request and decodes the response.",
                parameters: [
                    Parameter(name: "path", description: "API endpoint path"),
                    Parameter(name: "type", description: "Expected response type")
                ],
                returnDescription: "Decoded response object",
                throwsDescription: "NetworkError for HTTP errors or decoding failures",
                example: """
                let users = try await networkManager.get("/users", type: [User].self)
                """
            ),
            Method(
                name: "post",
                signature: "func post<T: Codable, R: Codable>(_ path: String, body: T) async throws -> R",
                description: "Performs a POST request with a request body.",
                parameters: [
                    Parameter(name: "path", description: "API endpoint path"),
                    Parameter(name: "body", description: "Request body to encode and send")
                ],
                returnDescription: "Decoded response object",
                throwsDescription: "NetworkError for HTTP errors or encoding/decoding failures",
                example: """
                let newUser = try await networkManager.post("/users", body: createUserRequest)
                """
            )
        ],
        properties: [
            Property(name: "shared", type: "NetworkManager", description: "Global shared network manager instance")
        ],
        relatedTypes: ["DataRepository", "APIClient"]
    )
    
    static let analyticsManager = APIDocumentation(
        name: "AnalyticsManager",
        description: "Privacy-focused analytics tracking with automatic PII redaction.",
        shortDescription: "Privacy-focused analytics tracking",
        declaration: """
        public final class AnalyticsManager {
            public static var shared: AnalyticsManager?
            public func track(event: String, properties: [String: Any] = [:])
        }
        """,
        overview: "AnalyticsManager provides privacy-compliant analytics tracking with automatic PII detection and redaction, batched uploads, and offline support.",
        methods: [
            Method(
                name: "track",
                signature: "func track(event: String, properties: [String: Any] = [:])",
                description: "Tracks an analytics event with optional properties.",
                parameters: [
                    Parameter(name: "event", description: "Event name to track"),
                    Parameter(name: "properties", description: "Additional event properties (PII is automatically redacted)")
                ],
                returnDescription: "Void",
                throwsDescription: nil,
                example: """
                AnalyticsManager.shared?.track(
                    event: "user_signed_in",
                    properties: ["method": "email"]
                )
                """
            )
        ],
        properties: [
            Property(name: "shared", type: "AnalyticsManager?", description: "Global analytics manager instance")
        ],
        relatedTypes: []
    )
    
    static let widgetSupport = APIDocumentation(
        name: "WidgetSupport",
        description: "WidgetKit integration helpers and timeline management.",
        shortDescription: "WidgetKit integration utilities",
        declaration: """
        public protocol ArcheryTimelineProvider: TimelineProvider {
            var container: EnvContainer { get }
            func createEntry(for configuration: Intent?, at date: Date) async -> Entry
        }
        """,
        overview: "Widget support provides seamless integration between WidgetKit and Archery's dependency injection system with shared ViewModels.",
        methods: [
            Method(
                name: "createEntry",
                signature: "func createEntry(for configuration: Intent?, at date: Date) async -> Entry",
                description: "Creates a timeline entry for widget display.",
                parameters: [
                    Parameter(name: "configuration", description: "Widget configuration intent"),
                    Parameter(name: "date", description: "Entry timestamp")
                ],
                returnDescription: "Timeline entry with data and metadata",
                throwsDescription: nil,
                example: """
                let entry = await provider.createEntry(for: nil, at: Date())
                """
            )
        ],
        properties: [
            Property(name: "container", type: "EnvContainer", description: "Dependency injection container for widget data access")
        ],
        relatedTypes: ["EnvContainer", "DataRepository"]
    )
    
    static let backgroundTasks = APIDocumentation(
        name: "BackgroundTaskManager", 
        description: "Background task scheduling and execution coordination.",
        shortDescription: "Background task management",
        declaration: """
        public final class BackgroundTaskManager {
            public static let shared: BackgroundTaskManager
            public func register<Handler: BackgroundTaskHandler>(taskId: String, handler: Handler.Type)
        }
        """,
        overview: "BackgroundTaskManager coordinates background task execution with automatic scheduling, retry logic, and integration with app lifecycle events.",
        methods: [
            Method(
                name: "register",
                signature: "func register<Handler: BackgroundTaskHandler>(taskId: String, handler: Handler.Type)",
                description: "Registers a background task handler.",
                parameters: [
                    Parameter(name: "taskId", description: "Unique background task identifier"),
                    Parameter(name: "handler", description: "Handler type that implements task execution")
                ],
                returnDescription: "Void",
                throwsDescription: nil,
                example: """
                manager.register(taskId: "com.app.sync", handler: DataSyncTask.self)
                """
            ),
            Method(
                name: "scheduleAppRefresh",
                signature: "func scheduleAppRefresh(identifier: String, earliestBeginDate: Date?) throws",
                description: "Schedules a background app refresh task.",
                parameters: [
                    Parameter(name: "identifier", description: "Background task identifier"),
                    Parameter(name: "earliestBeginDate", description: "Earliest execution time")
                ],
                returnDescription: "Void", 
                throwsDescription: "BackgroundTaskError if scheduling fails",
                example: """
                try manager.scheduleAppRefresh(
                    identifier: "com.app.sync",
                    earliestBeginDate: Date().addingTimeInterval(3600)
                )
                """
            )
        ],
        properties: [
            Property(name: "shared", type: "BackgroundTaskManager", description: "Global background task manager instance")
        ],
        relatedTypes: ["DataRepository"]
    )
}