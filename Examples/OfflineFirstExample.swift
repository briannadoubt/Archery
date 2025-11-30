import SwiftUI
import Archery

struct OfflineFirstApp: App {
    @StateObject private var connectivity = ConnectivityMonitor.shared
    @StateObject private var mutationQueue = MutationQueue()
    @StateObject private var syncCoordinator: SyncCoordinator
    
    init() {
        let queue = MutationQueue()
        let coordinator = SyncCoordinator(mutationQueue: queue)
        _mutationQueue = StateObject(wrappedValue: queue)
        _syncCoordinator = StateObject(wrappedValue: coordinator)
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(connectivity)
                .environmentObject(mutationQueue)
                .environmentObject(syncCoordinator)
                .offlineCapable()
        }
    }
}

struct ContentView: View {
    @EnvironmentObject private var connectivity: ConnectivityMonitor
    @EnvironmentObject private var syncCoordinator: SyncCoordinator
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if !connectivity.isConnected {
                    OfflineIndicator()
                }
                
                TabView {
                    TodoListView()
                        .tabItem {
                            Label("Todos", systemImage: "checklist")
                        }
                    
                    NotesView()
                        .tabItem {
                            Label("Notes", systemImage: "note.text")
                        }
                    
                    SyncDashboardView()
                        .tabItem {
                            Label("Sync", systemImage: "arrow.triangle.2.circlepath")
                        }
                    
                    DiagnosticsView()
                        .tabItem {
                            Label("Diagnostics", systemImage: "chart.line.uptrend.xyaxis")
                        }
                }
            }
            .navigationTitle("Offline First Demo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    ConnectivityView()
                }
                
                ToolbarItem(placement: .navigationBarLeading) {
                    SyncStatusBadge()
                }
            }
        }
    }
}

struct SyncStatusBadge: View {
    @EnvironmentObject private var syncCoordinator: SyncCoordinator
    
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: iconName)
                .foregroundColor(iconColor)
                .font(.caption)
            
            if syncCoordinator.pendingChanges > 0 {
                Text("\(syncCoordinator.pendingChanges)")
                    .font(.caption2)
                    .foregroundColor(.white)
                    .padding(.horizontal, 4)
                    .background(Color.orange)
                    .clipShape(Capsule())
            }
        }
    }
    
    private var iconName: String {
        switch syncCoordinator.syncState {
        case .syncing:
            return "arrow.triangle.2.circlepath"
        case .offline:
            return "wifi.slash"
        case .failed:
            return "exclamationmark.triangle"
        default:
            return syncCoordinator.pendingChanges > 0 ? "clock" : "checkmark.circle"
        }
    }
    
    private var iconColor: Color {
        switch syncCoordinator.syncState {
        case .syncing:
            return .blue
        case .offline:
            return .gray
        case .failed:
            return .red
        default:
            return syncCoordinator.pendingChanges > 0 ? .orange : .green
        }
    }
}

struct TodoItem: Cacheable, Identifiable {
    struct Key: CacheKey {
        let identifier: String
    }
    
    let id = UUID().uuidString
    var key: Key { Key(identifier: id) }
    let title: String
    var isCompleted: Bool
    let lastModified: Date
    let version: Int
    
    init(title: String, isCompleted: Bool = false) {
        self.title = title
        self.isCompleted = isCompleted
        self.lastModified = Date()
        self.version = 1
    }
}

struct CreateTodoMutation: Mutation {
    let id = UUID().uuidString
    let timestamp = Date()
    var retryCount = 0
    let maxRetries = 3
    let todo: TodoItem
    
    func execute() async throws -> MutationResult {
        try await Task.sleep(nanoseconds: 500_000_000)
        return .success(todo)
    }
    
    func canRetry() -> Bool {
        retryCount < maxRetries
    }
}

struct UpdateTodoMutation: Mutation {
    let id: String
    let timestamp = Date()
    var retryCount = 0
    let maxRetries = 3
    let todoId: String
    let isCompleted: Bool
    
    func execute() async throws -> MutationResult {
        try await Task.sleep(nanoseconds: 500_000_000)
        return .success(nil)
    }
    
    func canRetry() -> Bool {
        retryCount < maxRetries
    }
}

@MainActor
class TodoViewModel: ObservableObject {
    @Published var todos: [TodoItem] = []
    private let cache = OfflineCache<TodoItem>(name: "todos")
    private let mutationQueue: MutationQueue
    
    init(mutationQueue: MutationQueue) {
        self.mutationQueue = mutationQueue
        
        mutationQueue.registerHandler(for: CreateTodoMutation.self) { mutation in
            return .success(mutation.todo)
        }
        
        mutationQueue.registerHandler(for: UpdateTodoMutation.self) { mutation in
            return .success(nil)
        }
        
        Task {
            await loadTodos()
        }
    }
    
    func loadTodos() async {
        todos = await cache.getAll()
    }
    
    func addTodo(_ title: String) async {
        let todo = TodoItem(title: title)
        await cache.set(todo)
        todos.append(todo)
        
        let mutation = CreateTodoMutation(todo: todo)
        await mutationQueue.enqueue(mutation)
    }
    
    func toggleTodo(_ todo: TodoItem) async {
        var updatedTodo = todo
        updatedTodo.isCompleted.toggle()
        await cache.set(updatedTodo)
        
        if let index = todos.firstIndex(where: { $0.id == todo.id }) {
            todos[index] = updatedTodo
        }
        
        let mutation = UpdateTodoMutation(
            id: UUID().uuidString,
            todoId: todo.id,
            isCompleted: updatedTodo.isCompleted
        )
        await mutationQueue.enqueue(mutation)
    }
}

struct TodoListView: View {
    @StateObject private var viewModel: TodoViewModel
    @EnvironmentObject private var mutationQueue: MutationQueue
    @State private var newTodoTitle = ""
    @State private var showingAddSheet = false
    
    init() {
        _viewModel = StateObject(wrappedValue: TodoViewModel(mutationQueue: MutationQueue()))
    }
    
    var body: some View {
        NavigationStack {
            List {
                ForEach(viewModel.todos) { todo in
                    TodoRow(todo: todo, viewModel: viewModel)
                }
                
                if viewModel.todos.isEmpty {
                    ContentUnavailableView(
                        "No Todos",
                        systemImage: "checklist",
                        description: Text("Add your first todo to get started")
                    )
                }
            }
            .navigationTitle("Todos")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button(action: { showingAddSheet = true }) {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingAddSheet) {
                AddTodoSheet(viewModel: viewModel, isPresented: $showingAddSheet)
            }
            .refreshable {
                await viewModel.loadTodos()
            }
        }
    }
}

struct TodoRow: View {
    let todo: TodoItem
    let viewModel: TodoViewModel
    
    var body: some View {
        HStack {
            Button(action: {
                Task {
                    await viewModel.toggleTodo(todo)
                }
            }) {
                Image(systemName: todo.isCompleted ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(todo.isCompleted ? .green : .gray)
            }
            .buttonStyle(.plain)
            
            Text(todo.title)
                .strikethrough(todo.isCompleted)
                .foregroundColor(todo.isCompleted ? .secondary : .primary)
            
            Spacer()
            
            Text(todo.lastModified, style: .relative)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
    }
}

struct AddTodoSheet: View {
    let viewModel: TodoViewModel
    @Binding var isPresented: Bool
    @State private var title = ""
    @FocusState private var isFocused: Bool
    
    var body: some View {
        NavigationStack {
            Form {
                TextField("Todo title", text: $title)
                    .focused($isFocused)
            }
            .navigationTitle("New Todo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        isPresented = false
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        Task {
                            await viewModel.addTodo(title)
                            isPresented = false
                        }
                    }
                    .disabled(title.isEmpty)
                }
            }
        }
        .onAppear {
            isFocused = true
        }
    }
}

struct NotesView: View {
    @State private var notes: [String] = []
    @EnvironmentObject private var connectivity: ConnectivityMonitor
    
    var body: some View {
        NavigationStack {
            List {
                ForEach(notes, id: \.self) { note in
                    Text(note)
                }
                
                if notes.isEmpty {
                    ContentUnavailableView(
                        "No Notes",
                        systemImage: "note.text",
                        description: Text("Your notes will appear here")
                    )
                }
            }
            .navigationTitle("Notes")
            .offlineCapable(
                showIndicator: true,
                customMessage: "Notes sync when online"
            )
        }
    }
}

struct SyncDashboardView: View {
    @EnvironmentObject private var syncCoordinator: SyncCoordinator
    @EnvironmentObject private var mutationQueue: MutationQueue
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    SyncStatusView(coordinator: syncCoordinator)
                    
                    MutationQueueView(queue: mutationQueue)
                    
                    SyncDiagnosticsView(coordinator: syncCoordinator)
                    
                    syncActions
                }
                .padding()
            }
            .navigationTitle("Sync Dashboard")
        }
    }
    
    private var syncActions: some View {
        VStack(spacing: 12) {
            Button(action: {
                Task {
                    await syncCoordinator.forceSync()
                }
            }) {
                Label("Force Sync", systemImage: "arrow.clockwise")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(syncCoordinator.syncState == .syncing || syncCoordinator.syncState == .offline)
            
            if !mutationQueue.failedMutations.isEmpty {
                Button(action: {
                    Task {
                        await mutationQueue.retryAll()
                    }
                }) {
                    Label("Retry All Failed", systemImage: "arrow.uturn.backward")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .foregroundColor(.orange)
            }
            
            if !mutationQueue.failedMutations.isEmpty {
                Button(action: {
                    Task {
                        await mutationQueue.clearFailed()
                    }
                }) {
                    Label("Clear Failed", systemImage: "trash")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .foregroundColor(.red)
            }
        }
    }
}

struct DiagnosticsView: View {
    @EnvironmentObject private var connectivity: ConnectivityMonitor
    @EnvironmentObject private var syncCoordinator: SyncCoordinator
    
    var body: some View {
        NavigationStack {
            List {
                connectivitySection
                syncMetricsSection
                historySection
            }
            .navigationTitle("Diagnostics")
        }
    }
    
    private var connectivitySection: some View {
        Section("Connectivity") {
            LabeledContent("Status", value: connectivity.isConnected ? "Connected" : "Offline")
            LabeledContent("Type", value: connectivity.connectionType.rawValue)
            LabeledContent("Quality", value: connectivity.connectionQuality.rawValue)
            
            if connectivity.isExpensive {
                Label("Expensive Connection", systemImage: "dollarsign.circle")
                    .foregroundColor(.orange)
            }
            
            if connectivity.isConstrained {
                Label("Low Data Mode", systemImage: "exclamationmark.triangle")
                    .foregroundColor(.yellow)
            }
            
            let uptime = connectivity.getAverageUptime(over: 3600)
            LabeledContent("Uptime (1h)", value: "\(Int(uptime * 100))%")
        }
    }
    
    private var syncMetricsSection: some View {
        Section("Sync Metrics") {
            LabeledContent("Total Syncs", value: "\(syncCoordinator.metrics.syncAttempts)")
            LabeledContent("Successful", value: "\(syncCoordinator.metrics.successfulSyncs)")
            LabeledContent("Failed", value: "\(syncCoordinator.metrics.failedSyncs)")
            LabeledContent("Success Rate", value: "\(Int(syncCoordinator.metrics.successRate * 100))%")
            LabeledContent("Avg Duration", value: String(format: "%.2fs", syncCoordinator.metrics.averageSyncTime))
            LabeledContent("Conflicts Resolved", value: "\(syncCoordinator.metrics.conflictsResolved)")
            
            if let lastSync = syncCoordinator.lastSyncTime {
                LabeledContent("Last Sync") {
                    Text(lastSync, style: .relative)
                }
            }
        }
    }
    
    private var historySection: some View {
        Section("Connection History") {
            ForEach(connectivity.getConnectionHistory().suffix(10), id: \.timestamp) { event in
                HStack {
                    Image(systemName: event.isConnected ? "wifi" : "wifi.slash")
                        .foregroundColor(event.isConnected ? .green : .red)
                    
                    VStack(alignment: .leading) {
                        Text(event.type.rawValue)
                            .font(.caption)
                        Text(event.timestamp, style: .relative)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    Text(event.quality.rawValue)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
    }
}