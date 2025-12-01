import Foundation
import SwiftUI

// MARK: - ViewModels

@MainActor
@ObservableViewModel
class ProjectListViewModel: ObservableObject {
    @Published var projects: [Project] = []
    @Published var searchText: String = ""
    @Published var showAddProject: Bool = false
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    
    private let container: EnvContainer
    private var repository: ProjectRepository { container.resolve(ProjectRepository.self)! }
    
    init(container: EnvContainer) {
        self.container = container
    }
    
    func loadProjects() async {
        isLoading = true
        errorMessage = nil
        
        do {
            let allProjects = try await repository.fetchAll()
            projects = filterProjects(allProjects)
        } catch {
            errorMessage = error.localizedDescription
        }
        
        isLoading = false
    }
    
    func refresh() async {
        await loadProjects()
        
        // Track analytics
        AnalyticsManager.shared?.track(
            event: "projects_refreshed",
            properties: ["count": projects.count]
        )
    }
    
    func deleteProjects(at offsets: IndexSet) {
        Task {
            for index in offsets {
                let project = projects[index]
                try? await repository.delete(id: project.id)
            }
            projects.remove(atOffsets: offsets)
            
            AnalyticsManager.shared?.track(
                event: "projects_deleted",
                properties: ["count": offsets.count]
            )
        }
    }
    
    private func filterProjects(_ allProjects: [Project]) -> [Project] {
        if searchText.isEmpty {
            return allProjects
        } else {
            return allProjects.filter { project in
                project.name.localizedCaseInsensitiveContains(searchText) ||
                project.description.localizedCaseInsensitiveContains(searchText)
            }
        }
    }
}

@MainActor
@ObservableViewModel
class TaskListViewModel: ObservableObject {
    @Published var tasks: [Task] = []
    @Published var showAddTask: Bool = false
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    
    private let container: EnvContainer
    private var repository: TaskRepository { container.resolve(TaskRepository.self)! }
    
    init(container: EnvContainer) {
        self.container = container
    }
    
    func loadTasks() async {
        isLoading = true
        errorMessage = nil
        
        do {
            tasks = try await repository.fetchAll()
        } catch {
            errorMessage = error.localizedDescription
        }
        
        isLoading = false
    }
    
    func toggleTask(_ task: Task) {
        Task {
            var updatedTask = task
            updatedTask.isCompleted.toggle()
            
            try? await repository.save(updatedTask)
            
            if let index = tasks.firstIndex(where: { $0.id == task.id }) {
                tasks[index] = updatedTask
            }
            
            AnalyticsManager.shared?.track(
                event: "task_toggled",
                properties: [
                    "task_id": task.id.uuidString,
                    "completed": updatedTask.isCompleted
                ]
            )
        }
    }
    
    func deleteTasks(at offsets: IndexSet) {
        Task {
            for index in offsets {
                let task = tasks[index]
                try? await repository.delete(id: task.id)
            }
            tasks.remove(atOffsets: offsets)
        }
    }
}

@MainActor
@ObservableViewModel
class SettingsViewModel: ObservableObject {
    @Published var theme: Theme = .system
    @Published var notificationsEnabled: Bool = true
    @Published var language: Language = .english
    
    private let container: EnvContainer
    private var settingsStore: SettingsStore { container.resolve(SettingsStore.self)! }
    
    init(container: EnvContainer) {
        self.container = container
        loadSettings()
    }
    
    private func loadSettings() {
        Task {
            theme = await settingsStore.theme
            notificationsEnabled = await settingsStore.notificationsEnabled
            language = await settingsStore.language
        }
    }
    
    func exportData() async {
        // Mock implementation
        AnalyticsManager.shared?.track(event: "data_exported")
    }
    
    func clearCache() {
        // Clear cache implementation
        AnalyticsManager.shared?.track(event: "cache_cleared")
    }
}

// MARK: - Forms

@MainActor
class ProjectForm: ObservableObject {
    @Published var name: String = ""
    @Published var description: String = ""
    @Published var dueDate: Date = Date().addingTimeInterval(86400 * 30)
    @Published var memberCount: Int = 1
    @Published var validationErrors: [String] = []
    
    private let repository = ProjectRepository()
    
    var isValid: Bool {
        validateForm()
        return validationErrors.isEmpty
    }
    
    @discardableResult
    private func validateForm() -> Bool {
        validationErrors = []
        
        if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            validationErrors.append("Project name is required")
        }
        
        if name.count > 100 {
            validationErrors.append("Project name must be less than 100 characters")
        }
        
        if description.count > 500 {
            validationErrors.append("Description must be less than 500 characters")
        }
        
        if dueDate < Date() {
            validationErrors.append("Due date must be in the future")
        }
        
        if memberCount < 1 {
            validationErrors.append("Must have at least one team member")
        }
        
        return validationErrors.isEmpty
    }
    
    func save() async -> Bool {
        guard validateForm() else { return false }
        
        let project = Project(
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            description: description.trimmingCharacters(in: .whitespacesAndNewlines),
            memberCount: memberCount,
            dueDate: dueDate
        )
        
        do {
            try await repository.save(project)
            
            AnalyticsManager.shared?.track(
                event: "project_created",
                properties: [
                    "name_length": name.count,
                    "has_description": !description.isEmpty,
                    "member_count": memberCount
                ]
            )
            
            return true
        } catch {
            validationErrors.append("Failed to save project: \(error.localizedDescription)")
            return false
        }
    }
    
    func update(_ project: Project) async -> Bool {
        guard validateForm() else { return false }
        
        // Update logic would go here
        return true
    }
    
    func load(from project: Project) {
        name = project.name
        description = project.description
        dueDate = project.dueDate
        memberCount = project.memberCount
    }
}

@MainActor
class TaskForm: ObservableObject {
    @Published var title: String = ""
    @Published var description: String = ""
    @Published var priority: TaskPriority = .medium
    @Published var dueDate: Date = Date().addingTimeInterval(86400)
    
    private let repository = TaskRepository()
    
    func save() async -> Bool {
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return false
        }
        
        let task = Task(
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            description: description.trimmingCharacters(in: .whitespacesAndNewlines),
            priority: priority,
            dueDate: dueDate
        )
        
        do {
            try await repository.save(task)
            
            AnalyticsManager.shared?.track(
                event: "task_created",
                properties: [
                    "priority": priority.rawValue,
                    "has_description": !description.isEmpty,
                    "due_in_hours": Int(dueDate.timeIntervalSince(Date()) / 3600)
                ]
            )
            
            return true
        } catch {
            return false
        }
    }
}

// MARK: - Repositories

@Repository
class ProjectRepository: DataRepository {
    typealias Model = Project
    
    private let networkManager = NetworkManager.shared
    private let cache = ProjectCache()
    
    func fetch(id: UUID) async throws -> Project {
        // Try cache first
        if let cached = cache.get(id: id) {
            return cached
        }
        
        // Fetch from network
        let project = try await networkManager.get("/projects/\(id.uuidString)", type: Project.self)
        cache.set(project, id: id)
        return project
    }
    
    func fetchAll() async throws -> [Project] {
        // Mock data for demo
        return [
            Project(
                name: "Mobile App Redesign",
                description: "Complete overhaul of the mobile application UI/UX",
                taskCount: 24,
                progress: 0.65,
                memberCount: 5
            ),
            Project(
                name: "API Migration",
                description: "Migrate from REST to GraphQL API",
                taskCount: 18,
                progress: 0.30,
                memberCount: 3
            ),
            Project(
                name: "Database Optimization",
                description: "Improve database query performance and indexing",
                taskCount: 12,
                progress: 0.85,
                memberCount: 2
            ),
            Project(
                name: "Security Audit",
                description: "Comprehensive security review and penetration testing",
                taskCount: 8,
                progress: 0.20,
                memberCount: 4
            )
        ]
    }
    
    func save(_ model: Project) async throws {
        cache.set(model, id: model.id)
        try await networkManager.post("/projects", body: model)
    }
    
    func delete(id: UUID) async throws {
        cache.remove(id: id)
        try await networkManager.delete("/projects/\(id.uuidString)")
    }
}

@Repository
class TaskRepository: DataRepository {
    typealias Model = Task
    
    private let networkManager = NetworkManager.shared
    private let cache = TaskCache()
    
    func fetch(id: UUID) async throws -> Task {
        if let cached = cache.get(id: id) {
            return cached
        }
        
        let task = try await networkManager.get("/tasks/\(id.uuidString)", type: Task.self)
        cache.set(task, id: id)
        return task
    }
    
    func fetchAll() async throws -> [Task] {
        // Mock data for demo
        return [
            Task(
                title: "Design new login screen",
                description: "Create wireframes and mockups for the new login experience",
                priority: .high
            ),
            Task(
                title: "Implement OAuth integration",
                description: "Add support for Google and Apple sign-in",
                priority: .medium
            ),
            Task(
                title: "Write unit tests",
                description: "Increase test coverage to 90%",
                priority: .medium
            ),
            Task(
                title: "Update documentation",
                description: "Document new API endpoints",
                priority: .low
            ),
            Task(
                title: "Fix critical bug",
                description: "App crashes on iPhone 12 Pro Max",
                priority: .urgent
            )
        ]
    }
    
    func save(_ model: Task) async throws {
        cache.set(model, id: model.id)
        try await networkManager.post("/tasks", body: model)
    }
    
    func delete(id: UUID) async throws {
        cache.remove(id: id)
        try await networkManager.delete("/tasks/\(id.uuidString)")
    }
}

@Repository
class UserRepository: DataRepository {
    typealias Model = User
    
    func fetch(id: UUID) async throws -> User {
        return User(username: "demo", email: "demo@archery.com", name: "Demo User")
    }
    
    func fetchAll() async throws -> [User] {
        return [fetch(id: UUID())]
    }
    
    func save(_ model: User) async throws {
        // Implementation
    }
    
    func delete(id: UUID) async throws {
        // Implementation
    }
}

@Repository
class SettingsRepository: DataRepository {
    typealias Model = Setting
    
    func fetch(id: UUID) async throws -> Setting {
        return Setting(key: "demo", value: "value")
    }
    
    func fetchAll() async throws -> [Setting] {
        return []
    }
    
    func save(_ model: Setting) async throws {
        // Implementation
    }
    
    func delete(id: UUID) async throws {
        // Implementation
    }
}

struct Setting: Identifiable, Codable {
    let id = UUID()
    let key: String
    let value: String
}

// MARK: - KeyValueStore for Settings

@KeyValueStore
struct SettingsStore {
    var theme: Theme = .system
    var notificationsEnabled: Bool = true
    var language: Language = .english
    var lastSyncDate: Date = Date.distantPast
}

// MARK: - Cache Classes

class ProjectCache {
    private var cache: [UUID: Project] = [:]
    
    func get(id: UUID) -> Project? {
        return cache[id]
    }
    
    func set(_ project: Project, id: UUID) {
        cache[id] = project
    }
    
    func remove(id: UUID) {
        cache.removeValue(forKey: id)
    }
}

class TaskCache {
    private var cache: [UUID: Task] = [:]
    
    func get(id: UUID) -> Task? {
        return cache[id]
    }
    
    func set(_ task: Task, id: UUID) {
        cache[id] = task
    }
    
    func remove(id: UUID) {
        cache.removeValue(forKey: id)
    }
}

// MARK: - Auth Manager

@MainActor
class AuthManager: ObservableObject {
    @Published var isAuthenticated: Bool = false
    @Published var currentUser: User?
    
    func signIn(username: String, password: String) async {
        // Mock authentication
        if username == "demo" && password == "password" {
            isAuthenticated = true
            currentUser = User(username: username, email: "demo@archery.com", name: "Demo User")
            
            AnalyticsManager.shared?.track(
                event: "user_signed_in",
                properties: ["username": username]
            )
        }
    }
    
    func signOut() {
        isAuthenticated = false
        currentUser = nil
        
        AnalyticsManager.shared?.track(event: "user_signed_out")
    }
}

// MARK: - Analytics Data

@MainActor
class AnalyticsData: ObservableObject {
    @Published var totalProjects: Int = 0
    @Published var completedTasks: Int = 0
    @Published var activeUsers: Int = 0
    @Published var avgCompletion: Double = 0.0
    @Published var projectProgress: [ProjectProgress] = []
    @Published var recentActivity: [RecentActivity] = []
    
    func loadData() async {
        // Mock data
        totalProjects = 24
        completedTasks = 142
        activeUsers = 8
        avgCompletion = 0.73
        
        projectProgress = [
            ProjectProgress(name: "Mobile App", progress: 0.85),
            ProjectProgress(name: "API Migration", progress: 0.42),
            ProjectProgress(name: "Security Audit", progress: 0.20),
            ProjectProgress(name: "Database Opt", progress: 0.90)
        ]
        
        recentActivity = [
            RecentActivity(
                title: "Task completed",
                description: "Design system components finished",
                icon: "checkmark.circle",
                color: .green,
                timestamp: Date().addingTimeInterval(-1800)
            ),
            RecentActivity(
                title: "New project created",
                description: "Mobile app redesign started",
                icon: "plus.circle",
                color: .blue,
                timestamp: Date().addingTimeInterval(-3600)
            ),
            RecentActivity(
                title: "Team member added",
                description: "Sarah joined the design team",
                icon: "person.badge.plus",
                color: .purple,
                timestamp: Date().addingTimeInterval(-7200)
            )
        ]
    }
    
    func refresh() async {
        await loadData()
    }
}

// MARK: - Design Tokens

struct DesignTokens {
    static func apply() {
        // Apply design system tokens
        // This would set up colors, fonts, spacing, etc.
    }
}

// MARK: - App Shell

struct AppShellView<Content: View>: View {
    let content: Content
    
    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }
    
    var body: some View {
        TabView {
            content
        }
    }
}