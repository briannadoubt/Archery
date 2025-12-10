import Foundation
import SwiftUI
import Archery

// MARK: - Advanced Macros Showcase
//
// This file demonstrates the advanced macros in Archery:
// - @APIClient - Networking with retry, caching, and DI
// - @ViewModelBound - DI-aware View binding
// - @PersistenceGateway - SQLite-backed persistence
//
// Note: @AppShell and @SharedModel are demonstrated conceptually
// as they require specific app structure (main App entry point)
// or WidgetKit/ActivityKit targets.

// MARK: - @APIClient Demo
// The @APIClient macro generates:
// - Protocol (TaskAPIProtocol)
// - Live implementation (TaskAPILive) with retry/caching
// - Mock implementation (MockTaskAPI)
// - DI helpers (.live(), .make(in:), .makeChild(from:))

@APIClient
class TaskAPI {
    /// Fetch all tasks from the server
    func fetchTasks() async throws -> [APITask] {
        let url = URL(string: "https://api.example.com/tasks")!
        let (data, _) = try await URLSession.shared.data(from: url)
        return try JSONDecoder().decode([APITask].self, from: data)
    }

    /// Fetch a single task by ID
    @Cache(ttl: .seconds(60))
    func fetchTask(id: String) async throws -> APITask {
        let url = URL(string: "https://api.example.com/tasks/\(id)")!
        let (data, _) = try await URLSession.shared.data(from: url)
        return try JSONDecoder().decode(APITask.self, from: data)
    }

    /// Create a new task
    func createTask(title: String, priority: String) async throws -> APITask {
        var request = URLRequest(url: URL(string: "https://api.example.com/tasks")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(["title": title, "priority": priority])
        let (data, _) = try await URLSession.shared.data(for: request)
        return try JSONDecoder().decode(APITask.self, from: data)
    }

    /// Delete a task
    func deleteTask(id: String) async throws {
        var request = URLRequest(url: URL(string: "https://api.example.com/tasks/\(id)")!)
        request.httpMethod = "DELETE"
        let _ = try await URLSession.shared.data(for: request)
    }
}

/// Task model for API responses
struct APITask: Codable, Identifiable, Sendable {
    let id: String
    let title: String
    let priority: String
    let completed: Bool
}

// MARK: - @PersistenceGateway Demo
// The @PersistenceGateway macro generates:
// - keyName property for each case
// - Gateway struct with typed getters/setters
// - SQLite-backed storage with migrations

@PersistenceGateway
enum AppStorage {
    case userProfile(UserProfile)
    case settings(AppSettings)
    case lastSyncDate(Date)
    case cachedTasks([CachedTask])
}

struct UserProfile: Codable {
    var name: String
    var email: String
    var avatarURL: URL?
}

struct AppSettings: Codable {
    var theme: String = "system"
    var notificationsEnabled: Bool = true
    var syncInterval: TimeInterval = 300
}

struct CachedTask: Codable, Identifiable {
    let id: String
    var title: String
    var completed: Bool
}

// MARK: - Simple ViewModel for Demo
// Using @Observable (built-in) for simplicity in this demo.
// The @ObservableViewModel macro adds lifecycle management,
// Resettable conformance, and DI integration.

@Observable
@MainActor
final class APIClientDemoViewModel {
    var tasks: [APITask] = []
    var isLoading = false
    var errorMessage: String?

    // In a real app, this would be injected via DI
    private var mockTasks: [APITask] = [
        APITask(id: "1", title: "Learn Archery Macros", priority: "high", completed: false),
        APITask(id: "2", title: "Build Demo App", priority: "medium", completed: true),
        APITask(id: "3", title: "Write Documentation", priority: "low", completed: false)
    ]

    func loadTasks() async {
        isLoading = true
        errorMessage = nil

        // Simulate network delay
        try? await Task.sleep(for: .seconds(1))

        // Use mock data (in real app, would use TaskAPIProtocol)
        tasks = mockTasks
        isLoading = false
    }

    func addTask(title: String, priority: String) {
        let newTask = APITask(
            id: UUID().uuidString,
            title: title,
            priority: priority,
            completed: false
        )
        tasks.append(newTask)
        mockTasks.append(newTask)
    }

    func deleteTask(id: String) {
        tasks.removeAll { $0.id == id }
        mockTasks.removeAll { $0.id == id }
    }
}

// This view demonstrates @ViewModelBound pattern
// (simplified version - the macro would generate boilerplate)
struct APIClientDemoView: View {
    @State private var viewModel = APIClientDemoViewModel()
    @State private var showingAddTask = false
    @State private var newTaskTitle = ""
    @State private var newTaskPriority = "medium"

    var body: some View {
        List {
            Section("API Client Demo") {
                Text("This demonstrates @APIClient macro usage")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Tasks") {
                if viewModel.isLoading {
                    HStack {
                        ProgressView()
                        Text("Loading tasks...")
                            .foregroundStyle(.secondary)
                    }
                } else if viewModel.tasks.isEmpty {
                    Text("No tasks yet")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(viewModel.tasks) { task in
                        HStack {
                            Image(systemName: task.completed ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(task.completed ? .green : .secondary)

                            VStack(alignment: .leading) {
                                Text(task.title)
                                Text(task.priority)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .onDelete { indexSet in
                        for index in indexSet {
                            viewModel.deleteTask(id: viewModel.tasks[index].id)
                        }
                    }
                }
            }

            if let error = viewModel.errorMessage {
                Section {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                }
            }
        }
        .navigationTitle("API Client")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingAddTask = true
                } label: {
                    Image(systemName: "plus")
                }
            }

            ToolbarItem(placement: .secondaryAction) {
                Button("Reload") {
                    Task { await viewModel.loadTasks() }
                }
            }
        }
        .task {
            await viewModel.loadTasks()
        }
        .sheet(isPresented: $showingAddTask) {
            NavigationStack {
                Form {
                    TextField("Task Title", text: $newTaskTitle)
                    Picker("Priority", selection: $newTaskPriority) {
                        Text("Low").tag("low")
                        Text("Medium").tag("medium")
                        Text("High").tag("high")
                    }
                }
                .navigationTitle("New Task")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { showingAddTask = false }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Add") {
                            viewModel.addTask(title: newTaskTitle, priority: newTaskPriority)
                            newTaskTitle = ""
                            newTaskPriority = "medium"
                            showingAddTask = false
                        }
                        .disabled(newTaskTitle.isEmpty)
                    }
                }
            }
            .presentationDetents([.medium])
        }
    }
}

// MARK: - Persistence Gateway Demo View

struct PersistenceGatewayDemoView: View {
    @State private var profile = UserProfile(name: "", email: "")
    @State private var settings = AppSettings()
    @State private var lastSync: Date?
    @State private var isSaving = false

    var body: some View {
        Form {
            Section("@PersistenceGateway Demo") {
                Text("This demonstrates typed SQLite persistence")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("User Profile") {
                TextField("Name", text: $profile.name)
                TextField("Email", text: $profile.email)
                    .textContentType(.emailAddress)
                    .autocapitalization(.none)
            }

            Section("Settings") {
                Picker("Theme", selection: $settings.theme) {
                    Text("System").tag("system")
                    Text("Light").tag("light")
                    Text("Dark").tag("dark")
                }
                Toggle("Notifications", isOn: $settings.notificationsEnabled)
            }

            Section("Sync Status") {
                if let lastSync {
                    LabeledContent("Last Sync", value: lastSync.formatted())
                } else {
                    Text("Never synced")
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                Button {
                    simulateSave()
                } label: {
                    HStack {
                        if isSaving {
                            ProgressView()
                        }
                        Text(isSaving ? "Saving..." : "Save to SQLite")
                    }
                }
                .disabled(isSaving)
            }
        }
        .navigationTitle("Persistence")
    }

    private func simulateSave() {
        isSaving = true
        // In a real app:
        // let gateway = try AppStorage.Gateway(url: dbURL)
        // try await gateway.setUserProfile(profile)
        // try await gateway.setSettings(settings)
        // try await gateway.setLastSyncDate(Date())

        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            lastSync = Date()
            isSaving = false
        }
    }
}

// MARK: - Advanced Macros Showcase View

struct AdvancedMacrosShowcaseView: View {
    var body: some View {
        List {
            Section {
                Text("These macros provide advanced functionality for networking, DI, and persistence.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Networking") {
                NavigationLink {
                    APIClientDemoView()
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("@APIClient")
                            .font(.headline)
                        Text("Async networking with retry, caching, and mock generation")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
            }

            Section("Persistence") {
                NavigationLink {
                    PersistenceGatewayDemoView()
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("@PersistenceGateway")
                            .font(.headline)
                        Text("SQLite-backed typed key-value storage")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
            }

            Section("View Binding") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("@ViewModelBound")
                        .font(.headline)
                    Text("DI-aware View binding with automatic ViewModel injection. Generates preview containers and environment setup.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text("Usage:")
                        .font(.caption.bold())
                        .padding(.top, 4)
                    Text("""
                    @ViewModelBound<MyViewModel>
                    struct MyView: View {
                        var body: some View {
                            Text(vm.title)  // vm is auto-injected
                        }
                    }
                    """)
                    .font(.caption.monospaced())
                    .padding(8)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .padding(.vertical, 4)
            }

            Section("App Structure") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("@AppShell")
                        .font(.headline)
                    Text("Generates entire TabView-based navigation shell with state persistence, deep linking, and sheet/fullscreen presentation.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text("Usage:")
                        .font(.caption.bold())
                        .padding(.top, 4)
                    Text("""
                    @AppShell
                    struct MyAppShell {
                        enum Tab: CaseIterable {
                            case home, settings
                        }
                        enum Sheet { case newItem }
                    }
                    // Generates: ShellView, route enums,
                    // navigation state, preview helpers
                    """)
                    .font(.caption.monospaced())
                    .padding(8)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .padding(.vertical, 4)
            }

            Section("Widget/Intent Sharing") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("@SharedModel")
                        .font(.headline)
                    Text("Generates code for sharing data between app, widgets, app intents, and live activities.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text("Usage:")
                        .font(.caption.bold())
                        .padding(.top, 4)
                    Text("""
                    @SharedModel(widget: true, intent: true)
                    struct TaskEntry {
                        var name: String
                        var dueDate: Date
                    }
                    // Generates: TimelineEntry, AppEntity
                    """)
                    .font(.caption.monospaced())
                    .padding(8)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .padding(.vertical, 4)
            }
        }
        .navigationTitle("Advanced Macros")
    }
}

#Preview {
    NavigationStack {
        AdvancedMacrosShowcaseView()
    }
}
