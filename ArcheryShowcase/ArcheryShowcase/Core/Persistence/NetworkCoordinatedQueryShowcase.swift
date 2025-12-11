import Foundation
import SwiftUI
import Archery

// MARK: - Network-Coordinated Query Showcase
//
// This demonstrates the new @Query cache policy feature that enables
// network coordination with local database queries.
//
// Key concepts:
// - @Query with cache policies (staleWhileRevalidate, cacheFirst, networkFirst)
// - QueryRefreshAction for connecting @APIClient to @Query
// - Automatic background refresh when data becomes stale
// - Manual refresh via $query.refresh()

// MARK: - Demo Model

/// A task item persisted in the local database
@Persistable(table: "demo_tasks")
struct DemoTask: Codable, Identifiable, Hashable, Sendable, FetchableRecord, MutablePersistableRecord {
    var id: String
    var title: String
    var isCompleted: Bool
    var priority: Int
    var updatedAt: Date

    mutating func didInsert(_ inserted: InsertionSuccess) {}
}

// MARK: - Simulated API Client

/// Simulates a network API for demo purposes
@APIClient
class DemoTasksAPI {
    func fetchTasks() async throws -> [DemoTask] {
        // Simulate network delay
        try await Task.sleep(for: .seconds(1))

        // Return simulated remote data
        return [
            DemoTask(id: "1", title: "Buy groceries", isCompleted: false, priority: 2, updatedAt: Date()),
            DemoTask(id: "2", title: "Call dentist", isCompleted: true, priority: 1, updatedAt: Date()),
            DemoTask(id: "3", title: "Review PR", isCompleted: false, priority: 3, updatedAt: Date()),
            DemoTask(id: "4", title: "Write tests", isCompleted: false, priority: 2, updatedAt: Date()),
            DemoTask(id: "5", title: "Update docs", isCompleted: true, priority: 1, updatedAt: Date()),
        ]
    }
}

// MARK: - Showcase View

struct NetworkCoordinatedQueryShowcase: View {
    @State private var selectedPolicy: CachePolicyOption = .staleWhileRevalidate

    enum CachePolicyOption: String, CaseIterable {
        case localOnly = "Local Only"
        case staleWhileRevalidate = "Stale-While-Revalidate"
        case cacheFirst = "Cache First"
        case networkFirst = "Network First"

        var description: String {
            switch self {
            case .localOnly:
                return "No network refresh, local database only"
            case .staleWhileRevalidate:
                return "Show cached data immediately, refresh in background"
            case .cacheFirst:
                return "Use cache if fresh (within TTL), else wait for network"
            case .networkFirst:
                return "Always try network first, cache as fallback"
            }
        }
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Network-coordinated queries combine the reactivity of @Query with automatic network refresh based on configurable cache policies.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    HStack {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .foregroundStyle(.blue)
                        Text("Stale-while-revalidate: Fast initial load + background refresh")
                            .font(.caption)
                    }

                    HStack {
                        Image(systemName: "clock.arrow.circlepath")
                            .foregroundStyle(.orange)
                        Text("Cache-first: Use fresh cache, fetch only when expired")
                            .font(.caption)
                    }

                    HStack {
                        Image(systemName: "wifi")
                            .foregroundStyle(.green)
                        Text("Network-first: Always fetch, cache as offline fallback")
                            .font(.caption)
                    }
                }
            }

            Section("Cache Policy Types") {
                ForEach(CachePolicyOption.allCases, id: \.self) { option in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Image(systemName: option == selectedPolicy ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(option == selectedPolicy ? .blue : .secondary)
                            Text(option.rawValue)
                                .font(.subheadline.weight(.medium))
                        }
                        Text(option.description)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        selectedPolicy = option
                    }
                }
            }

            Section("API Pattern") {
                VStack(alignment: .leading, spacing: 4) {
                    Text("// 1. Define @Query with cache policy")
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)

                    Group {
                        Text("@Query(")
                        Text("    DemoTask.all(),")
                        Text("    cachePolicy: .staleWhileRevalidate(staleAfter: .minutes(5)),")
                        Text("    refresh: .fromAPI { try await api.fetchTasks() }")
                        Text(")")
                        Text("var tasks: [DemoTask]")
                    }
                    .font(.caption.monospaced())
                    .foregroundStyle(.blue)

                    Text("")

                    Text("// 2. Access state via projection")
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)

                    Group {
                        Text("$tasks.isStale      // Bool")
                        Text("$tasks.isRefreshing // Bool")
                        Text("$tasks.lastSyncedAt // Date?")
                    }
                    .font(.caption.monospaced())

                    Text("")

                    Text("// 3. Manual refresh")
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)

                    Group {
                        Text(".refreshable {")
                        Text("    await $tasks.refresh()")
                        Text("}")
                    }
                    .font(.caption.monospaced())
                    .foregroundStyle(.blue)
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            Section("QueryRefreshBuilder Options") {
                ForEach([
                    (".fromAPI { ... }", "Simple fetch closure"),
                    (".using(client) { ... }", "With API client instance"),
                    ("QueryMergeStrategy.replace", "Delete all, insert fresh"),
                    ("QueryMergeStrategy.upsert", "Insert or update by ID"),
                    ("QueryMergeStrategy.appendNew", "Only insert new records"),
                ], id: \.0) { code, desc in
                    LabeledContent {
                        Text(desc)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } label: {
                        Text(code)
                            .font(.caption.monospaced())
                    }
                }
            }

            Section("Projection Properties") {
                ForEach([
                    ("$query.isStale", "Whether data exceeds staleness threshold"),
                    ("$query.isRefreshing", "Network refresh in progress"),
                    ("$query.lastSyncedAt", "Timestamp of last successful sync"),
                    ("$query.refreshError", "Error from last refresh attempt"),
                    ("$query.refresh()", "Trigger manual refresh"),
                    ("$query.forceRefresh()", "Force refresh regardless of staleness"),
                    ("$query.refreshLocal()", "Restart DB observation only"),
                ], id: \.0) { prop, desc in
                    LabeledContent {
                        Text(desc)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } label: {
                        Text(prop)
                            .font(.caption.monospaced())
                    }
                }
            }

            Section("Setup Requirements") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("1. Create coordinator in your App:")
                        .font(.caption.weight(.medium))

                    Group {
                        Text("let coordinator = QueryNetworkCoordinator(")
                        Text("    container: persistenceContainer")
                        Text(")")
                    }
                    .font(.caption.monospaced())
                    .foregroundStyle(.blue)

                    Text("")

                    Text("2. Inject into environment:")
                        .font(.caption.weight(.medium))

                    Group {
                        Text("ContentView()")
                        Text("    .databaseContainer(container)")
                        Text("    .queryNetworkCoordinator(coordinator)")
                    }
                    .font(.caption.monospaced())
                    .foregroundStyle(.blue)

                    Text("")

                    Text("Or use the convenience modifier:")
                        .font(.caption.weight(.medium))

                    Group {
                        Text("ContentView()")
                        Text("    .enableQueryCoordination(container: container)")
                    }
                    .font(.caption.monospaced())
                    .foregroundStyle(.blue)
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            Section("Migration from @Repository") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Before (deprecated):")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.orange)

                    Group {
                        Text("@Repository")
                        Text("class TaskRepository {")
                        Text("    func fetchTasks() async throws -> [Task] {")
                        Text("        try await apiClient.fetchTasks()")
                        Text("    }")
                        Text("}")
                    }
                    .font(.caption.monospaced())
                    .strikethrough()
                    .foregroundStyle(.secondary)

                    Text("")

                    Text("After (recommended):")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.green)

                    Group {
                        Text("@APIClient")
                        Text("class TasksAPI {")
                        Text("    func fetchTasks() async throws -> [Task] { ... }")
                        Text("}")
                        Text("")
                        Text("@Query(")
                        Text("    Task.all(),")
                        Text("    cachePolicy: .staleWhileRevalidate(...),")
                        Text("    refresh: .fromAPI { try await api.fetchTasks() }")
                        Text(")")
                        Text("var tasks: [Task]")
                    }
                    .font(.caption.monospaced())
                    .foregroundStyle(.blue)
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            // MARK: - QuerySources Pattern

            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Reusable Query Sources", systemImage: "arrow.triangle.branch")
                        .font(.headline)

                    Text("Define query sources once, use via keypath in any view. Perfect for queries shared across multiple views.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("1. Define Query Sources (Nested in Model)") {
                VStack(alignment: .leading, spacing: 4) {
                    Text("// Sources nested in model type for clean keypaths")
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)

                    Group {
                        Text("extension Task: HasQuerySources {")
                        Text("    @QuerySources")
                        Text("    struct Sources {")
                        Text("        let api: TasksAPIProtocol")
                        Text("")
                        Text("        var all: QuerySource<Task> {")
                        Text("            QuerySource(Task.all().order(by: .createdAt))")
                        Text("                .remote { try await api.fetchAll() }")
                        Text("                .staleWhileRevalidate(after: .minutes(5))")
                        Text("        }")
                        Text("")
                        Text("        var completed: QuerySource<Task> {")
                        Text("            QuerySource(Task.all().filter(Task.Columns.isCompleted == true))")
                        Text("                .remote { try await api.fetchCompleted() }")
                        Text("                .cacheFirst(ttl: .hours(1))")
                        Text("        }")
                        Text("")
                        Text("        // Parameterized query")
                        Text("        var byPriority: (Int) -> QuerySource<Task> {")
                        Text("            { priority in")
                        Text("                QuerySource(Task.all().filter(Task.Columns.priority == priority))")
                        Text("                    .remote { [api] in try await api.fetchByPriority(priority) }")
                        Text("            }")
                        Text("        }")
                        Text("    }")
                        Text("}")
                    }
                    .font(.caption.monospaced())
                    .foregroundStyle(.blue)
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            Section("2. Inject at App Root") {
                VStack(alignment: .leading, spacing: 4) {
                    Group {
                        Text("ContentView()")
                        Text("    .databaseContainer(database)")
                        Text("    .enableQueryCoordination(container: database)")
                        Text("    // Inject each model's sources")
                        Text("    .querySources(Task.Sources(api: TasksAPI.live()))")
                        Text("    .querySources(User.Sources(api: UsersAPI.live()))")
                    }
                    .font(.caption.monospaced())
                    .foregroundStyle(.blue)
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            Section("3. Use via Keypath") {
                VStack(alignment: .leading, spacing: 4) {
                    Text("// Shorthand syntax - root inferred from [Task]")
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)

                    Group {
                        Text("struct TaskListView: View {")
                        Text("    @Query(\\.all)")
                        Text("    var tasks: [Task]")
                        Text("")
                        Text("    @Query(\\.completed)")
                        Text("    var completed: [Task]")
                        Text("")
                        Text("    // Parameterized query")
                        Text("    @Query(\\.byPriority, param: 1)")
                        Text("    var highPriority: [Task]")
                        Text("")
                        Text("    var body: some View {")
                        Text("        List(tasks) { TaskRow(task: $0) }")
                        Text("            .refreshable { await $tasks.refresh() }")
                        Text("    }")
                        Text("}")
                    }
                    .font(.caption.monospaced())
                    .foregroundStyle(.blue)
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            Section("Benefits of QuerySources") {
                ForEach([
                    ("Modular", "Each model/domain defines its own sources"),
                    ("Reusable", "Same query definition used across views"),
                    ("DI-Friendly", "Inject APIs per domain, easy to mock"),
                    ("Type-Safe", "Full compile-time checking with keypaths"),
                    ("Co-located", "Query sources live near the models they query"),
                ], id: \.0) { title, desc in
                    LabeledContent {
                        Text(desc)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } label: {
                        Label(title, systemImage: "checkmark.circle.fill")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.green)
                    }
                }
            }

            Section("Testing with QuerySources") {
                VStack(alignment: .leading, spacing: 4) {
                    Group {
                        Text("func testTaskListView() {")
                        Text("    let mockAPI = MockTasksAPI()")
                        Text("    mockAPI.tasksToReturn = [Task.sample]")
                        Text("")
                        Text("    let view = TaskListView()")
                        Text("        .querySources(Task.Sources(api: mockAPI))")
                        Text("        .databaseContainer(try! .inMemory())")
                        Text("}")
                    }
                    .font(.caption.monospaced())
                    .foregroundStyle(.blue)
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
        .navigationTitle("Network Queries")
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        NetworkCoordinatedQueryShowcase()
    }
}
