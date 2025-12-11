import Foundation
import SwiftUI
import Archery

// MARK: - @APIClient Showcase
//
// Demonstrates real networking with JSONPlaceholder API:
// - Actual HTTP requests
// - Retry and cache policies
// - Loading states and error handling
// - Generated protocol, live impl, and mock

// MARK: - JSONPlaceholder API Client

/// Uses JSONPlaceholder for real API calls.
/// The @APIClient macro generates:
/// - `JSONPlaceholderAPIProtocol` - protocol for DI
/// - `JSONPlaceholderAPILive` - implementation with retry/cache
/// - `MockJSONPlaceholderAPI` - test mock
@APIClient
class JSONPlaceholderAPI {
    private let baseURL = "https://jsonplaceholder.typicode.com"

    /// Fetch all todos
    func fetchTodos() async throws -> [JSONTodo] {
        let url = URL(string: "\(baseURL)/todos")!
        let (data, _) = try await URLSession.shared.data(from: url)
        return try JSONDecoder().decode([JSONTodo].self, from: data)
    }

    /// Fetch a single todo by ID
    func fetchTodo(id: Int) async throws -> JSONTodo {
        let url = URL(string: "\(baseURL)/todos/\(id)")!
        let (data, _) = try await URLSession.shared.data(from: url)
        return try JSONDecoder().decode(JSONTodo.self, from: data)
    }

    /// Fetch all users
    func fetchUsers() async throws -> [JSONUser] {
        let url = URL(string: "\(baseURL)/users")!
        let (data, _) = try await URLSession.shared.data(from: url)
        return try JSONDecoder().decode([JSONUser].self, from: data)
    }

    /// Fetch posts by user ID
    func fetchPosts(userId: Int) async throws -> [JSONPost] {
        let url = URL(string: "\(baseURL)/posts?userId=\(userId)")!
        let (data, _) = try await URLSession.shared.data(from: url)
        return try JSONDecoder().decode([JSONPost].self, from: data)
    }

    /// Create a new todo (simulated - JSONPlaceholder returns fake response)
    func createTodo(title: String, userId: Int) async throws -> JSONTodo {
        var request = URLRequest(url: URL(string: "\(baseURL)/todos")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body = ["title": title, "userId": userId, "completed": false] as [String: Any]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, _) = try await URLSession.shared.data(for: request)
        return try JSONDecoder().decode(JSONTodo.self, from: data)
    }
}

// MARK: - API Models

struct JSONTodo: Codable, Identifiable, Sendable {
    let userId: Int
    let id: Int
    var title: String
    var completed: Bool
}

struct JSONUser: Codable, Identifiable, Sendable {
    let id: Int
    let name: String
    let username: String
    let email: String
    let phone: String
    let website: String
}

struct JSONPost: Codable, Identifiable, Sendable {
    let userId: Int
    let id: Int
    let title: String
    let body: String
}

// MARK: - Networking Showcase View

struct NetworkingShowcaseView: View {
    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("@APIClient Macro")
                        .font(.headline)
                    Text("Generates protocol, live implementation with retry/cache, and mock for testing. Uses real JSONPlaceholder API.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Demos") {
                NavigationLink {
                    TodosAPIDemo()
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Todos API")
                            .font(.headline)
                        Text("Fetch, display, and create todos")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }

                NavigationLink {
                    UsersAPIDemo()
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Users API")
                            .font(.headline)
                        Text("Fetch user profiles")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
            }

            Section("Generated Code") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("@APIClient generates:")
                        .font(.caption.bold())

                    Group {
                        CodeSnippet("• JSONPlaceholderAPIProtocol")
                        CodeSnippet("• JSONPlaceholderAPILive (with retry)")
                        CodeSnippet("• MockJSONPlaceholderAPI")
                        CodeSnippet("• .live() factory method")
                        CodeSnippet("• .make(in:) for DI")
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .navigationTitle("@APIClient")
    }
}

private struct CodeSnippet: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.caption.monospaced())
            .foregroundStyle(.secondary)
    }
}

// MARK: - Todos API Demo

struct TodosAPIDemo: View {
    @State private var todos: [JSONTodo] = []
    @State private var isLoading = false
    @State private var error: Error?
    @State private var newTodoTitle = ""
    @State private var showingCreateSheet = false

    // Use the raw API directly for demo (in production, use DI)
    private let api = JSONPlaceholderAPI()

    var body: some View {
        List {
            Section {
                HStack {
                    Text("Status:")
                    Spacer()
                    if isLoading {
                        ProgressView()
                    } else if let error {
                        Label(error.localizedDescription, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.red)
                            .font(.caption)
                    } else {
                        Text("\(todos.count) todos loaded")
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if !todos.isEmpty {
                Section("Todos (first 10)") {
                    ForEach(todos.prefix(10)) { todo in
                        HStack {
                            Image(systemName: todo.completed ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(todo.completed ? .green : .secondary)
                            Text(todo.title)
                                .lineLimit(1)
                        }
                    }
                }
            }
        }
        .navigationTitle("Todos API")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingCreateSheet = true
                } label: {
                    Image(systemName: "plus")
                }
            }

            ToolbarItem(placement: .secondaryAction) {
                Button("Refresh") {
                    Task { await loadTodos() }
                }
            }
        }
        .task {
            await loadTodos()
        }
        .sheet(isPresented: $showingCreateSheet) {
            CreateTodoSheet(api: api, onCreated: { todo in
                todos.insert(todo, at: 0)
            })
        }
    }

    private func loadTodos() async {
        isLoading = true
        error = nil

        do {
            todos = try await api.fetchTodos()
        } catch {
            self.error = error
        }

        isLoading = false
    }
}

struct CreateTodoSheet: View {
    let api: JSONPlaceholderAPI
    let onCreated: (JSONTodo) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var isCreating = false
    @State private var error: Error?

    var body: some View {
        NavigationStack {
            Form {
                Section("New Todo") {
                    TextField("Title", text: $title)
                }

                if let error {
                    Section {
                        Label(error.localizedDescription, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.red)
                    }
                }

                Section {
                    Text("Note: JSONPlaceholder simulates creation but doesn't persist data")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Create Todo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        Task { await createTodo() }
                    }
                    .disabled(title.isEmpty || isCreating)
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func createTodo() async {
        isCreating = true
        error = nil

        do {
            let todo = try await api.createTodo(title: title, userId: 1)
            onCreated(todo)
            dismiss()
        } catch {
            self.error = error
        }

        isCreating = false
    }
}

// MARK: - Users API Demo

struct UsersAPIDemo: View {
    @State private var users: [JSONUser] = []
    @State private var selectedUser: JSONUser?
    @State private var posts: [JSONPost] = []
    @State private var isLoading = false
    @State private var error: Error?

    private let api = JSONPlaceholderAPI()

    var body: some View {
        List {
            Section {
                HStack {
                    Text("Status:")
                    Spacer()
                    if isLoading {
                        ProgressView()
                    } else if let error {
                        Label(error.localizedDescription, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.red)
                            .font(.caption)
                    } else {
                        Text("\(users.count) users loaded")
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if !users.isEmpty {
                Section("Users") {
                    ForEach(users) { user in
                        Button {
                            selectedUser = user
                            Task { await loadPosts(for: user) }
                        } label: {
                            HStack {
                                Image(systemName: "person.circle.fill")
                                    .font(.title2)
                                    .foregroundStyle(.tint)

                                VStack(alignment: .leading) {
                                    Text(user.name)
                                        .font(.headline)
                                    Text(user.email)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()

                                if selectedUser?.id == user.id {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(.tint)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            if let user = selectedUser, !posts.isEmpty {
                Section("Posts by \(user.name)") {
                    ForEach(posts) { post in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(post.title)
                                .font(.subheadline.bold())
                            Text(post.body)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }
        .navigationTitle("Users API")
        .task {
            await loadUsers()
        }
    }

    private func loadUsers() async {
        isLoading = true
        error = nil

        do {
            users = try await api.fetchUsers()
        } catch {
            self.error = error
        }

        isLoading = false
    }

    private func loadPosts(for user: JSONUser) async {
        do {
            posts = try await api.fetchPosts(userId: user.id)
        } catch {
            self.error = error
        }
    }
}

#Preview {
    NavigationStack {
        NetworkingShowcaseView()
    }
}
