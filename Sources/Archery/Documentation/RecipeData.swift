import Foundation

// MARK: - Recipe Documentation Data

extension Recipe {
    
    static let authGate = Recipe(
        title: "Authentication Gate",
        description: "Implement app-wide authentication with automatic redirection and state persistence.",
        shortDescription: "Protect app content behind authentication",
        problem: "You need to ensure users are authenticated before accessing app content, with seamless sign-in flow and persistent session management.",
        solution: "Use Archery's authentication patterns with @ObservableViewModel for auth state, @KeyValueStore for token persistence, and conditional view rendering.",
        steps: [
            Step(
                title: "Create Auth Manager",
                description: "Set up an authentication manager with observable state.",
                code: """
                @ObservableViewModel
                class AuthManager: ObservableObject {
                    @Published var isAuthenticated: Bool = false
                    @Published var currentUser: User?
                    @Published var isLoading: Bool = false
                    
                    private let authStore = AuthTokenStore()
                    private let userRepository: UserRepository
                    
                    init(userRepository: UserRepository) {
                        self.userRepository = userRepository
                        checkExistingAuth()
                    }
                    
                    func checkExistingAuth() {
                        Task {
                            isLoading = true
                            if let token = await authStore.token, !token.isEmpty {
                                await validateToken(token)
                            }
                            isLoading = false
                        }
                    }
                }
                """,
                explanation: "AuthManager handles authentication state with automatic token validation on app launch."
            ),
            Step(
                title: "Add Token Storage",
                description: "Create secure storage for authentication tokens.",
                code: """
                @KeyValueStore(backend: .keychain, encrypted: true)
                struct AuthTokenStore {
                    var token: String = ""
                    var refreshToken: String = ""
                    var expiresAt: Date = .distantPast
                    
                    var isValid: Bool {
                        token.isEmpty == false && expiresAt > Date()
                    }
                }
                """,
                explanation: "Tokens are stored securely in the Keychain with encryption and expiration tracking."
            ),
            Step(
                title: "Implement Sign-In Flow",
                description: "Add authentication methods to the auth manager.",
                code: """
                extension AuthManager {
                    func signIn(email: String, password: String) async throws {
                        isLoading = true
                        defer { isLoading = false }
                        
                        let request = SignInRequest(email: email, password: password)
                        let response = try await userRepository.signIn(request)
                        
                        await authStore.setToken(response.accessToken)
                        await authStore.setRefreshToken(response.refreshToken)
                        await authStore.setExpiresAt(response.expiresAt)
                        
                        currentUser = response.user
                        isAuthenticated = true
                        
                        AnalyticsManager.shared?.track(event: "user_signed_in")
                    }
                    
                    func signOut() async {
                        await authStore.setToken("")
                        await authStore.setRefreshToken("")
                        currentUser = nil
                        isAuthenticated = false
                        
                        AnalyticsManager.shared?.track(event: "user_signed_out")
                    }
                }
                """,
                explanation: "Sign-in handles token storage, user state, and analytics tracking."
            ),
            Step(
                title: "Create Auth Gate View",
                description: "Build a conditional view that shows authentication or main content.",
                code: """
                struct AuthGateView<Content: View>: View {
                    @EnvironmentObject var authManager: AuthManager
                    let content: Content
                    
                    init(@ViewBuilder content: () -> Content) {
                        self.content = content()
                    }
                    
                    var body: some View {
                        Group {
                            if authManager.isLoading {
                                LoadingView()
                            } else if authManager.isAuthenticated {
                                content
                                    .transition(.opacity.combined(with: .scale))
                            } else {
                                SignInView()
                                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                            }
                        }
                        .animation(.easeInOut(duration: 0.3), value: authManager.isAuthenticated)
                    }
                }
                """,
                explanation: "AuthGateView conditionally shows content based on authentication state with smooth transitions."
            ),
            Step(
                title: "Integrate with App Structure",
                description: "Use the auth gate in your main app structure.",
                code: """
                @main
                struct MyApp: App {
                    @StateObject private var authManager = AuthManager()
                    @StateObject private var container = EnvContainer()
                    
                    var body: some Scene {
                        WindowGroup {
                            AuthGateView {
                                MainAppView()
                                    .environmentObject(container)
                            }
                            .environmentObject(authManager)
                            .onAppear {
                                container.register(AuthManager.self) { authManager }
                            }
                        }
                    }
                }
                """,
                explanation: "The auth gate wraps your main app content and provides authentication context."
            )
        ],
        completeExample: """
        // Complete authentication gate implementation
        @main
        struct SecureApp: App {
            @StateObject private var authManager = AuthManager()
            
            var body: some Scene {
                WindowGroup {
                    AuthGateView {
                        TabView {
                            HomeView()
                                .tabItem { Label("Home", systemImage: "house") }
                            ProfileView()
                                .tabItem { Label("Profile", systemImage: "person") }
                        }
                    }
                    .environmentObject(authManager)
                }
            }
        }
        
        @ViewModelBound(SignInViewModel.self)
        struct SignInView: View {
            var body: some View {
                VStack(spacing: 20) {
                    TextField("Email", text: $viewModel.email)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                    
                    SecureField("Password", text: $viewModel.password)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                    
                    Button("Sign In") {
                        Task { await viewModel.signIn() }
                    }
                    .disabled(!viewModel.isValid || viewModel.isLoading)
                }
                .padding()
            }
        }
        """,
        testExample: """
        @MainActor
        class AuthManagerTests: XCTestCase {
            var authManager: AuthManager!
            var mockUserRepository: MockUserRepository!
            
            override func setUp() async throws {
                mockUserRepository = MockUserRepository()
                authManager = AuthManager(userRepository: mockUserRepository)
            }
            
            func testSuccessfulSignIn() async throws {
                mockUserRepository.signInResult = SignInResponse(
                    accessToken: "token123",
                    user: User(id: UUID(), email: "test@example.com")
                )
                
                try await authManager.signIn(email: "test@example.com", password: "password")
                
                XCTAssertTrue(authManager.isAuthenticated)
                XCTAssertNotNil(authManager.currentUser)
            }
            
            func testSignOut() async throws {
                authManager.isAuthenticated = true
                
                await authManager.signOut()
                
                XCTAssertFalse(authManager.isAuthenticated)
                XCTAssertNil(authManager.currentUser)
            }
        }
        """,
        bestPractices: [
            "Store tokens securely in Keychain, never UserDefaults",
            "Implement token refresh logic to maintain sessions",
            "Use biometric authentication when available",
            "Handle network failures gracefully with retry logic",
            "Clear sensitive data completely on sign out"
        ],
        commonPitfalls: [
            Recipe.Issue(
                issue: "Tokens stored insecurely",
                solution: "Always use @KeyValueStore with .keychain backend for sensitive data"
            ),
            Recipe.Issue(
                issue: "Authentication state not persisting",
                solution: "Check token validation logic and ensure proper async/await usage"
            )
        ],
        relatedRecipes: ["Offline Sync", "Validated Form"],
        category: .gettingStarted
    )
    
    static let paginatedList = Recipe(
        title: "Paginated List",
        description: "Implement infinite scrolling lists with automatic loading and error handling.",
        shortDescription: "Infinite scroll with pagination",
        problem: "You need to display large datasets efficiently with smooth scrolling and automatic loading of more content.",
        solution: "Use @Repository for data fetching, @ObservableViewModel for state management, and SwiftUI's onAppear for pagination triggers.",
        steps: [
            Step(
                title: "Create Paginated Repository",
                description: "Extend your repository to support pagination.",
                code: """
                extension TaskRepository {
                    func fetchTasks(page: Int, pageSize: Int = 20) async throws -> PagedResponse<Task> {
                        let response = try await networkManager.get(
                            "/tasks?page=\\(page)&limit=\\(pageSize)",
                            type: PagedResponse<Task>.self
                        )
                        return response
                    }
                }
                
                struct PagedResponse<T: Codable>: Codable {
                    let items: [T]
                    let currentPage: Int
                    let totalPages: Int
                    let hasNextPage: Bool
                    let totalCount: Int
                }
                """,
                explanation: "Repository method returns paginated data with metadata about pagination state."
            ),
            Step(
                title: "Setup Paginated ViewModel",
                description: "Create a ViewModel that manages pagination state.",
                code: """
                @ObservableViewModel(dependencies: ["TaskRepository"])
                class TaskListViewModel: ObservableObject {
                    @Published var tasks: [Task] = []
                    @Published var isLoading = false
                    @Published var isLoadingMore = false
                    @Published var hasMorePages = true
                    @Published var error: AppError?
                    
                    private var currentPage = 0
                    private let pageSize = 20
                    private var repository: TaskRepository { container.resolve(TaskRepository.self)! }
                    
                    @MainActor
                    func loadInitialTasks() async {
                        guard !isLoading else { return }
                        
                        isLoading = true
                        error = nil
                        currentPage = 0
                        
                        do {
                            let response = try await repository.fetchTasks(page: currentPage, pageSize: pageSize)
                            tasks = response.items
                            hasMorePages = response.hasNextPage
                            currentPage += 1
                        } catch {
                            self.error = AppError.from(error)
                        }
                        
                        isLoading = false
                    }
                }
                """,
                explanation: "ViewModel tracks pagination state and handles initial data loading with error management."
            ),
            Step(
                title: "Implement Load More Logic",
                description: "Add method to load additional pages of data.",
                code: """
                extension TaskListViewModel {
                    @MainActor
                    func loadMoreTasksIfNeeded(for task: Task) async {
                        guard let lastTask = tasks.last,
                              lastTask.id == task.id,
                              hasMorePages,
                              !isLoadingMore else { return }
                        
                        isLoadingMore = true
                        
                        do {
                            let response = try await repository.fetchTasks(page: currentPage, pageSize: pageSize)
                            tasks.append(contentsOf: response.items)
                            hasMorePages = response.hasNextPage
                            currentPage += 1
                            
                            AnalyticsManager.shared?.track(
                                event: "pagination_loaded",
                                properties: [
                                    "page": currentPage,
                                    "total_items": tasks.count
                                ]
                            )
                        } catch {
                            self.error = AppError.from(error)
                        }
                        
                        isLoadingMore = false
                    }
                    
                    func refresh() async {
                        await loadInitialTasks()
                    }
                }
                """,
                explanation: "Load more is triggered when user scrolls to the last item, with analytics tracking."
            ),
            Step(
                title: "Build Paginated List View", 
                description: "Create a SwiftUI view with infinite scrolling.",
                code: """
                @ViewModelBound(TaskListViewModel.self)
                struct TaskListView: View {
                    var body: some View {
                        NavigationView {
                            List {
                                ForEach(viewModel.tasks) { task in
                                    TaskRowView(task: task)
                                        .onAppear {
                                            Task {
                                                await viewModel.loadMoreTasksIfNeeded(for: task)
                                            }
                                        }
                                }
                                
                                if viewModel.isLoadingMore {
                                    HStack {
                                        Spacer()
                                        ProgressView()
                                            .scaleEffect(0.8)
                                        Spacer()
                                    }
                                    .listRowSeparator(.hidden)
                                }
                            }
                            .navigationTitle("Tasks")
                            .refreshable {
                                await viewModel.refresh()
                            }
                            .task {
                                await viewModel.loadInitialTasks()
                            }
                            .alert("Error", isPresented: Binding<Bool>(
                                get: { viewModel.error != nil },
                                set: { _ in viewModel.error = nil }
                            )) {
                                Button("Retry") {
                                    Task { await viewModel.loadInitialTasks() }
                                }
                                Button("Cancel", role: .cancel) { }
                            } message: {
                                Text(viewModel.error?.localizedDescription ?? "")
                            }
                        }
                    }
                }
                """,
                explanation: "List view with pagination trigger, loading indicator, pull-to-refresh, and error handling."
            )
        ],
        completeExample: """
        // Complete paginated list implementation
        @ViewModelBound(ProductListViewModel.self)
        struct ProductListView: View {
            @State private var searchText = ""
            
            var body: some View {
                NavigationView {
                    List {
                        ForEach(viewModel.filteredProducts(searchText: searchText)) { product in
                            ProductRowView(product: product)
                                .onAppear {
                                    Task {
                                        await viewModel.loadMoreIfNeeded(for: product)
                                    }
                                }
                        }
                        
                        if viewModel.isLoadingMore && viewModel.hasMorePages {
                            LoadingRowView()
                        }
                    }
                    .searchable(text: $searchText)
                    .navigationTitle("Products")
                    .refreshable {
                        await viewModel.refresh()
                    }
                    .task {
                        await viewModel.loadInitialProducts()
                    }
                    .errorAlert(error: viewModel.error) {
                        await viewModel.retry()
                    }
                }
            }
        }
        
        struct LoadingRowView: View {
            var body: some View {
                HStack {
                    Spacer()
                    ProgressView()
                    Text("Loading more...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .listRowSeparator(.hidden)
            }
        }
        """,
        testExample: """
        @MainActor
        class TaskListViewModelTests: XCTestCase {
            var viewModel: TaskListViewModel!
            var mockRepository: MockTaskRepository!
            
            override func setUp() async throws {
                mockRepository = MockTaskRepository()
                viewModel = TaskListViewModel(container: EnvContainer())
                viewModel.container.register(TaskRepository.self) { mockRepository }
            }
            
            func testLoadInitialTasks() async throws {
                let mockTasks = (1...20).map { Task(title: "Task \\($0)") }
                mockRepository.pagedResponse = PagedResponse(
                    items: mockTasks,
                    currentPage: 0,
                    totalPages: 5,
                    hasNextPage: true,
                    totalCount: 100
                )
                
                await viewModel.loadInitialTasks()
                
                XCTAssertEqual(viewModel.tasks.count, 20)
                XCTAssertTrue(viewModel.hasMorePages)
                XCTAssertFalse(viewModel.isLoading)
            }
            
            func testLoadMoreTasks() async throws {
                // Setup initial state
                viewModel.tasks = (1...20).map { Task(title: "Task \\($0)") }
                viewModel.hasMorePages = true
                
                let moreTasks = (21...40).map { Task(title: "Task \\($0)") }
                mockRepository.pagedResponse = PagedResponse(
                    items: moreTasks,
                    currentPage: 1,
                    totalPages: 5,
                    hasNextPage: true,
                    totalCount: 100
                )
                
                await viewModel.loadMoreTasksIfNeeded(for: viewModel.tasks.last!)
                
                XCTAssertEqual(viewModel.tasks.count, 40)
            }
        }
        """,
        bestPractices: [
            "Use appropriate page sizes (20-50 items typically work well)",
            "Implement pull-to-refresh for manual refresh capability", 
            "Show loading states during pagination",
            "Handle errors gracefully with retry options",
            "Cache paginated data for offline access",
            "Consider using placeholder content while loading"
        ],
        commonPitfalls: [
            Recipe.Issue(
                issue: "Duplicate API calls during fast scrolling",
                solution: "Use proper guards in loadMoreIfNeeded to prevent concurrent requests"
            ),
            Recipe.Issue(
                issue: "Memory issues with large lists",
                solution: "Implement data pruning to remove items that are far off-screen"
            )
        ],
        relatedRecipes: ["Offline Sync", "Design System"],
        category: .ui
    )
    
    static let validatedForm = Recipe(
        title: "Validated Form",
        description: "Create forms with comprehensive validation, error handling, and user experience optimization.",
        shortDescription: "Forms with validation and error handling",
        problem: "You need to create forms with robust validation, clear error messages, and smooth user experience.",
        solution: "Use @FormValidation macro for validation logic, @ObservableViewModel for form state, and SwiftUI form components for UI.",
        steps: [
            Step(
                title: "Define Form Model",
                description: "Create a form model with validation rules.",
                code: """
                @FormValidation(validateOnChange: true, showErrors: .onSubmit)
                struct UserRegistrationForm {
                    @Required(message: "First name is required")
                    @MinLength(2, message: "First name must be at least 2 characters")
                    var firstName: String = ""
                    
                    @Required(message: "Last name is required")  
                    @MinLength(2, message: "Last name must be at least 2 characters")
                    var lastName: String = ""
                    
                    @Required(message: "Email is required")
                    @Email(message: "Please enter a valid email address")
                    var email: String = ""
                    
                    @Required(message: "Password is required")
                    @MinLength(8, message: "Password must be at least 8 characters")
                    @PasswordStrength(message: "Password must contain uppercase, lowercase, number and symbol")
                    var password: String = ""
                    
                    @Required(message: "Please confirm your password")
                    @Matches("password", message: "Passwords do not match")
                    var confirmPassword: String = ""
                    
                    @Required(message: "Please accept the terms of service")
                    var acceptsTerms: Bool = false
                }
                """,
                explanation: "Form model with comprehensive validation rules and custom error messages."
            ),
            Step(
                title: "Create Form ViewModel", 
                description: "Build a ViewModel to manage form state and submission.",
                code: """
                @ObservableViewModel(dependencies: ["UserRepository"])
                class RegistrationViewModel: ObservableObject {
                    @Published var form = UserRegistrationForm()
                    @Published var isSubmitting = false
                    @Published var submissionError: AppError?
                    @Published var isSuccess = false
                    
                    private var repository: UserRepository { 
                        container.resolve(UserRepository.self)! 
                    }
                    
                    var canSubmit: Bool {
                        form.isValid && !isSubmitting
                    }
                    
                    @MainActor
                    func submit() async {
                        guard form.isValid else { return }
                        
                        isSubmitting = true
                        submissionError = nil
                        
                        do {
                            let request = CreateUserRequest(
                                firstName: form.firstName,
                                lastName: form.lastName, 
                                email: form.email,
                                password: form.password
                            )
                            
                            _ = try await repository.createUser(request)
                            isSuccess = true
                            
                            AnalyticsManager.shared?.track(
                                event: "user_registered",
                                properties: ["method": "email"]
                            )
                        } catch {
                            submissionError = AppError.from(error)
                        }
                        
                        isSubmitting = false
                    }
                }
                """,
                explanation: "ViewModel handles form submission with loading states and error handling."
            ),
            Step(
                title: "Build Form UI",
                description: "Create the SwiftUI form interface with validation feedback.",
                code: """
                @ViewModelBound(RegistrationViewModel.self)
                struct RegistrationView: View {
                    @Environment(\\.dismiss) var dismiss
                    
                    var body: some View {
                        NavigationView {
                            Form {
                                Section("Personal Information") {
                                    ValidatedTextField(
                                        "First Name",
                                        text: $viewModel.form.firstName,
                                        validation: viewModel.form.firstNameValidation
                                    )
                                    
                                    ValidatedTextField(
                                        "Last Name", 
                                        text: $viewModel.form.lastName,
                                        validation: viewModel.form.lastNameValidation
                                    )
                                }
                                
                                Section("Account") {
                                    ValidatedTextField(
                                        "Email",
                                        text: $viewModel.form.email,
                                        validation: viewModel.form.emailValidation
                                    )
                                    .keyboardType(.emailAddress)
                                    .textContentType(.emailAddress)
                                    .autocapitalization(.none)
                                    
                                    ValidatedSecureField(
                                        "Password",
                                        text: $viewModel.form.password,
                                        validation: viewModel.form.passwordValidation
                                    )
                                    .textContentType(.newPassword)
                                    
                                    ValidatedSecureField(
                                        "Confirm Password",
                                        text: $viewModel.form.confirmPassword, 
                                        validation: viewModel.form.confirmPasswordValidation
                                    )
                                    .textContentType(.newPassword)
                                }
                                
                                Section {
                                    Toggle("I accept the Terms of Service", 
                                           isOn: $viewModel.form.acceptsTerms)
                                    
                                    if !viewModel.form.acceptsTermsValidation.isValid {
                                        Text(viewModel.form.acceptsTermsValidation.errorMessage)
                                            .foregroundColor(.red)
                                            .font(.caption)
                                    }
                                }
                            }
                            .navigationTitle("Create Account")
                            .navigationBarTitleDisplayMode(.inline)
                            .toolbar {
                                ToolbarItem(placement: .navigationBarLeading) {
                                    Button("Cancel") { dismiss() }
                                }
                                
                                ToolbarItem(placement: .navigationBarTrailing) {
                                    Button("Sign Up") {
                                        Task { await viewModel.submit() }
                                    }
                                    .disabled(!viewModel.canSubmit)
                                }
                            }
                            .alert("Registration Successful", isPresented: $viewModel.isSuccess) {
                                Button("OK") { dismiss() }
                            }
                            .alert("Error", isPresented: Binding<Bool>(
                                get: { viewModel.submissionError != nil },
                                set: { _ in viewModel.submissionError = nil }
                            )) {
                                Button("Retry") { Task { await viewModel.submit() } }
                                Button("Cancel", role: .cancel) { }
                            } message: {
                                Text(viewModel.submissionError?.localizedDescription ?? "")
                            }
                        }
                    }
                }
                """,
                explanation: "Form UI with validation feedback, proper keyboard types, and error handling."
            ),
            Step(
                title: "Create Validated Input Components",
                description: "Build reusable components that show validation state.",
                code: """
                struct ValidatedTextField: View {
                    let title: String
                    @Binding var text: String
                    let validation: FieldValidation
                    
                    var body: some View {
                        VStack(alignment: .leading, spacing: 4) {
                            TextField(title, text: $text)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(borderColor, lineWidth: 1)
                                )
                            
                            if !validation.isValid && !validation.errorMessage.isEmpty {
                                Label(validation.errorMessage, systemImage: "exclamationmark.triangle")
                                    .foregroundColor(.red)
                                    .font(.caption)
                            }
                        }
                    }
                    
                    private var borderColor: Color {
                        if text.isEmpty {
                            return .clear
                        } else if validation.isValid {
                            return .green
                        } else {
                            return .red
                        }
                    }
                }
                
                struct ValidatedSecureField: View {
                    let title: String
                    @Binding var text: String
                    let validation: FieldValidation
                    @State private var showPassword = false
                    
                    var body: some View {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                if showPassword {
                                    TextField(title, text: $text)
                                } else {
                                    SecureField(title, text: $text)
                                }
                                
                                Button(action: { showPassword.toggle() }) {
                                    Image(systemName: showPassword ? "eye.slash" : "eye")
                                        .foregroundColor(.secondary)
                                }
                            }
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(borderColor, lineWidth: 1)
                            )
                            
                            if !validation.isValid && !validation.errorMessage.isEmpty {
                                Label(validation.errorMessage, systemImage: "exclamationmark.triangle")
                                    .foregroundColor(.red)
                                    .font(.caption)
                            }
                        }
                    }
                    
                    private var borderColor: Color {
                        if text.isEmpty {
                            return .clear
                        } else if validation.isValid {
                            return .green
                        } else {
                            return .red
                        }
                    }
                }
                """,
                explanation: "Reusable validated input components with visual feedback for validation state."
            )
        ],
        completeExample: """
        // Complete form implementation with custom validation
        @FormValidation
        struct ContactForm {
            @Required @MinLength(2) @MaxLength(50)
            var name: String = ""
            
            @Required @Email
            var email: String = ""
            
            @Required @PhoneNumber
            var phone: String = ""
            
            @Required @MinLength(10) @MaxLength(500)
            var message: String = ""
            
            @Custom(validator: BusinessHoursValidator())
            var contactTime: Date = Date()
        }
        
        struct BusinessHoursValidator: FormValidator {
            func validate(_ value: Date) -> ValidationResult {
                let hour = Calendar.current.component(.hour, from: value)
                if hour >= 9 && hour <= 17 {
                    return .valid
                } else {
                    return .invalid("Please select a time during business hours (9 AM - 5 PM)")
                }
            }
        }
        
        @ViewModelBound(ContactFormViewModel.self) 
        struct ContactFormView: View {
            var body: some View {
                Form {
                    ValidatedTextField("Name", text: $viewModel.form.name, validation: viewModel.form.nameValidation)
                    ValidatedTextField("Email", text: $viewModel.form.email, validation: viewModel.form.emailValidation)
                    ValidatedTextField("Phone", text: $viewModel.form.phone, validation: viewModel.form.phoneValidation)
                    ValidatedTextEditor("Message", text: $viewModel.form.message, validation: viewModel.form.messageValidation)
                    
                    DatePicker("Preferred Contact Time", selection: $viewModel.form.contactTime, displayedComponents: [.date, .hourAndMinute])
                    
                    Button("Send Message") {
                        Task { await viewModel.submit() }
                    }
                    .disabled(!viewModel.form.isValid || viewModel.isSubmitting)
                }
            }
        }
        """,
        testExample: """
        class UserRegistrationFormTests: XCTestCase {
            var form: UserRegistrationForm!
            
            override func setUp() {
                form = UserRegistrationForm()
            }
            
            func testValidForm() {
                form.firstName = "John"
                form.lastName = "Doe"
                form.email = "john.doe@example.com"
                form.password = "SecurePass123!"
                form.confirmPassword = "SecurePass123!"
                form.acceptsTerms = true
                
                XCTAssertTrue(form.isValid)
                XCTAssertTrue(form.validationErrors.isEmpty)
            }
            
            func testInvalidEmail() {
                form.email = "invalid-email"
                
                XCTAssertFalse(form.emailValidation.isValid)
                XCTAssertTrue(form.emailValidation.errorMessage.contains("valid email"))
            }
            
            func testPasswordMismatch() {
                form.password = "SecurePass123!"
                form.confirmPassword = "DifferentPass456!"
                
                XCTAssertFalse(form.confirmPasswordValidation.isValid)
                XCTAssertTrue(form.confirmPasswordValidation.errorMessage.contains("match"))
            }
        }
        """,
        bestPractices: [
            "Validate fields as users type for immediate feedback",
            "Use appropriate keyboard types and text content types",
            "Provide clear, actionable error messages",
            "Show validation state visually (colors, icons)",
            "Disable submit button until form is valid",
            "Handle network errors gracefully during submission",
            "Use proper accessibility labels for screen readers"
        ],
        commonPitfalls: [
            Recipe.Issue(
                issue: "Form validation not updating in real-time",
                solution: "Ensure validateOnChange is enabled and @Published properties are used correctly"
            ),
            Recipe.Issue(
                issue: "Password visibility toggle not working",
                solution: "Use @State for showPassword and conditional TextField/SecureField"
            )
        ],
        relatedRecipes: ["Authentication Gate", "Design System"],
        category: .ui
    )
    
    static let offlineSync = Recipe(
        title: "Offline Sync",
        description: "Implement robust offline data synchronization with conflict resolution.",
        shortDescription: "Offline-first data synchronization",
        problem: "Users need to access and modify data while offline, with automatic sync when connectivity returns.",
        solution: "Combine local storage with sync queues, conflict resolution, and background synchronization.",
        steps: [
            Step(
                title: "Setup Local Storage",
                description: "Create local storage layer for offline data.",
                code: """
                @KeyValueStore(backend: .sqlite, encrypted: false)
                struct LocalTaskStore {
                    var tasks: [Task] = []
                    var lastSyncTimestamp: Date = .distantPast
                    var pendingOperations: [SyncOperation] = []
                }
                
                struct SyncOperation: Codable, Identifiable {
                    let id = UUID()
                    let type: OperationType
                    let entityId: UUID
                    let entityData: Data?
                    let timestamp: Date
                    let retryCount: Int
                    
                    enum OperationType: String, Codable {
                        case create, update, delete
                    }
                }
                """,
                explanation: "Local storage manages offline data and tracks pending sync operations."
            ),
            Step(
                title: "Implement Sync Manager",
                description: "Create a manager to handle synchronization logic.",
                code: """
                @ObservableViewModel
                class SyncManager: ObservableObject {
                    @Published var syncStatus: SyncStatus = .idle
                    @Published var lastSyncDate: Date?
                    @Published var conflictCount: Int = 0
                    
                    private let localStore = LocalTaskStore()
                    private let repository: TaskRepository
                    private let networkMonitor = NetworkMonitor.shared
                    
                    enum SyncStatus {
                        case idle, syncing, error(AppError), completed
                    }
                    
                    init(repository: TaskRepository) {
                        self.repository = repository
                        setupNetworkMonitoring()
                    }
                    
                    private func setupNetworkMonitoring() {
                        networkMonitor.$isConnected
                            .filter { $0 }
                            .sink { [weak self] _ in
                                Task { await self?.syncWhenOnline() }
                            }
                            .store(in: &cancellables)
                    }
                    
                    @MainActor
                    func syncWhenOnline() async {
                        guard networkMonitor.isConnected else { return }
                        await performSync()
                    }
                }
                """,
                explanation: "SyncManager orchestrates offline synchronization and monitors network connectivity."
            ),
            Step(
                title: "Add Offline Repository Operations",
                description: "Extend repository to work offline with sync queuing.",
                code: """
                extension TaskRepository {
                    func saveOffline(_ task: Task) async throws {
                        // Save to local storage immediately
                        var localTasks = await localStore.tasks
                        
                        if let index = localTasks.firstIndex(where: { $0.id == task.id }) {
                            localTasks[index] = task
                            await localStore.setTasks(localTasks)
                            
                            // Queue update operation
                            await queueSyncOperation(.update, entityId: task.id, data: task)
                        } else {
                            localTasks.append(task)
                            await localStore.setTasks(localTasks)
                            
                            // Queue create operation  
                            await queueSyncOperation(.create, entityId: task.id, data: task)
                        }
                    }
                    
                    func deleteOffline(id: UUID) async throws {
                        // Remove from local storage
                        var localTasks = await localStore.tasks
                        localTasks.removeAll { $0.id == id }
                        await localStore.setTasks(localTasks)
                        
                        // Queue delete operation
                        await queueSyncOperation(.delete, entityId: id, data: nil)
                    }
                    
                    private func queueSyncOperation(_ type: SyncOperation.OperationType, entityId: UUID, data: Task?) async {
                        let operation = SyncOperation(
                            type: type,
                            entityId: entityId,
                            entityData: try? JSONEncoder().encode(data),
                            timestamp: Date(),
                            retryCount: 0
                        )
                        
                        var pending = await localStore.pendingOperations
                        pending.append(operation)
                        await localStore.setPendingOperations(pending)
                    }
                }
                """,
                explanation: "Repository queues operations for later sync when offline modifications are made."
            ),
            Step(
                title: "Implement Sync Logic",
                description: "Add the actual synchronization and conflict resolution.",
                code: """
                extension SyncManager {
                    @MainActor
                    private func performSync() async {
                        guard syncStatus != .syncing else { return }
                        
                        syncStatus = .syncing
                        
                        do {
                            // First, pull latest data from server
                            try await pullFromServer()
                            
                            // Then push local changes
                            try await pushToServer()
                            
                            // Update sync timestamp
                            await localStore.setLastSyncTimestamp(Date())
                            lastSyncDate = Date()
                            syncStatus = .completed
                            
                            AnalyticsManager.shared?.track(
                                event: "data_synced",
                                properties: ["operation_count": await localStore.pendingOperations.count]
                            )
                        } catch {
                            syncStatus = .error(AppError.from(error))
                        }
                    }
                    
                    private func pullFromServer() async throws {
                        let lastSync = await localStore.lastSyncTimestamp
                        let serverTasks = try await repository.fetchTasksSince(lastSync)
                        let localTasks = await localStore.tasks
                        
                        // Merge server changes with local data
                        let mergedTasks = try await mergeWithConflictResolution(
                            local: localTasks,
                            remote: serverTasks
                        )
                        
                        await localStore.setTasks(mergedTasks)
                    }
                    
                    private func mergeWithConflictResolution(
                        local: [Task], 
                        remote: [Task]
                    ) async throws -> [Task] {
                        var merged: [Task] = local
                        var conflicts: [ConflictResolution] = []
                        
                        for remoteTask in remote {
                            if let localIndex = merged.firstIndex(where: { $0.id == remoteTask.id }) {
                                let localTask = merged[localIndex]
                                
                                // Check if there's a conflict
                                if localTask.updatedAt != remoteTask.updatedAt && 
                                   localTask != remoteTask {
                                    
                                    // Apply conflict resolution strategy
                                    let resolved = try await resolveConflict(
                                        local: localTask, 
                                        remote: remoteTask
                                    )
                                    merged[localIndex] = resolved
                                    conflicts.append(ConflictResolution(
                                        entityId: remoteTask.id,
                                        strategy: .lastWriteWins
                                    ))
                                } else {
                                    merged[localIndex] = remoteTask
                                }
                            } else {
                                merged.append(remoteTask)
                            }
                        }
                        
                        conflictCount = conflicts.count
                        return merged
                    }
                }
                """,
                explanation: "Sync logic handles pulling server data and resolving conflicts using last-write-wins strategy."
            )
        ],
        completeExample: """
        // Complete offline sync implementation
        @Repository(cachingStrategy: .offline, syncStrategy: .automatic)
        class OfflineTaskRepository: DataRepository {
            typealias Model = Task
            
            private let syncManager = SyncManager()
            private let networkMonitor = NetworkMonitor.shared
            
            func fetch(id: UUID) async throws -> Task {
                if networkMonitor.isConnected {
                    return try await fetchFromServer(id: id)
                } else {
                    return try await fetchFromLocal(id: id)
                }
            }
            
            func save(_ model: Task) async throws {
                if networkMonitor.isConnected {
                    try await saveToServer(model)
                    try await saveToLocal(model)
                } else {
                    try await saveOffline(model)
                }
            }
        }
        
        @ViewModelBound(TaskListViewModel.self)
        struct OfflineTaskListView: View {
            @StateObject private var syncManager = SyncManager.shared
            
            var body: some View {
                List(viewModel.tasks) { task in
                    TaskRowView(task: task)
                        .swipeActions {
                            Button("Delete") {
                                Task {
                                    try await viewModel.deleteTask(task.id)
                                }
                            }
                            .tint(.red)
                        }
                }
                .navigationTitle("Tasks")
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        SyncStatusView(status: syncManager.syncStatus)
                    }
                    
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Sync") {
                            Task { await syncManager.forcSync() }
                        }
                        .disabled(syncManager.syncStatus == .syncing)
                    }
                }
                .overlay(alignment: .bottom) {
                    if syncManager.conflictCount > 0 {
                        ConflictsBannerView(count: syncManager.conflictCount)
                    }
                }
            }
        }
        """,
        testExample: """
        class SyncManagerTests: XCTestCase {
            var syncManager: SyncManager!
            var mockRepository: MockTaskRepository!
            var mockNetworkMonitor: MockNetworkMonitor!
            
            override func setUp() async throws {
                mockRepository = MockTaskRepository()
                mockNetworkMonitor = MockNetworkMonitor()
                syncManager = SyncManager(
                    repository: mockRepository,
                    networkMonitor: mockNetworkMonitor
                )
            }
            
            func testOfflineCreateAndSync() async throws {
                // Go offline
                mockNetworkMonitor.isConnected = false
                
                // Create task offline
                let task = Task(title: "Offline Task")
                try await mockRepository.saveOffline(task)
                
                // Verify queued for sync
                let pending = await syncManager.localStore.pendingOperations
                XCTAssertEqual(pending.count, 1)
                XCTAssertEqual(pending.first?.type, .create)
                
                // Come back online
                mockNetworkMonitor.isConnected = true
                await syncManager.syncWhenOnline()
                
                // Verify sync completed
                XCTAssertEqual(mockRepository.createCallCount, 1)
            }
            
            func testConflictResolution() async throws {
                let localTask = Task(title: "Local Version", updatedAt: Date())
                let remoteTask = Task(title: "Remote Version", updatedAt: Date().addingTimeInterval(60))
                
                let resolved = try await syncManager.resolveConflict(
                    local: localTask,
                    remote: remoteTask
                )
                
                // Should use last write wins (remote is newer)
                XCTAssertEqual(resolved.title, "Remote Version")
            }
        }
        """,
        bestPractices: [
            "Always save locally first, then sync to server",
            "Use timestamps for conflict resolution",
            "Implement exponential backoff for failed sync retries",
            "Provide clear sync status indicators to users",
            "Handle partial sync failures gracefully",
            "Allow manual sync triggers for user control",
            "Store sync operations in persistent storage"
        ],
        commonPitfalls: [
            Recipe.Issue(
                issue: "Data loss during conflicts",
                solution: "Implement proper conflict resolution strategies and store conflicted versions"
            ),
            Recipe.Issue(
                issue: "Infinite sync loops",
                solution: "Use proper timestamp comparison and avoid updating local data during sync"
            )
        ],
        relatedRecipes: ["Authentication Gate", "Background Tasks"],
        category: .data
    )
    
    static let widgetIntegration = Recipe(
        title: "Widget Integration",
        description: "Create widgets that share data with your main app using ViewModels and repositories.",
        shortDescription: "Widgets with shared app data",
        problem: "You want to create widgets that display data from your main app with proper data sharing and timeline management.",
        solution: "Use @WidgetDefinition macro with shared repositories and ViewModels through App Groups.",
        steps: [
            Step(
                title: "Setup App Groups",
                description: "Configure App Groups for data sharing between app and widget.",
                code: """
                // 1. In Xcode, add App Groups capability to both app and widget targets
                // 2. Use the same group identifier: group.com.yourapp.shared
                
                // 3. Configure shared UserDefaults
                extension UserDefaults {
                    static let shared = UserDefaults(suiteName: "group.com.yourapp.shared")!
                }
                
                // 4. Update KeyValueStore to use shared storage
                @KeyValueStore(suiteName: "group.com.yourapp.shared")
                struct SharedTaskStore {
                    var tasks: [Task] = []
                    var lastUpdate: Date = Date()
                }
                """,
                explanation: "App Groups enable data sharing between the main app and widget extension."
            ),
            Step(
                title: "Create Widget Definition",
                description: "Define your widget using the @WidgetDefinition macro.",
                code: """
                @WidgetDefinition(
                    kind: "com.yourapp.TaskWidget",
                    displayName: "My Tasks",
                    description: "View your upcoming tasks",
                    families: ["systemSmall", "systemMedium", "systemLarge"]
                )
                struct TaskWidget {
                    // Implementation generated automatically
                }
                
                struct TaskWidgetEntry: ArcheryTimelineEntry {
                    typealias ViewModel = TaskWidgetViewModel
                    
                    let date: Date
                    let configuration: TaskConfigurationIntent?
                    let viewModel: TaskWidgetViewModel
                    
                    init(date: Date, configuration: TaskConfigurationIntent?, viewModel: TaskWidgetViewModel) {
                        self.date = date
                        self.configuration = configuration
                        self.viewModel = viewModel
                    }
                }
                """,
                explanation: "Widget definition specifies supported sizes and timeline entry structure."
            ),
            Step(
                title: "Create Widget ViewModel",
                description: "Build a ViewModel specifically for widget data management.",
                code: """
                @ObservableViewModel
                class TaskWidgetViewModel: ObservableObject {
                    @Published var tasks: [Task] = []
                    @Published var isLoading = false
                    @Published var lastUpdate: Date = Date()
                    
                    private let sharedStore = SharedTaskStore()
                    private let container = EnvContainer.shared
                    
                    func loadWidgetData() async {
                        isLoading = true
                        
                        // Try to load from shared storage first (fast)
                        tasks = await sharedStore.tasks
                        lastUpdate = await sharedStore.lastUpdate
                        
                        // If data is stale, try to refresh from network
                        if Date().timeIntervalSince(lastUpdate) > 300 { // 5 minutes
                            await refreshFromNetwork()
                        }
                        
                        isLoading = false
                    }
                    
                    private func refreshFromNetwork() async {
                        guard let repository = container.resolve(TaskRepository.self) else { return }
                        
                        do {
                            let freshTasks = try await repository.fetchAll()
                            tasks = Array(freshTasks.prefix(10)) // Limit for widget
                            
                            // Update shared storage
                            await sharedStore.setTasks(tasks)
                            await sharedStore.setLastUpdate(Date())
                            
                        } catch {
                            // Fall back to cached data on error
                            print("Widget data refresh failed: \\(error)")
                        }
                    }
                }
                """,
                explanation: "Widget ViewModel handles data loading with caching and network fallback."
            ),
            Step(
                title: "Create Widget Views",
                description: "Design widget layouts for different sizes.",
                code: """
                struct TaskWidgetView: View {
                    let entry: TaskWidgetEntry
                    @Environment(\\.widgetFamily) var family
                    
                    var body: some View {
                        switch family {
                        case .systemSmall:
                            SmallTaskWidgetView(entry: entry)
                        case .systemMedium:
                            MediumTaskWidgetView(entry: entry)
                        case .systemLarge:
                            LargeTaskWidgetView(entry: entry)
                        default:
                            SmallTaskWidgetView(entry: entry)
                        }
                    }
                }
                
                struct SmallTaskWidgetView: View {
                    let entry: TaskWidgetEntry
                    
                    var body: some View {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Image(systemName: "checkmark.circle")
                                    .foregroundColor(.blue)
                                Text("Tasks")
                                    .font(.headline)
                                    .fontWeight(.semibold)
                                Spacer()
                            }
                            
                            if let firstTask = entry.viewModel.tasks.first {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(firstTask.title)
                                        .font(.subheadline)
                                        .lineLimit(2)
                                    
                                    Text(firstTask.dueDate, style: .relative)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            } else {
                                Text("No tasks")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                            
                            Spacer()
                        }
                        .padding()
                        .widgetBackground()
                        .widgetDeepLink(to: "tasks")
                    }
                }
                
                struct MediumTaskWidgetView: View {
                    let entry: TaskWidgetEntry
                    
                    var body: some View {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Image(systemName: "checkmark.circle")
                                    .foregroundColor(.blue)
                                Text("Upcoming Tasks")
                                    .font(.headline)
                                    .fontWeight(.semibold)
                                Spacer()
                                Text("\\(entry.viewModel.tasks.count)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            
                            VStack(spacing: 8) {
                                ForEach(Array(entry.viewModel.tasks.prefix(3))) { task in
                                    HStack {
                                        Circle()
                                            .fill(task.priority.color)
                                            .frame(width: 8, height: 8)
                                        
                                        Text(task.title)
                                            .font(.subheadline)
                                            .lineLimit(1)
                                        
                                        Spacer()
                                        
                                        Text(task.dueDate, style: .relative)
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }
                            }
                        }
                        .padding()
                        .widgetBackground()
                        .widgetDeepLink(to: "tasks")
                    }
                }
                """,
                explanation: "Different widget views optimized for small and medium sizes with deep linking."
            ),
            Step(
                title: "Implement Timeline Provider",
                description: "Create the timeline provider that manages widget updates.",
                code: """
                struct TaskWidgetTimelineProvider: ArcheryTimelineProvider {
                    typealias Entry = TaskWidgetEntry
                    
                    let container = EnvContainer.shared
                    
                    func createEntry(for configuration: TaskConfigurationIntent?, at date: Date) async -> TaskWidgetEntry {
                        let viewModel = TaskWidgetViewModel()
                        await viewModel.loadWidgetData()
                        
                        return TaskWidgetEntry(
                            date: date,
                            configuration: configuration,
                            viewModel: viewModel
                        )
                    }
                    
                    func createPlaceholderEntry(in context: Context) -> TaskWidgetEntry {
                        let placeholderViewModel = TaskWidgetViewModel()
                        placeholderViewModel.tasks = [
                            Task(title: "Sample Task", priority: .medium),
                            Task(title: "Another Task", priority: .high)
                        ]
                        
                        return TaskWidgetEntry(
                            date: Date(),
                            configuration: nil,
                            viewModel: placeholderViewModel
                        )
                    }
                    
                    func nextUpdateDate(after date: Date) -> Date {
                        // Update every 15 minutes during active hours
                        let calendar = Calendar.current
                        let hour = calendar.component(.hour, from: date)
                        
                        let interval: TimeInterval
                        if hour >= 6 && hour <= 22 {
                            interval = 15 * 60 // 15 minutes during day
                        } else {
                            interval = 60 * 60 // 1 hour at night
                        }
                        
                        return date.addingTimeInterval(interval)
                    }
                }
                """,
                explanation: "Timeline provider creates widget entries and manages update scheduling."
            )
        ],
        completeExample: """
        // Complete widget integration with main app
        
        // Widget Implementation
        @WidgetDefinition(
            kind: "com.myapp.ProgressWidget",
            displayName: "Project Progress",
            description: "Track your project completion",
            families: ["systemSmall", "systemMedium"]
        )
        struct ProgressWidget {
            // Auto-generated widget implementation
        }
        
        // Main app integration
        extension MainApp {
            func updateWidgets() {
                // Update shared data when app data changes
                Task {
                    let sharedStore = SharedTaskStore()
                    let tasks = try? await container.resolve(TaskRepository.self)?.fetchAll()
                    await sharedStore.setTasks(tasks ?? [])
                    
                    // Trigger widget timeline reload
                    WidgetTimelineManager.shared.reload(kind: "com.myapp.ProgressWidget")
                }
            }
        }
        
        // Automatic updates when data changes
        @ViewModelBound(TaskListViewModel.self)
        struct TaskListView: View {
            var body: some View {
                List(viewModel.tasks) { task in
                    TaskRowView(task: task)
                }
                .onChange(of: viewModel.tasks) { _ in
                    // Update widgets when tasks change
                    WidgetTimelineManager.shared.scheduleUpdate(
                        for: ["com.myapp.ProgressWidget"],
                        delay: 1.0
                    )
                }
            }
        }
        """,
        testExample: """
        class TaskWidgetTests: XCTestCase {
            var provider: TaskWidgetTimelineProvider!
            var mockRepository: MockTaskRepository!
            
            override func setUp() {
                mockRepository = MockTaskRepository()
                provider = TaskWidgetTimelineProvider()
                provider.container.register(TaskRepository.self) { mockRepository }
            }
            
            func testWidgetEntryCreation() async throws {
                let mockTasks = [
                    Task(title: "Test Task 1", priority: .high),
                    Task(title: "Test Task 2", priority: .medium)
                ]
                mockRepository.tasks = mockTasks
                
                let entry = await provider.createEntry(for: nil, at: Date())
                
                XCTAssertEqual(entry.viewModel.tasks.count, 2)
                XCTAssertEqual(entry.viewModel.tasks.first?.title, "Test Task 1")
            }
            
            func testPlaceholderEntry() {
                let entry = provider.createPlaceholderEntry(in: Context())
                
                XCTAssertFalse(entry.viewModel.tasks.isEmpty)
                XCTAssertEqual(entry.viewModel.tasks.count, 2)
            }
        }
        """,
        bestPractices: [
            "Use App Groups for data sharing between app and widget",
            "Implement smart update scheduling based on user patterns",
            "Provide meaningful placeholder content",
            "Handle network failures gracefully with cached data",
            "Keep widget data fresh but don't over-update",
            "Use deep linking to drive engagement back to main app",
            "Test widget behavior in different states (no data, loading, error)"
        ],
        commonPitfalls: [
            Recipe.Issue(
                issue: "Widget not updating with app data",
                solution: "Verify App Groups configuration and shared UserDefaults usage"
            ),
            Recipe.Issue(
                issue: "Widget performance issues",
                solution: "Limit data processing in timeline provider and use efficient data structures"
            )
        ],
        relatedRecipes: ["Background Tasks", "Design System"],
        category: .system
    )
    
    static let backgroundTasks = Recipe(
        title: "Background Tasks",
        description: "Implement background processing for data sync, cache cleanup, and maintenance tasks.",
        shortDescription: "Automated background processing",
        problem: "Your app needs to perform maintenance tasks, sync data, and update content while in the background.",
        solution: "Use @BackgroundTask macro with proper scheduling and execution management.",
        steps: [
            Step(
                title: "Define Background Tasks",
                description: "Create background task handlers for different operations.",
                code: """
                @BackgroundTask(
                    identifier: "com.yourapp.data-sync",
                    interval: "6hours",
                    requiresNetwork: true,
                    repositories: ["TaskRepository", "UserRepository"]
                )
                struct DataSyncTask {
                    // Implementation generated automatically
                }
                
                @BackgroundTask(
                    identifier: "com.yourapp.cache-cleanup",
                    interval: "daily",
                    requiresNetwork: false
                )
                struct CacheCleanupTask {
                    // Implementation generated automatically  
                }
                
                @BackgroundTask(
                    identifier: "com.yourapp.analytics-upload",
                    interval: "4hours",
                    requiresNetwork: true
                )
                struct AnalyticsUploadTask {
                    // Implementation generated automatically
                }
                """,
                explanation: "Different background tasks for sync, cleanup, and analytics with appropriate intervals."
            ),
            Step(
                title: "Configure App Capabilities",
                description: "Enable background modes in your app configuration.",
                code: """
                // In your Info.plist, add:
                <key>UIBackgroundModes</key>
                <array>
                    <string>background-app-refresh</string>
                    <string>background-processing</string>
                </array>
                
                // In your BGTaskSchedulerPermittedIdentifiers:
                <key>BGTaskSchedulerPermittedIdentifiers</key>
                <array>
                    <string>com.yourapp.data-sync</string>
                    <string>com.yourapp.cache-cleanup</string>
                    <string>com.yourapp.analytics-upload</string>
                </array>
                """,
                explanation: "App must declare background modes and permitted task identifiers."
            ),
            Step(
                title: "Setup Background Task Coordinator",
                description: "Configure the background task system in your app delegate.",
                code: """
                @main
                struct MyApp: App {
                    @StateObject private var container = EnvContainer()
                    
                    init() {
                        setupBackgroundTasks()
                    }
                    
                    var body: some Scene {
                        WindowGroup {
                            ContentView()
                                .environmentObject(container)
                                .onReceive(NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)) { _ in
                                    scheduleBackgroundTasks()
                                }
                        }
                    }
                    
                    private func setupBackgroundTasks() {
                        BackgroundTaskCoordinator.shared.configure()
                        
                        // Register custom task handlers
                        BackgroundTaskManager.shared.register(
                            taskId: "com.yourapp.data-sync",
                            handler: DataSyncTask.self
                        )
                        
                        BackgroundTaskManager.shared.register(
                            taskId: "com.yourapp.cache-cleanup", 
                            handler: CacheCleanupTask.self
                        )
                        
                        BackgroundTaskManager.shared.register(
                            taskId: "com.yourapp.analytics-upload",
                            handler: AnalyticsUploadTask.self
                        )
                    }
                    
                    private func scheduleBackgroundTasks() {
                        BackgroundTaskCoordinator.shared.scheduleInitialTasks()
                    }
                }
                """,
                explanation: "App setup configures background task coordination and scheduling."
            ),
            Step(
                title: "Implement Custom Task Logic",
                description: "Add custom logic for specific background tasks.",
                code: """
                extension DataSyncTask {
                    func performSync(with container: EnvContainer) async throws {
                        guard let taskRepo = container.resolve(TaskRepository.self),
                              let userRepo = container.resolve(UserRepository.self) else {
                            throw BackgroundTaskError.repositoriesUnavailable
                        }
                        
                        // Sync tasks
                        let localTasks = try await taskRepo.fetchLocalTasks()
                        let remoteTasks = try await taskRepo.fetchRemoteTasks()
                        try await taskRepo.mergeAndSync(local: localTasks, remote: remoteTasks)
                        
                        // Sync user profile
                        try await userRepo.syncUserProfile()
                        
                        // Update widget data
                        let sharedStore = SharedTaskStore()
                        await sharedStore.setTasks(try await taskRepo.fetchAll())
                        await sharedStore.setLastUpdate(Date())
                        
                        // Trigger widget updates
                        WidgetTimelineManager.shared.reloadAll()
                        
                        AnalyticsManager.shared?.track(
                            event: "background_sync_completed",
                            properties: ["task_count": localTasks.count]
                        )
                    }
                }
                
                extension CacheCleanupTask {
                    func performCleanup() async throws {
                        let cacheManager = CacheManager.shared
                        
                        // Clean old image cache (older than 7 days)
                        await cacheManager.cleanImageCache(olderThan: 7 * 24 * 3600)
                        
                        // Clean temporary files
                        await cacheManager.cleanTemporaryFiles()
                        
                        // Compact database
                        try await DatabaseManager.shared.compactDatabase()
                        
                        // Clear expired authentication tokens
                        let authStore = AuthTokenStore()
                        if await authStore.expiresAt < Date() {
                            await authStore.setToken("")
                            await authStore.setRefreshToken("")
                        }
                        
                        let freedSpace = await cacheManager.lastCleanupFreedSpace
                        AnalyticsManager.shared?.track(
                            event: "cache_cleanup_completed",
                            properties: ["freed_bytes": freedSpace]
                        )
                    }
                }
                """,
                explanation: "Custom task implementations handle specific business logic for sync and cleanup."
            ),
            Step(
                title: "Add Task Monitoring",
                description: "Implement monitoring and debugging for background tasks.",
                code: """
                @ObservableViewModel
                class BackgroundTaskMonitor: ObservableObject {
                    @Published var taskStatus: [String: BackgroundTaskStatus] = [:]
                    @Published var lastExecutions: [String: Date] = [:]
                    @Published var executionResults: [String: TaskExecutionResult] = [:]
                    
                    enum TaskExecutionResult {
                        case success(Date)
                        case failure(Date, Error)
                        case expired(Date)
                    }
                    
                    func monitorTask(_ taskId: String) {
                        // Monitor task execution and update status
                        NotificationCenter.default.addObserver(
                            forName: .backgroundTaskCompleted,
                            object: nil,
                            queue: .main
                        ) { [weak self] notification in
                            guard let userInfo = notification.userInfo,
                                  let id = userInfo["taskId"] as? String,
                                  id == taskId else { return }
                            
                            if let error = userInfo["error"] as? Error {
                                self?.executionResults[taskId] = .failure(Date(), error)
                            } else {
                                self?.executionResults[taskId] = .success(Date())
                            }
                            
                            self?.lastExecutions[taskId] = Date()
                        }
                    }
                    
                    func getTaskStatusSummary() async -> String {
                        let statuses = await BackgroundTaskCoordinator.shared.getTaskStatus()
                        
                        var summary = "Background Tasks:\\n"
                        for status in statuses {
                            let lastRun = lastExecutions[status.identifier] ?? Date.distantPast
                            let result = executionResults[status.identifier]
                            
                            summary += "• \\(status.identifier)\\n"
                            summary += "  Scheduled: \\(status.isScheduled ? "✅" : "❌")\\n"
                            summary += "  Last run: \\(lastRun.formatted(.relative(presentation: .numeric)))\\n"
                            
                            switch result {
                            case .success:
                                summary += "  Status: ✅ Success\\n"
                            case .failure(_, let error):
                                summary += "  Status: ❌ Error: \\(error.localizedDescription)\\n"
                            case .expired:
                                summary += "  Status: ⏰ Expired\\n"
                            case nil:
                                summary += "  Status: ⏳ Not run yet\\n"
                            }
                            summary += "\\n"
                        }
                        
                        return summary
                    }
                }
                """,
                explanation: "Background task monitor provides visibility into task execution and debugging information."
            )
        ],
        completeExample: """
        // Complete background task implementation with monitoring
        
        class AppDelegate: UIResponder, UIApplicationDelegate {
            func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
                
                // Configure background tasks
                BackgroundTaskCoordinator.shared.configure()
                
                return true
            }
            
            func applicationDidEnterBackground(_ application: UIApplication) {
                // Schedule background tasks when app enters background
                BackgroundTaskCoordinator.shared.scheduleInitialTasks()
            }
        }
        
        // Debug view for monitoring background tasks
        struct BackgroundTaskDebugView: View {
            @StateObject private var monitor = BackgroundTaskMonitor()
            @State private var statusSummary = ""
            
            var body: some View {
                NavigationView {
                    VStack(alignment: .leading, spacing: 20) {
                        Button("Refresh Status") {
                            Task {
                                statusSummary = await monitor.getTaskStatusSummary()
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        
                        ScrollView {
                            Text(statusSummary)
                                .font(.monospaced(.caption)())
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        
                        Button("Force Sync Now") {
                            Task {
                                try await BackgroundTaskManager.shared.scheduleAppRefresh(
                                    identifier: "com.yourapp.data-sync",
                                    earliestBeginDate: Date()
                                )
                            }
                        }
                        
                        Spacer()
                    }
                    .padding()
                    .navigationTitle("Background Tasks")
                }
                .onAppear {
                    monitor.monitorTask("com.yourapp.data-sync")
                    monitor.monitorTask("com.yourapp.cache-cleanup")
                }
            }
        }
        """,
        testExample: """
        class BackgroundTaskTests: XCTestCase {
            var dataSyncTask: DataSyncTask!
            var mockContainer: EnvContainer!
            var mockTaskRepository: MockTaskRepository!
            
            override func setUp() {
                mockContainer = EnvContainer()
                mockTaskRepository = MockTaskRepository()
                mockContainer.register(TaskRepository.self) { mockTaskRepository }
                dataSyncTask = DataSyncTask()
            }
            
            func testDataSyncExecution() async throws {
                mockTaskRepository.localTasks = [Task(title: "Local Task")]
                mockTaskRepository.remoteTasks = [Task(title: "Remote Task")]
                
                try await dataSyncTask.execute(with: mockContainer)
                
                XCTAssertTrue(mockTaskRepository.syncCalled)
                XCTAssertEqual(mockTaskRepository.mergeCallCount, 1)
            }
            
            func testTaskScheduling() async throws {
                let manager = BackgroundTaskManager.shared
                
                try manager.scheduleAppRefresh(
                    identifier: "com.test.task",
                    earliestBeginDate: Date().addingTimeInterval(60)
                )
                
                let status = await BackgroundTaskCoordinator.shared.getTaskStatus()
                XCTAssertTrue(status.contains { $0.identifier == "com.test.task" })
            }
        }
        """,
        bestPractices: [
            "Register task identifiers in Info.plist before using them",
            "Handle task expiration gracefully with cleanup code",
            "Use appropriate task types (app refresh vs processing)",
            "Schedule tasks conservatively to avoid system throttling",
            "Implement proper error handling and retry logic",
            "Monitor task execution and success rates in production",
            "Provide manual trigger options for debugging"
        ],
        commonPitfalls: [
            Recipe.Issue(
                issue: "Background tasks not executing",
                solution: "Verify background modes are enabled and task identifiers are registered in Info.plist"
            ),
            Recipe.Issue(
                issue: "Tasks being killed by the system",
                solution: "Optimize task execution time and handle expiration callbacks properly"
            )
        ],
        relatedRecipes: ["Offline Sync", "Widget Integration"],
        category: .system
    )
    
    static let designSystem = Recipe(
        title: "Design System",
        description: "Implement a comprehensive design system with tokens, components, and theming.",
        shortDescription: "Scalable design system implementation",
        problem: "You need a consistent design system that scales across your app with proper theming and component library.",
        solution: "Use @DesignTokens macro with systematic component architecture and theme management.",
        steps: [
            Step(
                title: "Setup Design Tokens",
                description: "Define your design system tokens using the macro.",
                code: """
                @DesignTokens(source: "design-tokens.json")
                struct AppDesignSystem {
                    // Tokens are generated from design-tokens.json
                }
                
                // design-tokens.json structure:
                {
                  "color": {
                    "primary": {
                      "50": "#f0f9ff",
                      "500": "#3b82f6", 
                      "900": "#1e3a8a"
                    },
                    "semantic": {
                      "success": "#10b981",
                      "warning": "#f59e0b",
                      "error": "#ef4444"
                    }
                  },
                  "typography": {
                    "scale": {
                      "xs": 12,
                      "sm": 14,
                      "base": 16,
                      "lg": 18,
                      "xl": 20
                    }
                  },
                  "spacing": {
                    "xs": 4,
                    "sm": 8,
                    "md": 16,
                    "lg": 24,
                    "xl": 32
                  }
                }
                """,
                explanation: "Design tokens provide the foundation for consistent styling across the app."
            ),
            Step(
                title: "Create Theme System",
                description: "Implement dynamic theming with light/dark mode support.",
                code: """
                enum AppTheme: String, CaseIterable, Codable {
                    case light, dark, system
                    
                    var colorScheme: ColorScheme? {
                        switch self {
                        case .light: return .light
                        case .dark: return .dark
                        case .system: return nil
                        }
                    }
                }
                
                @ObservableViewModel
                class ThemeManager: ObservableObject {
                    @Published var currentTheme: AppTheme = .system
                    
                    private let themeStore = ThemeStore()
                    
                    init() {
                        loadTheme()
                    }
                    
                    func setTheme(_ theme: AppTheme) {
                        currentTheme = theme
                        Task {
                            await themeStore.setTheme(theme)
                        }
                    }
                    
                    private func loadTheme() {
                        Task {
                            currentTheme = await themeStore.theme
                        }
                    }
                }
                
                @KeyValueStore
                struct ThemeStore {
                    var theme: AppTheme = .system
                }
                """,
                explanation: "Theme manager handles theme persistence and switching with reactive updates."
            ),
            Step(
                title: "Build Component Library",
                description: "Create reusable components using design tokens.",
                code: """
                // MARK: - Button Components
                
                struct PrimaryButton: View {
                    let title: String
                    let action: () -> Void
                    let isLoading: Bool
                    let isDisabled: Bool
                    
                    init(
                        _ title: String,
                        isLoading: Bool = false,
                        isDisabled: Bool = false,
                        action: @escaping () -> Void
                    ) {
                        self.title = title
                        self.isLoading = isLoading
                        self.isDisabled = isDisabled
                        self.action = action
                    }
                    
                    var body: some View {
                        Button(action: action) {
                            HStack(spacing: AppDesignSystem.Spacing.sm) {
                                if isLoading {
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                        .scaleEffect(0.8)
                                }
                                
                                Text(title)
                                    .font(AppDesignSystem.Typography.button)
                                    .fontWeight(.semibold)
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 48)
                            .foregroundColor(.white)
                            .background(
                                RoundedRectangle(cornerRadius: AppDesignSystem.BorderRadius.md)
                                    .fill(isDisabled ? AppDesignSystem.Colors.gray300 : AppDesignSystem.Colors.primary500)
                            )
                        }
                        .disabled(isDisabled || isLoading)
                        .buttonStyle(ScaleButtonStyle())
                    }
                }
                
                struct SecondaryButton: View {
                    let title: String
                    let action: () -> Void
                    let isDisabled: Bool
                    
                    init(_ title: String, isDisabled: Bool = false, action: @escaping () -> Void) {
                        self.title = title
                        self.isDisabled = isDisabled
                        self.action = action
                    }
                    
                    var body: some View {
                        Button(action: action) {
                            Text(title)
                                .font(AppDesignSystem.Typography.button)
                                .fontWeight(.medium)
                                .frame(maxWidth: .infinity)
                                .frame(height: 48)
                                .foregroundColor(AppDesignSystem.Colors.primary500)
                                .background(
                                    RoundedRectangle(cornerRadius: AppDesignSystem.BorderRadius.md)
                                        .stroke(AppDesignSystem.Colors.primary500, lineWidth: 1)
                                )
                        }
                        .disabled(isDisabled)
                        .buttonStyle(ScaleButtonStyle())
                    }
                }
                
                struct ScaleButtonStyle: ButtonStyle {
                    func makeBody(configuration: Configuration) -> some View {
                        configuration.label
                            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
                            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
                    }
                }
                """,
                explanation: "Component library provides consistent button styles using design tokens."
            ),
            Step(
                title: "Create Card Components",
                description: "Build card-based components with consistent styling.",
                code: """
                struct CardView<Content: View>: View {
                    let content: Content
                    let padding: CGFloat
                    let shadow: CardShadow
                    
                    enum CardShadow {
                        case none, small, medium, large
                        
                        var elevation: CGFloat {
                            switch self {
                            case .none: return 0
                            case .small: return 2
                            case .medium: return 4
                            case .large: return 8
                            }
                        }
                        
                        var radius: CGFloat {
                            switch self {
                            case .none: return 0
                            case .small: return 4
                            case .medium: return 8
                            case .large: return 16
                            }
                        }
                    }
                    
                    init(
                        padding: CGFloat = AppDesignSystem.Spacing.md,
                        shadow: CardShadow = .medium,
                        @ViewBuilder content: () -> Content
                    ) {
                        self.content = content()
                        self.padding = padding
                        self.shadow = shadow
                    }
                    
                    var body: some View {
                        content
                            .padding(padding)
                            .background(
                                RoundedRectangle(cornerRadius: AppDesignSystem.BorderRadius.lg)
                                    .fill(Color(.systemBackground))
                                    .shadow(
                                        color: .black.opacity(0.1),
                                        radius: shadow.radius,
                                        y: shadow.elevation
                                    )
                            )
                    }
                }
                
                struct InfoCard: View {
                    let title: String
                    let subtitle: String?
                    let icon: String
                    let action: (() -> Void)?
                    
                    init(
                        title: String,
                        subtitle: String? = nil,
                        icon: String,
                        action: (() -> Void)? = nil
                    ) {
                        self.title = title
                        self.subtitle = subtitle
                        self.icon = icon
                        self.action = action
                    }
                    
                    var body: some View {
                        CardView {
                            HStack(spacing: AppDesignSystem.Spacing.md) {
                                Image(systemName: icon)
                                    .font(.title2)
                                    .foregroundColor(AppDesignSystem.Colors.primary500)
                                    .frame(width: 32, height: 32)
                                
                                VStack(alignment: .leading, spacing: AppDesignSystem.Spacing.xs) {
                                    Text(title)
                                        .font(AppDesignSystem.Typography.headlineSmall)
                                        .fontWeight(.semibold)
                                    
                                    if let subtitle = subtitle {
                                        Text(subtitle)
                                            .font(AppDesignSystem.Typography.bodySmall)
                                            .foregroundColor(AppDesignSystem.Colors.gray600)
                                    }
                                }
                                
                                Spacer()
                                
                                if action != nil {
                                    Image(systemName: "chevron.right")
                                        .font(.caption)
                                        .foregroundColor(AppDesignSystem.Colors.gray400)
                                }
                            }
                        }
                        .onTapGesture {
                            action?()
                        }
                    }
                }
                """,
                explanation: "Card components provide consistent layouts and interactions across the app."
            ),
            Step(
                title: "Implement Typography System",
                description: "Create typography modifiers and text styles.",
                code: """
                extension View {
                    func textStyle(_ style: AppDesignSystem.Typography.Style) -> some View {
                        self
                            .font(style.font)
                            .lineSpacing(style.lineSpacing)
                            .tracking(style.letterSpacing)
                    }
                }
                
                extension AppDesignSystem.Typography {
                    enum Style {
                        case displayLarge, displayMedium, displaySmall
                        case headlineLarge, headlineMedium, headlineSmall
                        case titleLarge, titleMedium, titleSmall
                        case bodyLarge, bodyMedium, bodySmall
                        case labelLarge, labelMedium, labelSmall
                        
                        var font: Font {
                            switch self {
                            case .displayLarge: return .system(size: 57, weight: .regular)
                            case .displayMedium: return .system(size: 45, weight: .regular)
                            case .displaySmall: return .system(size: 36, weight: .regular)
                            case .headlineLarge: return .system(size: 32, weight: .regular)
                            case .headlineMedium: return .system(size: 28, weight: .regular)
                            case .headlineSmall: return .system(size: 24, weight: .regular)
                            case .titleLarge: return .system(size: 22, weight: .medium)
                            case .titleMedium: return .system(size: 16, weight: .medium)
                            case .titleSmall: return .system(size: 14, weight: .medium)
                            case .bodyLarge: return .system(size: 16, weight: .regular)
                            case .bodyMedium: return .system(size: 14, weight: .regular)
                            case .bodySmall: return .system(size: 12, weight: .regular)
                            case .labelLarge: return .system(size: 14, weight: .medium)
                            case .labelMedium: return .system(size: 12, weight: .medium)
                            case .labelSmall: return .system(size: 11, weight: .medium)
                            }
                        }
                        
                        var lineSpacing: CGFloat {
                            switch self {
                            case .displayLarge, .displayMedium, .displaySmall:
                                return 4
                            case .headlineLarge, .headlineMedium, .headlineSmall:
                                return 2
                            default:
                                return 0
                            }
                        }
                        
                        var letterSpacing: CGFloat {
                            switch self {
                            case .labelLarge, .labelMedium, .labelSmall:
                                return 0.5
                            default:
                                return 0
                            }
                        }
                    }
                }
                """,
                explanation: "Typography system ensures consistent text styling throughout the application."
            )
        ],
        completeExample: """
        // Complete design system usage example
        
        struct ProfileView: View {
            @StateObject private var themeManager = ThemeManager()
            
            var body: some View {
                ScrollView {
                    VStack(spacing: AppDesignSystem.Spacing.lg) {
                        // Profile header
                        CardView(shadow: .small) {
                            HStack(spacing: AppDesignSystem.Spacing.md) {
                                AsyncImage(url: user.avatarURL) { image in
                                    image
                                        .resizable()
                                        .aspectRatio(contentMode: .fill)
                                } placeholder: {
                                    Circle()
                                        .fill(AppDesignSystem.Colors.gray200)
                                }
                                .frame(width: 64, height: 64)
                                .clipShape(Circle())
                                
                                VStack(alignment: .leading, spacing: AppDesignSystem.Spacing.xs) {
                                    Text(user.name)
                                        .textStyle(.headlineSmall)
                                    
                                    Text(user.email)
                                        .textStyle(.bodyMedium)
                                        .foregroundColor(AppDesignSystem.Colors.gray600)
                                }
                                
                                Spacer()
                            }
                        }
                        
                        // Settings section
                        VStack(spacing: AppDesignSystem.Spacing.sm) {
                            InfoCard(
                                title: "Theme",
                                subtitle: themeManager.currentTheme.rawValue.capitalized,
                                icon: "paintbrush"
                            ) {
                                // Show theme picker
                            }
                            
                            InfoCard(
                                title: "Notifications",
                                subtitle: "Manage your notification preferences",
                                icon: "bell"
                            ) {
                                // Navigate to notifications
                            }
                        }
                        
                        // Action buttons
                        VStack(spacing: AppDesignSystem.Spacing.sm) {
                            PrimaryButton("Edit Profile") {
                                // Edit profile action
                            }
                            
                            SecondaryButton("Sign Out") {
                                // Sign out action
                            }
                        }
                    }
                    .padding(AppDesignSystem.Spacing.md)
                }
                .background(AppDesignSystem.Colors.background)
                .preferredColorScheme(themeManager.currentTheme.colorScheme)
            }
        }
        """,
        testExample: """
        class DesignSystemTests: XCTestCase {
            func testThemeManager() {
                let themeManager = ThemeManager()
                
                XCTAssertEqual(themeManager.currentTheme, .system)
                
                themeManager.setTheme(.dark)
                XCTAssertEqual(themeManager.currentTheme, .dark)
            }
            
            func testTypographyStyles() {
                let headlineFont = AppDesignSystem.Typography.Style.headlineLarge.font
                let bodyFont = AppDesignSystem.Typography.Style.bodyMedium.font
                
                XCTAssertNotEqual(headlineFont, bodyFont)
            }
            
            func testColorTokens() {
                XCTAssertNotNil(AppDesignSystem.Colors.primary500)
                XCTAssertNotNil(AppDesignSystem.Colors.success)
            }
        }
        """,
        bestPractices: [
            "Use design tokens consistently across all components",
            "Implement proper dark mode support for all colors",
            "Create reusable component library with clear APIs",
            "Document component usage and examples",
            "Test design system components across different screen sizes",
            "Use semantic color names instead of specific values",
            "Implement proper accessibility support in all components"
        ],
        commonPitfalls: [
            Recipe.Issue(
                issue: "Inconsistent spacing across views",
                solution: "Always use design token spacing values instead of hardcoded numbers"
            ),
            Recipe.Issue(
                issue: "Poor dark mode support",
                solution: "Define both light and dark variants for all colors in design tokens"
            )
        ],
        relatedRecipes: ["Validated Form", "Widget Integration"],
        category: .design
    )
    
    static let testing = Recipe(
        title: "Testing",
        description: "Implement comprehensive testing strategy with unit tests, integration tests, and UI tests.",
        shortDescription: "Complete testing implementation",
        problem: "You need a robust testing strategy that covers ViewModels, repositories, UI components, and integration scenarios.",
        solution: "Use Archery's testing utilities with proper mocking, dependency injection, and test helpers.",
        steps: [
            Step(
                title: "Setup Test Infrastructure",
                description: "Configure test targets and dependencies.",
                code: """
                // In Package.swift, add test dependencies
                .testTarget(
                    name: "ArcheryTests",
                    dependencies: ["Archery"]
                ),
                
                // Create base test class
                import XCTest
                @testable import Archery
                
                @MainActor
                class ArcheryTestCase: XCTestCase {
                    var container: EnvContainer!
                    
                    override func setUp() async throws {
                        container = EnvContainer()
                        await setupMockRepositories()
                    }
                    
                    override func tearDown() async throws {
                        container = nil
                    }
                    
                    private func setupMockRepositories() async {
                        container.register(TaskRepository.self) { MockTaskRepository() }
                        container.register(UserRepository.self) { MockUserRepository() }
                        container.register(AnalyticsManager.self) { MockAnalyticsManager() }
                    }
                    
                    func createViewModel<T: ObservableObject>(_ type: T.Type) -> T {
                        let viewModel = type.init()
                        if let archeryVM = viewModel as? any ArcheryViewModel {
                            archeryVM.setContainer(container)
                        }
                        return viewModel
                    }
                }
                """,
                explanation: "Base test class provides common setup for dependency injection and mock repositories."
            ),
            Step(
                title: "Create Mock Repositories",
                description: "Build comprehensive mocks for all repository types.",
                code: """
                class MockTaskRepository: DataRepository {
                    typealias Model = Task
                    
                    var tasks: [Task] = []
                    var shouldThrowError = false
                    var fetchCallCount = 0
                    var saveCallCount = 0
                    var deleteCallCount = 0
                    
                    func fetch(id: UUID) async throws -> Task {
                        fetchCallCount += 1
                        
                        if shouldThrowError {
                            throw RepositoryError.notFound
                        }
                        
                        guard let task = tasks.first(where: { $0.id == id }) else {
                            throw RepositoryError.notFound
                        }
                        
                        return task
                    }
                    
                    func fetchAll() async throws -> [Task] {
                        fetchCallCount += 1
                        
                        if shouldThrowError {
                            throw RepositoryError.networkError
                        }
                        
                        return tasks
                    }
                    
                    func save(_ model: Task) async throws {
                        saveCallCount += 1
                        
                        if shouldThrowError {
                            throw RepositoryError.saveFailed
                        }
                        
                        if let index = tasks.firstIndex(where: { $0.id == model.id }) {
                            tasks[index] = model
                        } else {
                            tasks.append(model)
                        }
                    }
                    
                    func delete(id: UUID) async throws {
                        deleteCallCount += 1
                        
                        if shouldThrowError {
                            throw RepositoryError.deleteFailed
                        }
                        
                        tasks.removeAll { $0.id == id }
                    }
                    
                    // Test helpers
                    func reset() {
                        tasks = []
                        shouldThrowError = false
                        fetchCallCount = 0
                        saveCallCount = 0
                        deleteCallCount = 0
                    }
                    
                    func setupTestData(_ testTasks: [Task]) {
                        tasks = testTasks
                    }
                }
                
                class MockAnalyticsManager: AnalyticsManager {
                    var trackedEvents: [(event: String, properties: [String: Any])] = []
                    
                    override func track(event: String, properties: [String: Any] = [:]) {
                        trackedEvents.append((event, properties))
                    }
                    
                    func reset() {
                        trackedEvents = []
                    }
                    
                    func didTrack(event: String) -> Bool {
                        trackedEvents.contains { $0.event == event }
                    }
                }
                """,
                explanation: "Mock repositories provide controllable test doubles with call tracking and error simulation."
            ),
            Step(
                title: "Test ViewModels",
                description: "Write comprehensive tests for ViewModel behavior.",
                code: """
                @MainActor
                class TaskListViewModelTests: ArcheryTestCase {
                    var viewModel: TaskListViewModel!
                    var mockRepository: MockTaskRepository!
                    var mockAnalytics: MockAnalyticsManager!
                    
                    override func setUp() async throws {
                        try await super.setUp()
                        
                        mockRepository = container.resolve(TaskRepository.self) as? MockTaskRepository
                        mockAnalytics = container.resolve(AnalyticsManager.self) as? MockAnalyticsManager
                        viewModel = createViewModel(TaskListViewModel.self)
                    }
                    
                    func testLoadTasksSuccess() async throws {
                        // Given
                        let testTasks = [
                            Task(title: "Test Task 1", priority: .high),
                            Task(title: "Test Task 2", priority: .medium)
                        ]
                        mockRepository.setupTestData(testTasks)
                        
                        // When
                        await viewModel.loadTasks()
                        
                        // Then
                        XCTAssertEqual(viewModel.tasks.count, 2)
                        XCTAssertEqual(viewModel.tasks[0].title, "Test Task 1")
                        XCTAssertFalse(viewModel.isLoading)
                        XCTAssertNil(viewModel.errorMessage)
                        XCTAssertEqual(mockRepository.fetchCallCount, 1)
                    }
                    
                    func testLoadTasksError() async throws {
                        // Given
                        mockRepository.shouldThrowError = true
                        
                        // When
                        await viewModel.loadTasks()
                        
                        // Then
                        XCTAssertTrue(viewModel.tasks.isEmpty)
                        XCTAssertFalse(viewModel.isLoading)
                        XCTAssertNotNil(viewModel.errorMessage)
                    }
                    
                    func testAddTask() async throws {
                        // Given
                        let newTask = Task(title: "New Task", priority: .medium)
                        
                        // When
                        await viewModel.addTask(newTask)
                        
                        // Then
                        XCTAssertEqual(mockRepository.saveCallCount, 1)
                        XCTAssertTrue(mockAnalytics.didTrack(event: "task_created"))
                        
                        // Verify analytics properties
                        let trackedEvent = mockAnalytics.trackedEvents.first { $0.event == "task_created" }
                        XCTAssertEqual(trackedEvent?.properties["priority"] as? String, "medium")
                    }
                    
                    func testDeleteTask() async throws {
                        // Given
                        let task = Task(title: "Task to Delete", priority: .low)
                        mockRepository.setupTestData([task])
                        await viewModel.loadTasks()
                        
                        // When
                        await viewModel.deleteTask(task.id)
                        
                        // Then
                        XCTAssertEqual(mockRepository.deleteCallCount, 1)
                        XCTAssertTrue(mockAnalytics.didTrack(event: "task_deleted"))
                    }
                    
                    func testToggleTask() async throws {
                        // Given
                        var task = Task(title: "Task to Toggle", priority: .medium)
                        task.isCompleted = false
                        mockRepository.setupTestData([task])
                        await viewModel.loadTasks()
                        
                        // When
                        await viewModel.toggleTask(task)
                        
                        // Then
                        XCTAssertEqual(mockRepository.saveCallCount, 1)
                        XCTAssertTrue(mockAnalytics.didTrack(event: "task_toggled"))
                        
                        let toggleEvent = mockAnalytics.trackedEvents.first { $0.event == "task_toggled" }
                        XCTAssertEqual(toggleEvent?.properties["completed"] as? Bool, true)
                    }
                }
                """,
                explanation: "ViewModel tests cover success paths, error handling, and side effects like analytics tracking."
            ),
            Step(
                title: "Test Repository Implementation", 
                description: "Test repository layer with network mocking.",
                code: """
                class TaskRepositoryTests: XCTestCase {
                    var repository: TaskRepository!
                    var mockNetworkManager: MockNetworkManager!
                    var mockCache: MockCache!
                    
                    override func setUp() {
                        mockNetworkManager = MockNetworkManager()
                        mockCache = MockCache()
                        repository = TaskRepository(
                            networkManager: mockNetworkManager,
                            cache: mockCache
                        )
                    }
                    
                    func testFetchAllTasksFromNetwork() async throws {
                        // Given
                        let expectedTasks = [
                            Task(title: "Network Task 1", priority: .high),
                            Task(title: "Network Task 2", priority: .low)
                        ]
                        mockNetworkManager.mockResponse(for: "/tasks", response: expectedTasks)
                        
                        // When
                        let tasks = try await repository.fetchAll()
                        
                        // Then
                        XCTAssertEqual(tasks.count, 2)
                        XCTAssertEqual(tasks[0].title, "Network Task 1")
                        XCTAssertTrue(mockCache.didCache(key: "tasks"))
                    }
                    
                    func testFetchFromCacheWhenNetworkFails() async throws {
                        // Given
                        let cachedTasks = [Task(title: "Cached Task", priority: .medium)]
                        mockCache.store(cachedTasks, forKey: "tasks")
                        mockNetworkManager.simulateNetworkError()
                        
                        // When
                        let tasks = try await repository.fetchAll()
                        
                        // Then
                        XCTAssertEqual(tasks.count, 1)
                        XCTAssertEqual(tasks[0].title, "Cached Task")
                    }
                    
                    func testSaveTaskToNetworkAndCache() async throws {
                        // Given
                        let task = Task(title: "New Task", priority: .high)
                        mockNetworkManager.mockResponse(for: "/tasks", response: task)
                        
                        // When
                        try await repository.save(task)
                        
                        // Then
                        XCTAssertTrue(mockNetworkManager.didPost(to: "/tasks"))
                        XCTAssertTrue(mockCache.didCache(key: "task_\\(task.id)"))
                    }
                    
                    func testRetryLogicOnNetworkFailure() async throws {
                        // Given
                        mockNetworkManager.simulateNetworkError(times: 2) // Fail twice, then succeed
                        let expectedTask = Task(title: "Retry Task", priority: .medium)
                        mockNetworkManager.mockResponse(for: "/tasks/\\(expectedTask.id)", response: expectedTask)
                        
                        // When
                        let task = try await repository.fetch(id: expectedTask.id)
                        
                        // Then
                        XCTAssertEqual(task.title, "Retry Task")
                        XCTAssertEqual(mockNetworkManager.requestCount, 3) // 2 failures + 1 success
                    }
                }
                """,
                explanation: "Repository tests verify networking, caching, and error handling behavior."
            ),
            Step(
                title: "Create UI Test Helpers",
                description: "Build utilities for UI testing and snapshot testing.",
                code: """
                import XCTest
                import SwiftUI
                @testable import Archery
                
                class UITestCase: XCTestCase {
                    var app: XCUIApplication!
                    
                    override func setUp() {
                        continueAfterFailure = false
                        app = XCUIApplication()
                        app.launchArguments.append("--uitesting")
                        app.launch()
                    }
                    
                    // MARK: - Test Helpers
                    
                    func waitForElement(_ element: XCUIElement, timeout: TimeInterval = 5) {
                        let exists = NSPredicate(format: "exists == true")
                        expectation(for: exists, evaluatedWith: element, handler: nil)
                        waitForExpectations(timeout: timeout, handler: nil)
                    }
                    
                    func signIn(email: String = "test@example.com", password: String = "password") {
                        let emailField = app.textFields["Email"]
                        let passwordField = app.secureTextFields["Password"]
                        let signInButton = app.buttons["Sign In"]
                        
                        waitForElement(emailField)
                        emailField.tap()
                        emailField.typeText(email)
                        
                        passwordField.tap()
                        passwordField.typeText(password)
                        
                        signInButton.tap()
                    }
                    
                    func createTask(title: String, priority: String = "Medium") {
                        let addButton = app.buttons["Add"]
                        addButton.tap()
                        
                        let titleField = app.textFields["Task Title"]
                        waitForElement(titleField)
                        titleField.typeText(title)
                        
                        let priorityPicker = app.buttons[priority]
                        priorityPicker.tap()
                        
                        let saveButton = app.buttons["Save"]
                        saveButton.tap()
                    }
                }
                
                // Snapshot testing helper
                extension View {
                    func snapshot(
                        as name: String,
                        in container: ViewImageSnapshot.Config = .iPhone13(),
                        file: StaticString = #file,
                        line: UInt = #line
                    ) {
                        let controller = UIHostingController(rootView: self)
                        controller.view.backgroundColor = .systemBackground
                        
                        ViewImageSnapshot.assertSnapshot(
                            matching: controller,
                            as: .image(on: container),
                            named: name,
                            file: file,
                            line: line
                        )
                    }
                }
                """,
                explanation: "UI test helpers provide reusable methods for common interactions and snapshot testing."
            ),
            Step(
                title: "Write Integration Tests",
                description: "Test complete user flows end-to-end.",
                code: """
                class TaskManagementIntegrationTests: UITestCase {
                    
                    func testCompleteTaskWorkflow() throws {
                        // Sign in
                        signIn()
                        
                        // Navigate to tasks
                        let tasksTab = app.tabBars.buttons["Tasks"]
                        waitForElement(tasksTab)
                        tasksTab.tap()
                        
                        // Create a new task
                        createTask(title: "Integration Test Task", priority: "High")
                        
                        // Verify task appears in list
                        let taskCell = app.cells.containing(.staticText, identifier: "Integration Test Task")
                        waitForElement(taskCell.firstMatch)
                        XCTAssertTrue(taskCell.firstMatch.exists)
                        
                        // Mark task as complete
                        let completeButton = taskCell.firstMatch.buttons.firstMatch
                        completeButton.tap()
                        
                        // Verify task is marked complete
                        let completedTask = app.cells.containing(.staticText, identifier: "Integration Test Task")
                        XCTAssertTrue(completedTask.firstMatch.exists)
                        
                        // Delete task
                        taskCell.firstMatch.swipeLeft()
                        let deleteButton = app.buttons["Delete"]
                        deleteButton.tap()
                        
                        // Verify task is removed
                        XCTAssertFalse(taskCell.firstMatch.exists)
                    }
                    
                    func testOfflineMode() throws {
                        // Sign in
                        signIn()
                        
                        // Go offline (simulate network failure)
                        app.buttons["Network Simulator"].tap()
                        app.switches["Offline Mode"].tap()
                        
                        // Navigate to tasks
                        app.tabBars.buttons["Tasks"].tap()
                        
                        // Create task while offline
                        createTask(title: "Offline Task")
                        
                        // Verify task appears with offline indicator
                        let offlineTask = app.cells.containing(.staticText, identifier: "Offline Task")
                        XCTAssertTrue(offlineTask.firstMatch.exists)
                        
                        let syncIndicator = app.images["sync.pending"]
                        XCTAssertTrue(syncIndicator.exists)
                        
                        // Go back online
                        app.buttons["Network Simulator"].tap()
                        app.switches["Offline Mode"].tap()
                        
                        // Verify sync completes
                        let syncedTask = app.cells.containing(.staticText, identifier: "Offline Task")
                        waitForElement(syncedTask.firstMatch)
                        XCTAssertFalse(app.images["sync.pending"].exists)
                    }
                }
                """,
                explanation: "Integration tests verify complete user workflows including edge cases like offline mode."
            )
        ],
        completeExample: """
        // Complete test suite structure
        
        // Unit Tests
        class ViewModelTests: ArcheryTestCase {
            // Test ViewModels with mock dependencies
        }
        
        class RepositoryTests: XCTestCase {
            // Test repository implementations
        }
        
        class NetworkingTests: XCTestCase {
            // Test API client and networking layer
        }
        
        // Integration Tests  
        class DataFlowIntegrationTests: ArcheryTestCase {
            // Test data flow between layers
        }
        
        // UI Tests
        class UserJourneyTests: UITestCase {
            // Test complete user journeys
        }
        
        class AccessibilityTests: UITestCase {
            // Test accessibility compliance
        }
        
        // Snapshot Tests
        class ComponentSnapshotTests: XCTestCase {
            func testButtonComponents() {
                PrimaryButton("Test Button") { }
                    .snapshot(as: "primary-button")
                
                SecondaryButton("Test Button") { }
                    .snapshot(as: "secondary-button")
            }
            
            func testCardComponents() {
                InfoCard(
                    title: "Test Card",
                    subtitle: "Test subtitle",
                    icon: "star"
                )
                .snapshot(as: "info-card")
            }
        }
        
        // Performance Tests
        class PerformanceTests: XCTestCase {
            func testViewModelPerformance() {
                measure {
                    let viewModel = TaskListViewModel()
                    // Performance critical operations
                }
            }
        }
        """,
        testExample: """
        class TestSuiteRunnerTests: XCTestCase {
            func testCompleteTestSuite() throws {
                // This test verifies our test infrastructure works
                let testBundle = Bundle(for: type(of: self))
                let testClasses = [
                    "TaskListViewModelTests",
                    "TaskRepositoryTests", 
                    "UserJourneyTests"
                ]
                
                for className in testClasses {
                    XCTAssertNotNil(NSClassFromString(className), "\\(className) should exist")
                }
            }
        }
        """,
        bestPractices: [
            "Write tests before implementation (TDD approach)",
            "Use descriptive test names that explain the scenario",
            "Follow Arrange-Act-Assert pattern in test structure",
            "Mock external dependencies completely",
            "Test both success and failure scenarios",
            "Use UI tests sparingly for critical user journeys",
            "Maintain test data fixtures for consistent testing",
            "Run tests in CI/CD pipeline automatically"
        ],
        commonPitfalls: [
            Recipe.Issue(
                issue: "Tests failing due to timing issues",
                solution: "Use proper async/await patterns and expectation-based waiting in UI tests"
            ),
            Recipe.Issue(
                issue: "Flaky UI tests",
                solution: "Use stable element identification and proper waiting mechanisms"
            )
        ],
        relatedRecipes: ["Authentication Gate", "Offline Sync"],
        category: .testing
    )
}

// MARK: - Example Project Data

extension ExampleProject {
    
    static let comprehensiveSample = ExampleProject(
        name: "Comprehensive Sample App",
        description: "A complete demonstration of all Archery framework features working together in a real-world application.",
        shortDescription: "Complete framework demonstration with all features",
        features: [
            "Authentication flow with secure token storage",
            "Task management with CRUD operations", 
            "Project management with team collaboration",
            "Offline synchronization with conflict resolution",
            "Widget integration for quick task access",
            "App Intents for Siri and Shortcuts",
            "Background task processing",
            "Form validation and error handling",
            "Design system with theming",
            "Analytics tracking with PII protection",
            "Comprehensive testing suite"
        ],
        primaryFeatures: ["Authentication", "Data Management", "Offline Sync", "Widget Support"],
        architecture: """
        The sample app demonstrates a layered architecture:
        
        **Presentation Layer**: SwiftUI views bound to ViewModels using @ViewModelBound
        **Business Logic Layer**: ViewModels with @ObservableViewModel for state management  
        **Data Layer**: Repositories with @Repository for CRUD operations
        **Infrastructure Layer**: Networking, storage, analytics, and system integration
        
        Key architectural patterns:
        - Dependency injection with EnvContainer
        - Repository pattern for data access
        - MVVM with reactive updates
        - Offline-first data synchronization
        - Widget and intent integration
        """,
        runInstructions: [
            "Open the Archery project in Xcode 15+",
            "Select the 'ComprehensiveSampleApp' target", 
            "Build and run on iOS Simulator or device",
            "Sign in with demo credentials (username: demo, password: password)",
            "Explore the different tabs to see all features in action",
            "Try going offline to test sync functionality",
            "Add the widget to your home screen to test widget integration"
        ],
        keyFiles: [
            KeyFile(
                path: "Examples/ComprehensiveSampleApp.swift",
                description: "Main app structure demonstrating AppShell pattern",
                snippet: """
                @main
                struct ArcherySampleApp: App {
                    @StateObject private var container = EnvContainer()
                    @StateObject private var authManager = AuthManager()
                    
                    var body: some Scene {
                        WindowGroup {
                            if authManager.isAuthenticated {
                                MainAppView()
                                    .environmentObject(container)
                            } else {
                                AuthView()
                                    .environmentObject(authManager)
                            }
                        }
                    }
                }
                """
            ),
            KeyFile(
                path: "Examples/SampleAppSupport.swift",
                description: "ViewModels, repositories, and forms demonstrating all macros",
                snippet: """
                @ObservableViewModel(dependencies: ["TaskRepository"])
                class TaskListViewModel: ObservableObject {
                    @Published var tasks: [Task] = []
                    @Published var isLoading = false
                    
                    @MainActor
                    func loadTasks() async {
                        // ViewModel implementation
                    }
                }
                """
            )
        ],
        learningObjectives: [
            "Understand how to structure a complete Archery application",
            "Learn proper dependency injection patterns with EnvContainer",
            "See how ViewModels integrate with repositories and UI",
            "Understand authentication flow and security best practices",
            "Learn offline synchronization implementation",
            "Understand widget and intent integration patterns",
            "See comprehensive error handling and validation"
        ],
        nextSteps: [
            "Customize the UI and branding for your own app",
            "Add your own data models and business logic", 
            "Integrate with your backend API endpoints",
            "Implement additional features using Archery patterns",
            "Add platform-specific features (watchOS, macOS, etc.)",
            "Deploy to the App Store with proper configuration"
        ],
        complexity: .intermediate
    )
    
    static let widgetsIntents = ExampleProject(
        name: "Widgets & Intents Example", 
        description: "Demonstration of WidgetKit integration, App Intents, and background task coordination.",
        shortDescription: "WidgetKit and App Intents integration",
        features: [
            "Multiple widget sizes with dynamic content",
            "App Intents for Shortcuts and Siri integration",
            "Background task coordination and scheduling",
            "Shared data between app and widget using App Groups",
            "Timeline management with smart update scheduling",
            "Deep linking from widgets to app content",
            "Intent parameter validation and error handling",
            "Widget analytics and usage tracking"
        ],
        primaryFeatures: ["Widgets", "App Intents", "Background Tasks", "Data Sharing"],
        architecture: """
        This example showcases system integration patterns:
        
        **Widget Layer**: Timeline providers with shared ViewModels
        **Intent Layer**: App Intents with parameter validation
        **Background Layer**: Automated task scheduling and execution
        **Shared Layer**: Data synchronization between app and extensions
        
        Integration points:
        - App Groups for data sharing
        - Background task coordination
        - Widget timeline management
        - Intent execution and feedback
        """,
        runInstructions: [
            "Build and run the WidgetsIntentsExample target",
            "Add the widget to your home screen from the widget gallery",
            "Test Siri integration by saying 'Add a task'",
            "Use Shortcuts app to create custom automations",
            "Test background sync by force-quitting the app",
            "Monitor widget updates and background task execution"
        ],
        keyFiles: [
            KeyFile(
                path: "Examples/WidgetsIntentsExample.swift",
                description: "Complete widget and intent implementation",
                snippet: """
                @WidgetDefinition(
                    kind: "com.archery.task-widget",
                    displayName: "Task Widget",
                    description: "View your upcoming tasks"
                )
                struct TaskWidget {
                    // Implementation generated automatically
                }
                """
            )
        ],
        learningObjectives: [
            "Understand WidgetKit integration with Archery",
            "Learn App Intents implementation patterns", 
            "Master background task coordination",
            "Understand data sharing between app and extensions",
            "Learn timeline management and update strategies"
        ],
        nextSteps: [
            "Create custom widget configurations",
            "Add more App Intent types",
            "Implement Live Activities",
            "Add widget interaction capabilities",
            "Optimize background task scheduling"
        ],
        complexity: .advanced
    )
    
    static let benchmarking = ExampleProject(
        name: "Benchmarking Example",
        description: "Performance testing and benchmarking tools with Instruments integration.",
        shortDescription: "Performance testing and optimization",
        features: [
            "Microbenchmark harness for performance testing",
            "Performance budget enforcement in CI",
            "Instruments template configuration and export",
            "Performance snapshot comparison across versions",
            "Statistical analysis of performance metrics",
            "Memory usage tracking and optimization",
            "Background performance monitoring",
            "Regression detection and alerting"
        ],
        primaryFeatures: ["Performance Testing", "Benchmarking", "Instruments Integration", "CI/CD"],
        architecture: """
        Performance testing architecture:
        
        **Benchmark Layer**: Microbenchmark execution with statistical analysis
        **Budget Layer**: Performance constraint validation and enforcement
        **Instruments Layer**: Profiling template generation and signpost integration
        **Snapshot Layer**: Performance comparison and regression detection
        
        Testing workflow:
        - Automated benchmark execution
        - Performance budget validation
        - Snapshot comparison reporting
        - CI/CD integration for regression detection
        """,
        runInstructions: [
            "Run the BenchmarkingExample target",
            "Navigate through different benchmark categories",
            "Execute performance tests and view results",
            "Export Instruments templates for detailed profiling",
            "Compare performance snapshots between versions",
            "Monitor performance budgets and violations"
        ],
        keyFiles: [
            KeyFile(
                path: "Tests/ArcheryTests/BenchmarkSuite.swift",
                description: "Comprehensive benchmark test suite",
                snippet: """
                func testEnvContainerLookup() {
                    let harness = BenchmarkHarness(name: "EnvContainer")
                    
                    let result = harness.measure("Container Lookup") {
                        for i in 0..<100 {
                            _ = container.resolve("service\\(i)", as: MockService.self)
                        }
                    }
                    
                    let budget = PerformanceBudget(name: "Container") {
                        MaximumTimeConstraint(threshold: 0.001, metric: .mean)
                    }
                    
                    let validation = budget.validate(result)
                    XCTAssertTrue(validation.passed)
                }
                """
            )
        ],
        learningObjectives: [
            "Learn performance testing methodologies",
            "Understand benchmark design and implementation",
            "Master Instruments integration and profiling",
            "Understand performance budget enforcement",
            "Learn regression detection techniques"
        ],
        nextSteps: [
            "Integrate benchmarks into CI/CD pipeline",
            "Create custom performance budgets",
            "Add more platform-specific benchmarks",
            "Implement performance monitoring dashboards",
            "Optimize identified performance bottlenecks"
        ],
        complexity: .advanced
    )
    
    static let e2eTesting = ExampleProject(
        name: "E2E Testing Example",
        description: "End-to-end testing framework with UI automation, navigation fuzzing, and property-based testing.",
        shortDescription: "Comprehensive end-to-end testing",
        features: [
            "Automated UI testing for critical user flows",
            "Navigation graph fuzzing to find invalid routes",
            "Property-based testing for state machines",
            "Record/replay harness for deterministic API testing",
            "Accessibility testing automation",
            "Cross-platform test execution",
            "Test data generation and management",
            "Visual regression testing with snapshots"
        ],
        primaryFeatures: ["UI Testing", "Navigation Fuzzing", "Property Testing", "API Testing"],
        architecture: """
        E2E testing architecture:
        
        **UI Test Layer**: Automated testing of critical user journeys
        **Fuzzing Layer**: Random navigation and input testing
        **Property Layer**: Mathematical property verification
        **API Layer**: Deterministic request/response testing
        
        Testing pyramid:
        - Unit tests for individual components
        - Integration tests for layer interactions  
        - E2E tests for complete user journeys
        - Performance tests for optimization
        """,
        runInstructions: [
            "Run the E2ETestingExample target",
            "Execute the full test suite to see all testing approaches",
            "Run navigation fuzzing to discover edge cases",
            "Use record/replay for API test creation",
            "Generate property-based test cases",
            "View test coverage and results reporting"
        ],
        keyFiles: [
            KeyFile(
                path: "Tests/ArcheryTests/E2ETestSuite.swift",
                description: "Complete E2E testing demonstration",
                snippet: """
                func testCompleteUserJourney() async throws {
                    let runner = UITestRunner()
                    
                    try await runner.runCriticalFlow(.authentication) { flow in
                        try await flow.signIn(username: "test", password: "password")
                        try await flow.navigateToTasks()
                        try await flow.createTask(title: "E2E Test Task")
                        try await flow.verifyTaskExists("E2E Test Task")
                    }
                }
                """
            )
        ],
        learningObjectives: [
            "Master UI testing automation techniques",
            "Understand navigation fuzzing concepts",
            "Learn property-based testing principles",
            "Understand deterministic API testing",
            "Learn test data management strategies"
        ],
        nextSteps: [
            "Integrate E2E tests into CI/CD pipeline",
            "Add more sophisticated fuzzing strategies",
            "Implement visual regression testing",
            "Create custom property-based test generators",
            "Add performance testing to E2E suites"
        ],
        complexity: .advanced
    )
}