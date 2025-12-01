import SwiftUI
import WidgetKit

#if canImport(AppIntents)
import AppIntents
#endif

// MARK: - Comprehensive Archery Sample App
// This demonstrates all major framework features working together

@main
struct ArcherySampleApp: App {
    
    @StateObject private var container = EnvContainer()
    @StateObject private var authManager = AuthManager()
    
    init() {
        setupArchery()
    }
    
    var body: some Scene {
        WindowGroup {
            if authManager.isAuthenticated {
                MainAppView()
                    .environmentObject(container)
                    .environmentObject(authManager)
                    .onAppear {
                        setupAppearance()
                    }
            } else {
                AuthView()
                    .environmentObject(authManager)
            }
        }
    }
    
    private func setupArchery() {
        // Register all repositories
        container.register(UserRepository.self) { UserRepository() }
        container.register(ProjectRepository.self) { ProjectRepository() }
        container.register(TaskRepository.self) { TaskRepository() }
        container.register(SettingsRepository.self) { SettingsRepository() }
        
        // Register ViewModels
        container.register(ProjectListViewModel.self) { 
            ProjectListViewModel(container: container) 
        }
        container.register(TaskListViewModel.self) { 
            TaskListViewModel(container: container) 
        }
        container.register(SettingsViewModel.self) { 
            SettingsViewModel(container: container) 
        }
        
        // Setup networking
        NetworkManager.shared.configure(baseURL: "https://api.archery-sample.com")
        
        // Configure analytics
        AnalyticsManager.shared = AnalyticsManager()
        
        // Setup background tasks
        #if canImport(BackgroundTasks) && !targetEnvironment(simulator)
        BackgroundTaskCoordinator.shared.configure()
        #endif
        
        EnvContainer.shared = container
    }
    
    private func setupAppearance() {
        // Apply design tokens
        DesignTokens.apply()
        
        // Setup navigation appearance
        let appearance = UINavigationBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = UIColor(Color.primary.opacity(0.1))
        
        UINavigationBar.appearance().standardAppearance = appearance
        UINavigationBar.appearance().scrollEdgeAppearance = appearance
    }
}

// MARK: - Auth View

struct AuthView: View {
    @EnvironmentObject var authManager: AuthManager
    @State private var username = ""
    @State private var password = ""
    @State private var isLoading = false
    
    var body: some View {
        VStack(spacing: 24) {
            // Logo and branding
            Image(systemName: "target")
                .font(.system(size: 64))
                .foregroundColor(.blue)
            
            Text("Archery Sample")
                .font(.largeTitle)
                .fontWeight(.bold)
            
            Text("A comprehensive demonstration of the Archery framework")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            
            // Auth form using Forms & Validation
            VStack(spacing: 16) {
                TextField("Username", text: $username)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .autocapitalization(.none)
                
                SecureField("Password", text: $password)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                
                Button(action: signIn) {
                    HStack {
                        if isLoading {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                .scaleEffect(0.8)
                        }
                        Text(isLoading ? "Signing In..." : "Sign In")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(12)
                }
                .disabled(isLoading || username.isEmpty || password.isEmpty)
            }
            .padding(.horizontal, 32)
            
            Spacer()
            
            // Demo credentials
            VStack {
                Text("Demo Credentials:")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text("Username: demo")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text("Password: password")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.bottom)
        }
        .padding()
    }
    
    private func signIn() {
        isLoading = true
        
        Task {
            await authManager.signIn(username: username, password: password)
            isLoading = false
        }
    }
}

// MARK: - Main App View using AppShell

struct MainAppView: View {
    var body: some View {
        AppShellView {
            ProjectsTab()
            TasksTab()
            AnalyticsTab()
            SettingsTab()
        }
    }
}

@ViewBuilder
func ProjectsTab() -> some View {
    NavigationView {
        ProjectListView()
    }
    .tabItem {
        Label("Projects", systemImage: "folder")
    }
}

@ViewBuilder
func TasksTab() -> some View {
    NavigationView {
        TaskListView()
    }
    .tabItem {
        Label("Tasks", systemImage: "checkmark.circle")
    }
}

@ViewBuilder
func AnalyticsTab() -> some View {
    NavigationView {
        AnalyticsView()
    }
    .tabItem {
        Label("Analytics", systemImage: "chart.bar")
    }
}

@ViewBuilder
func SettingsTab() -> some View {
    NavigationView {
        SettingsView()
    }
    .tabItem {
        Label("Settings", systemImage: "gear")
    }
}

// MARK: - Project List (Repository + ObservableViewModel + ViewModelBound)

@ViewModelBound(ProjectListViewModel.self)
struct ProjectListView: View {
    
    var body: some View {
        List {
            ForEach(viewModel.projects) { project in
                NavigationLink(destination: ProjectDetailView(project: project)) {
                    ProjectRowView(project: project)
                }
            }
            .onDelete(perform: viewModel.deleteProjects)
        }
        .navigationTitle("Projects")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Add") {
                    viewModel.showAddProject = true
                }
            }
        }
        .sheet(isPresented: $viewModel.showAddProject) {
            AddProjectView()
        }
        .refreshable {
            await viewModel.refresh()
        }
        .searchable(text: $viewModel.searchText)
        .task {
            await viewModel.loadProjects()
        }
    }
}

struct ProjectRowView: View {
    let project: Project
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(project.name)
                .font(.headline)
            
            Text(project.description)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .lineLimit(2)
            
            HStack {
                Label("\(project.taskCount)", systemImage: "checkmark.circle")
                    .font(.caption)
                    .foregroundColor(.blue)
                
                Spacer()
                
                Text(project.updatedAt, style: .date)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Project Detail with Forms & Validation

struct ProjectDetailView: View {
    let project: Project
    @State private var isEditing = false
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Project header
                VStack(alignment: .leading, spacing: 8) {
                    Text(project.name)
                        .font(.largeTitle)
                        .fontWeight(.bold)
                    
                    Text(project.description)
                        .font(.body)
                        .foregroundColor(.secondary)
                }
                
                // Project stats using Design System
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 2)) {
                    StatCard(title: "Tasks", value: "\(project.taskCount)", color: .blue)
                    StatCard(title: "Progress", value: "\(Int(project.progress * 100))%", color: .green)
                    StatCard(title: "Team Members", value: "\(project.memberCount)", color: .purple)
                    StatCard(title: "Due Date", value: project.dueDate.formatted(date: .abbreviated, time: .omitted), color: .orange)
                }
                
                Spacer()
            }
            .padding()
        }
        .navigationTitle("Project")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Edit") {
                    isEditing = true
                }
            }
        }
        .sheet(isPresented: $isEditing) {
            EditProjectView(project: project)
        }
    }
}

struct StatCard: View {
    let title: String
    let value: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 8) {
            Text(value)
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(color)
            
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color.gray.opacity(0.1))
        .cornerRadius(12)
    }
}

// MARK: - Forms & Validation Example

struct AddProjectView: View {
    @Environment(\.dismiss) var dismiss
    @StateObject private var form = ProjectForm()
    
    var body: some View {
        NavigationView {
            Form {
                Section("Project Details") {
                    TextField("Project Name", text: $form.name)
                        .autocapitalization(.words)
                    
                    TextField("Description", text: $form.description, axis: .vertical)
                        .lineLimit(3...6)
                    
                    DatePicker("Due Date", selection: $form.dueDate, displayedComponents: .date)
                }
                
                Section("Team") {
                    Stepper("Team Members: \(form.memberCount)", value: $form.memberCount, in: 1...20)
                }
                
                if !form.validationErrors.isEmpty {
                    Section("Errors") {
                        ForEach(form.validationErrors, id: \.self) { error in
                            Text(error)
                                .foregroundColor(.red)
                                .font(.caption)
                        }
                    }
                }
            }
            .navigationTitle("New Project")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        Task {
                            if await form.save() {
                                dismiss()
                            }
                        }
                    }
                    .disabled(!form.isValid)
                }
            }
        }
    }
}

struct EditProjectView: View {
    let project: Project
    @Environment(\.dismiss) var dismiss
    @StateObject private var form = ProjectForm()
    
    var body: some View {
        NavigationView {
            Form {
                Section("Project Details") {
                    TextField("Project Name", text: $form.name)
                        .autocapitalization(.words)
                    
                    TextField("Description", text: $form.description, axis: .vertical)
                        .lineLimit(3...6)
                    
                    DatePicker("Due Date", selection: $form.dueDate, displayedComponents: .date)
                }
                
                Section("Team") {
                    Stepper("Team Members: \(form.memberCount)", value: $form.memberCount, in: 1...20)
                }
                
                if !form.validationErrors.isEmpty {
                    Section("Errors") {
                        ForEach(form.validationErrors, id: \.self) { error in
                            Text(error)
                                .foregroundColor(.red)
                                .font(.caption)
                        }
                    }
                }
            }
            .navigationTitle("Edit Project")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        Task {
                            if await form.update(project) {
                                dismiss()
                            }
                        }
                    }
                    .disabled(!form.isValid)
                }
            }
        }
        .onAppear {
            form.load(from: project)
        }
    }
}

// MARK: - Task List with KeyValueStore persistence

@ViewModelBound(TaskListViewModel.self)
struct TaskListView: View {
    
    var body: some View {
        List {
            ForEach(viewModel.tasks) { task in
                TaskRowView(task: task) {
                    viewModel.toggleTask(task)
                }
            }
            .onDelete(perform: viewModel.deleteTasks)
        }
        .navigationTitle("Tasks")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Add") {
                    viewModel.showAddTask = true
                }
            }
        }
        .sheet(isPresented: $viewModel.showAddTask) {
            AddTaskView()
        }
        .task {
            await viewModel.loadTasks()
        }
    }
}

struct TaskRowView: View {
    let task: Task
    let onToggle: () -> Void
    
    var body: some View {
        HStack {
            Button(action: onToggle) {
                Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(task.isCompleted ? .green : .gray)
            }
            .buttonStyle(PlainButtonStyle())
            
            VStack(alignment: .leading, spacing: 4) {
                Text(task.title)
                    .strikethrough(task.isCompleted)
                    .font(.headline)
                
                if !task.description.isEmpty {
                    Text(task.description)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
                
                HStack {
                    Label(task.priority.displayName, systemImage: task.priority.icon)
                        .font(.caption)
                        .foregroundColor(task.priority.color)
                    
                    Spacer()
                    
                    Text(task.createdAt, style: .relative)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
        }
        .padding(.vertical, 4)
    }
}

struct AddTaskView: View {
    @Environment(\.dismiss) var dismiss
    @StateObject private var form = TaskForm()
    
    var body: some View {
        NavigationView {
            Form {
                Section("Task Details") {
                    TextField("Title", text: $form.title)
                        .autocapitalization(.sentences)
                    
                    TextField("Description", text: $form.description, axis: .vertical)
                        .lineLimit(2...4)
                }
                
                Section("Properties") {
                    Picker("Priority", selection: $form.priority) {
                        ForEach(TaskPriority.allCases, id: \.self) { priority in
                            Label(priority.displayName, systemImage: priority.icon)
                                .tag(priority)
                        }
                    }
                    
                    DatePicker("Due Date", selection: $form.dueDate, displayedComponents: [.date, .hourAndMinute])
                }
            }
            .navigationTitle("New Task")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        Task {
                            if await form.save() {
                                dismiss()
                            }
                        }
                    }
                    .disabled(form.title.isEmpty)
                }
            }
        }
    }
}

// MARK: - Analytics View

struct AnalyticsView: View {
    @StateObject private var analyticsData = AnalyticsData()
    
    var body: some View {
        ScrollView {
            LazyVStack(spacing: 20) {
                // Key Metrics
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 2)) {
                    MetricCard(title: "Total Projects", value: "\(analyticsData.totalProjects)", trend: .up(12))
                    MetricCard(title: "Completed Tasks", value: "\(analyticsData.completedTasks)", trend: .up(8))
                    MetricCard(title: "Active Users", value: "\(analyticsData.activeUsers)", trend: .down(2))
                    MetricCard(title: "Avg Completion", value: "\(Int(analyticsData.avgCompletion * 100))%", trend: .up(5))
                }
                
                // Charts would go here in real implementation
                VStack(alignment: .leading, spacing: 12) {
                    Text("Project Progress")
                        .font(.headline)
                    
                    ForEach(analyticsData.projectProgress, id: \.name) { project in
                        ProgressRowView(project: project)
                    }
                }
                .padding()
                .background(Color.gray.opacity(0.1))
                .cornerRadius(12)
                
                // Recent Activity
                VStack(alignment: .leading, spacing: 12) {
                    Text("Recent Activity")
                        .font(.headline)
                    
                    ForEach(analyticsData.recentActivity, id: \.id) { activity in
                        ActivityRowView(activity: activity)
                    }
                }
                .padding()
                .background(Color.gray.opacity(0.1))
                .cornerRadius(12)
            }
            .padding()
        }
        .navigationTitle("Analytics")
        .task {
            await analyticsData.loadData()
        }
        .refreshable {
            await analyticsData.refresh()
        }
    }
}

struct MetricCard: View {
    let title: String
    let value: String
    let trend: Trend
    
    enum Trend {
        case up(Int)
        case down(Int)
        case flat
        
        var color: Color {
            switch self {
            case .up: return .green
            case .down: return .red
            case .flat: return .gray
            }
        }
        
        var icon: String {
            switch self {
            case .up: return "arrow.up.right"
            case .down: return "arrow.down.right"
            case .flat: return "minus"
            }
        }
        
        var text: String {
            switch self {
            case .up(let percent): return "+\(percent)%"
            case .down(let percent): return "-\(percent)%"
            case .flat: return "0%"
            }
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                HStack(spacing: 2) {
                    Image(systemName: trend.icon)
                        .font(.caption2)
                    Text(trend.text)
                        .font(.caption2)
                }
                .foregroundColor(trend.color)
            }
            
            Text(value)
                .font(.title2)
                .fontWeight(.bold)
        }
        .padding()
        .background(Color.gray.opacity(0.1))
        .cornerRadius(10)
    }
}

struct ProgressRowView: View {
    let project: ProjectProgress
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(project.name)
                    .font(.subheadline)
                Spacer()
                Text("\(Int(project.progress * 100))%")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            ProgressView(value: project.progress)
                .progressViewStyle(LinearProgressViewStyle(tint: .blue))
        }
    }
}

struct ActivityRowView: View {
    let activity: RecentActivity
    
    var body: some View {
        HStack {
            Image(systemName: activity.icon)
                .foregroundColor(activity.color)
                .frame(width: 20, height: 20)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(activity.title)
                    .font(.subheadline)
                Text(activity.description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Text(activity.timestamp, style: .relative)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - Settings with KeyValueStore

@ViewModelBound(SettingsViewModel.self)
struct SettingsView: View {
    @EnvironmentObject var authManager: AuthManager
    
    var body: some View {
        Form {
            Section("Preferences") {
                HStack {
                    Text("Theme")
                    Spacer()
                    Picker("Theme", selection: $viewModel.theme) {
                        ForEach(Theme.allCases, id: \.self) { theme in
                            Text(theme.displayName).tag(theme)
                        }
                    }
                    .pickerStyle(MenuPickerStyle())
                }
                
                Toggle("Push Notifications", isOn: $viewModel.notificationsEnabled)
                
                HStack {
                    Text("Language")
                    Spacer()
                    Picker("Language", selection: $viewModel.language) {
                        ForEach(Language.allCases, id: \.self) { language in
                            Text(language.displayName).tag(language)
                        }
                    }
                    .pickerStyle(MenuPickerStyle())
                }
            }
            
            Section("Data") {
                Button("Export Data") {
                    Task {
                        await viewModel.exportData()
                    }
                }
                
                Button("Clear Cache") {
                    viewModel.clearCache()
                }
                .foregroundColor(.orange)
            }
            
            Section("About") {
                HStack {
                    Text("Version")
                    Spacer()
                    Text("1.0.0")
                        .foregroundColor(.secondary)
                }
                
                Link("Privacy Policy", destination: URL(string: "https://archery.example.com/privacy")!)
                Link("Terms of Service", destination: URL(string: "https://archery.example.com/terms")!)
            }
            
            Section {
                Button("Sign Out") {
                    authManager.signOut()
                }
                .foregroundColor(.red)
            }
        }
        .navigationTitle("Settings")
    }
}

// MARK: - Data Models

struct Project: Identifiable, Codable {
    let id = UUID()
    let name: String
    let description: String
    let taskCount: Int
    let progress: Double
    let memberCount: Int
    let dueDate: Date
    let createdAt: Date
    let updatedAt: Date
    
    init(name: String, description: String, taskCount: Int = 0, progress: Double = 0, memberCount: Int = 1, dueDate: Date = Date().addingTimeInterval(86400 * 30)) {
        self.name = name
        self.description = description
        self.taskCount = taskCount
        self.progress = progress
        self.memberCount = memberCount
        self.dueDate = dueDate
        self.createdAt = Date()
        self.updatedAt = Date()
    }
}

struct Task: Identifiable, Codable {
    let id = UUID()
    let title: String
    let description: String
    let priority: TaskPriority
    let createdAt: Date
    let dueDate: Date
    var isCompleted: Bool
    
    init(title: String, description: String = "", priority: TaskPriority = .medium, dueDate: Date = Date().addingTimeInterval(86400)) {
        self.title = title
        self.description = description
        self.priority = priority
        self.createdAt = Date()
        self.dueDate = dueDate
        self.isCompleted = false
    }
}

enum TaskPriority: String, CaseIterable, Codable {
    case low, medium, high, urgent
    
    var displayName: String {
        switch self {
        case .low: return "Low"
        case .medium: return "Medium"
        case .high: return "High"
        case .urgent: return "Urgent"
        }
    }
    
    var icon: String {
        switch self {
        case .low: return "minus.circle"
        case .medium: return "circle"
        case .high: return "exclamationmark.circle"
        case .urgent: return "exclamationmark.triangle"
        }
    }
    
    var color: Color {
        switch self {
        case .low: return .gray
        case .medium: return .blue
        case .high: return .orange
        case .urgent: return .red
        }
    }
}

struct User: Identifiable, Codable {
    let id = UUID()
    let username: String
    let email: String
    let name: String
    let createdAt: Date
    
    init(username: String, email: String, name: String) {
        self.username = username
        self.email = email
        self.name = name
        self.createdAt = Date()
    }
}

struct ProjectProgress {
    let name: String
    let progress: Double
}

struct RecentActivity: Identifiable {
    let id = UUID()
    let title: String
    let description: String
    let icon: String
    let color: Color
    let timestamp: Date
}

enum Theme: String, CaseIterable, Codable {
    case system, light, dark
    
    var displayName: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }
}

enum Language: String, CaseIterable, Codable {
    case english = "en"
    case spanish = "es"
    case french = "fr"
    case german = "de"
    
    var displayName: String {
        switch self {
        case .english: return "English"
        case .spanish: return "Español"
        case .french: return "Français"
        case .german: return "Deutsch"
        }
    }
}