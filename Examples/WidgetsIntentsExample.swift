import SwiftUI
import WidgetKit
import BackgroundTasks

#if canImport(AppIntents)
import AppIntents
#endif

// MARK: - Main App

@main
struct WidgetsIntentsExampleApp: App {
    
    @StateObject private var container = EnvContainer()
    
    init() {
        setupDependencies()
        setupBackgroundTasks()
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(container)
                .onAppear {
                    trackAppUsage()
                }
        }
    }
    
    private func setupDependencies() {
        // Register repositories and services
        container.register(TaskRepository.self) { TaskRepository() }
        container.register(UserRepository.self) { UserRepository() }
        
        // Set as shared container
        EnvContainer.shared = container
    }
    
    private func setupBackgroundTasks() {
        #if canImport(BackgroundTasks) && !targetEnvironment(simulator)
        BackgroundTaskCoordinator.shared.configure()
        BackgroundTaskCoordinator.shared.scheduleInitialTasks()
        #endif
    }
    
    private func trackAppUsage() {
        let defaults = UserDefaults(suiteName: "group.archery.widgets")
        defaults?.set(Date(), forKey: "last_app_open")
        
        // Update user active hours pattern
        let currentHour = Calendar.current.component(.hour, from: Date())
        var activeHours = defaults?.array(forKey: "user_active_hours") as? [Int] ?? []
        
        if !activeHours.contains(currentHour) {
            activeHours.append(currentHour)
            activeHours = Array(Set(activeHours)).sorted() // Remove duplicates
            defaults?.set(activeHours, forKey: "user_active_hours")
        }
    }
}

// MARK: - Content View

struct ContentView: View {
    @EnvironmentObject var container: EnvContainer
    @StateObject private var taskStore = TaskStore()
    
    var body: some View {
        TabView {
            TaskListView()
                .environmentObject(taskStore)
                .tabItem {
                    Label("Tasks", systemImage: "list.bullet")
                }
            
            WidgetDemoView()
                .tabItem {
                    Label("Widgets", systemImage: "rectangle.stack")
                }
            
            IntentsDemoView()
                .tabItem {
                    Label("Intents", systemImage: "command")
                }
            
            BackgroundTaskView()
                .tabItem {
                    Label("Background", systemImage: "gear")
                }
        }
        .onAppear {
            container.register(TaskStore.self) { taskStore }
        }
    }
}

// MARK: - Task List View

struct TaskListView: View {
    @EnvironmentObject var taskStore: TaskStore
    @State private var showingAddTask = false
    
    var body: some View {
        NavigationView {
            List {
                ForEach(taskStore.tasks) { task in
                    TaskRowView(task: task)
                        .onTapGesture {
                            taskStore.toggleTask(task)
                        }
                }
                .onDelete(perform: taskStore.deleteTasks)
            }
            .navigationTitle("Tasks")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Add") {
                        showingAddTask = true
                    }
                }
            }
            .sheet(isPresented: $showingAddTask) {
                AddTaskView()
                    .environmentObject(taskStore)
            }
        }
    }
}

struct TaskRowView: View {
    let task: Task
    
    var body: some View {
        HStack {
            Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                .foregroundColor(task.isCompleted ? .green : .gray)
            
            VStack(alignment: .leading) {
                Text(task.title)
                    .strikethrough(task.isCompleted)
                
                if !task.notes.isEmpty {
                    Text(task.notes)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Text(task.createdAt, style: .date)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            if task.priority == .high {
                Image(systemName: "exclamationmark.circle.fill")
                    .foregroundColor(.red)
            }
        }
        .padding(.vertical, 2)
    }
}

struct AddTaskView: View {
    @EnvironmentObject var taskStore: TaskStore
    @Environment(\.dismiss) var dismiss
    
    @State private var title = ""
    @State private var notes = ""
    @State private var priority = TaskPriority.medium
    
    var body: some View {
        NavigationView {
            Form {
                Section {
                    TextField("Task title", text: $title)
                    TextField("Notes (optional)", text: $notes, axis: .vertical)
                        .lineLimit(3...6)
                }
                
                Section {
                    Picker("Priority", selection: $priority) {
                        ForEach(TaskPriority.allCases, id: \.self) { priority in
                            Text(priority.displayName).tag(priority)
                        }
                    }
                    .pickerStyle(SegmentedPickerStyle())
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
                    Button("Add") {
                        let task = Task(
                            title: title,
                            notes: notes,
                            priority: priority
                        )
                        taskStore.addTask(task)
                        dismiss()
                    }
                    .disabled(title.isEmpty)
                }
            }
        }
    }
}

// MARK: - Widget Demo View

struct WidgetDemoView: View {
    @State private var widgetStatus: [BackgroundTaskStatus] = []
    @State private var isLoading = false
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                // Widget Management Section
                Section {
                    Text("Widget Management")
                        .font(.headline)
                    
                    VStack(spacing: 10) {
                        Button("Reload All Widgets") {
                            WidgetTimelineManager.shared.reloadAll()
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                        
                        Button("Reload Task Widget Only") {
                            WidgetTimelineManager.shared.reload(kind: "com.archery.task-widget")
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.green)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                    }
                }
                .padding()
                
                // Widget Analytics Section
                Section {
                    Text("Widget Analytics")
                        .font(.headline)
                    
                    VStack(spacing: 10) {
                        Button("Track Widget View") {
                            WidgetAnalytics.shared.trackWidgetView(
                                kind: "task-widget",
                                family: .systemMedium,
                                hasData: true
                            )
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.purple)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                        
                        Button("Track Widget Tap") {
                            WidgetAnalytics.shared.trackWidgetTap(
                                kind: "task-widget",
                                family: .systemMedium,
                                action: "open_task"
                            )
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.orange)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                    }
                }
                .padding()
                
                // Current Widgets Section
                Section {
                    Text("Current Widget Configurations")
                        .font(.headline)
                    
                    if isLoading {
                        ProgressView()
                    } else if widgetStatus.isEmpty {
                        Text("No widgets configured")
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(widgetStatus.indices, id: \.self) { index in
                            let status = widgetStatus[index]
                            VStack(alignment: .leading) {
                                Text(status.identifier)
                                    .font(.subheadline)
                                Text("Family: \(status.family.rawValue)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .padding(8)
                            .background(Color.gray.opacity(0.1))
                            .cornerRadius(8)
                        }
                    }
                    
                    Button("Refresh Widget Status") {
                        Task {
                            isLoading = true
                            widgetStatus = await WidgetTimelineManager.shared.getCurrentConfigurations()
                            isLoading = false
                        }
                    }
                    .padding()
                }
                .padding()
                
                Spacer()
            }
            .navigationTitle("Widget Demo")
        }
    }
}

// MARK: - Intents Demo View

struct IntentsDemoView: View {
    @State private var intentResults: [String] = []
    @EnvironmentObject var taskStore: TaskStore
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                // App Intents Section
                Section {
                    Text("App Intents Demo")
                        .font(.headline)
                    
                    VStack(spacing: 10) {
                        Button("Test Add Task Intent") {
                            testAddTaskIntent()
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                        
                        Button("Test Complete Task Intent") {
                            testCompleteTaskIntent()
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.green)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                        
                        Button("Test Get Tasks Intent") {
                            testGetTasksIntent()
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.purple)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                    }
                }
                .padding()
                
                #if canImport(AppIntents)
                // Siri Integration Section
                Section {
                    Text("Siri Integration")
                        .font(.headline)
                    
                    VStack(spacing: 10) {
                        Button("Add Quick Task to Siri") {
                            // Show how to add intent to Siri shortcuts
                            intentResults.append("Quick Task intent added to Siri suggestions")
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.orange)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                        
                        if #available(iOS 17.0, *) {
                            // Siri Tip would go here in real implementation
                            Text("Siri Tips would appear here in iOS 17+")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .padding()
                                .background(Color.gray.opacity(0.1))
                                .cornerRadius(8)
                        }
                    }
                }
                .padding()
                #endif
                
                // Intent Results Section
                Section {
                    Text("Intent Results")
                        .font(.headline)
                    
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 5) {
                            ForEach(intentResults.indices, id: \.self) { index in
                                Text("\(index + 1). \(intentResults[index])")
                                    .font(.caption)
                                    .padding(8)
                                    .background(Color.gray.opacity(0.1))
                                    .cornerRadius(8)
                            }
                        }
                        .padding()
                    }
                    .frame(maxHeight: 200)
                    
                    Button("Clear Results") {
                        intentResults.removeAll()
                    }
                    .padding()
                }
                .padding()
                
                Spacer()
            }
            .navigationTitle("Intents Demo")
        }
    }
    
    private func testAddTaskIntent() {
        let task = Task(title: "Intent Test Task", notes: "Added via intent", priority: .medium)
        taskStore.addTask(task)
        intentResults.append("Added task: \(task.title)")
        
        // Track intent usage
        IntentAnalytics.track(intent: "AddTaskIntent", parameters: [
            "title": task.title,
            "priority": task.priority.displayName
        ])
    }
    
    private func testCompleteTaskIntent() {
        if let firstIncompleteTask = taskStore.tasks.first(where: { !$0.isCompleted }) {
            taskStore.toggleTask(firstIncompleteTask)
            intentResults.append("Completed task: \(firstIncompleteTask.title)")
            
            IntentAnalytics.track(intent: "CompleteTaskIntent", parameters: [
                "task_id": firstIncompleteTask.id.uuidString
            ])
        } else {
            intentResults.append("No incomplete tasks to complete")
        }
    }
    
    private func testGetTasksIntent() {
        let incompleteTasks = taskStore.tasks.filter { !$0.isCompleted }
        intentResults.append("Found \(incompleteTasks.count) incomplete tasks")
        
        IntentAnalytics.track(intent: "GetTasksIntent", parameters: [
            "result_count": incompleteTasks.count
        ])
    }
}

// MARK: - Background Tasks View

struct BackgroundTaskView: View {
    @State private var taskStatus: [BackgroundTaskStatus] = []
    @State private var isLoading = false
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                // Background Task Status
                Section {
                    Text("Background Task Status")
                        .font(.headline)
                    
                    if isLoading {
                        ProgressView()
                    } else if taskStatus.isEmpty {
                        Text("No background tasks scheduled")
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(taskStatus.indices, id: \.self) { index in
                            let status = taskStatus[index]
                            VStack(alignment: .leading) {
                                Text(status.identifier)
                                    .font(.subheadline)
                                
                                if let earliestBeginDate = status.earliestBeginDate {
                                    Text("Next run: \(earliestBeginDate, style: .relative)")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                
                                Text(status.isScheduled ? "Scheduled" : "Not scheduled")
                                    .font(.caption)
                                    .foregroundColor(status.isScheduled ? .green : .red)
                            }
                            .padding(8)
                            .background(Color.gray.opacity(0.1))
                            .cornerRadius(8)
                        }
                    }
                    
                    Button("Refresh Status") {
                        Task {
                            isLoading = true
                            taskStatus = await BackgroundTaskCoordinator.shared.getTaskStatus()
                            isLoading = false
                        }
                    }
                    .padding()
                }
                .padding()
                
                // Manual Actions
                Section {
                    Text("Manual Actions")
                        .font(.headline)
                    
                    VStack(spacing: 10) {
                        Button("Schedule Data Sync") {
                            scheduleDataSync()
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                        
                        Button("Schedule Cache Cleanup") {
                            scheduleCacheCleanup()
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.orange)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                        
                        Button("Cancel All Tasks") {
                            BackgroundTaskManager.shared.cancelAllPendingTasks()
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.red)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                    }
                }
                .padding()
                
                Spacer()
            }
            .navigationTitle("Background Tasks")
        }
    }
    
    private func scheduleDataSync() {
        do {
            try BackgroundTaskManager.shared.scheduleAppRefresh(
                identifier: "com.archery.data-sync",
                earliestBeginDate: Date().addingTimeInterval(60) // 1 minute from now
            )
        } catch {
            print("Failed to schedule data sync: \(error)")
        }
    }
    
    private func scheduleCacheCleanup() {
        do {
            try BackgroundTaskManager.shared.scheduleProcessingTask(
                identifier: "com.archery.cache-cleanup",
                earliestBeginDate: Date().addingTimeInterval(300) // 5 minutes from now
            )
        } catch {
            print("Failed to schedule cache cleanup: \(error)")
        }
    }
}

// MARK: - Data Models

struct Task: Identifiable, Codable {
    let id = UUID()
    let title: String
    let notes: String
    let priority: TaskPriority
    let createdAt = Date()
    var isCompleted = false
    
    init(title: String, notes: String = "", priority: TaskPriority = .medium) {
        self.title = title
        self.notes = notes
        self.priority = priority
    }
}

enum TaskPriority: String, CaseIterable, Codable {
    case low, medium, high
    
    var displayName: String {
        switch self {
        case .low: return "Low"
        case .medium: return "Medium"
        case .high: return "High"
        }
    }
}

// MARK: - Task Store

class TaskStore: ObservableObject {
    @Published var tasks: [Task] = []
    
    init() {
        loadTasks()
    }
    
    func addTask(_ task: Task) {
        tasks.append(task)
        saveTasks()
        
        // Update widgets when tasks change
        WidgetTimelineManager.shared.scheduleUpdate(
            for: ["com.archery.task-widget"],
            delay: 1.0
        )
    }
    
    func toggleTask(_ task: Task) {
        if let index = tasks.firstIndex(where: { $0.id == task.id }) {
            tasks[index].isCompleted.toggle()
            saveTasks()
            
            // Update widgets
            WidgetTimelineManager.shared.scheduleUpdate(
                for: ["com.archery.task-widget"],
                delay: 0.5
            )
        }
    }
    
    func deleteTasks(at offsets: IndexSet) {
        tasks.remove(atOffsets: offsets)
        saveTasks()
        
        // Update widgets
        WidgetTimelineManager.shared.scheduleUpdate(
            for: ["com.archery.task-widget"],
            delay: 0.5
        )
    }
    
    private func loadTasks() {
        if let data = UserDefaults.standard.data(forKey: "tasks"),
           let decodedTasks = try? JSONDecoder().decode([Task].self, from: data) {
            tasks = decodedTasks
        }
    }
    
    private func saveTasks() {
        if let data = try? JSONEncoder().encode(tasks) {
            UserDefaults.standard.set(data, forKey: "tasks")
            
            // Also save to shared UserDefaults for widgets
            if let sharedDefaults = UserDefaults(suiteName: "group.archery.widgets") {
                sharedDefaults.set(data, forKey: "tasks")
            }
        }
    }
}

// MARK: - Repository Implementations

class TaskRepository: DataRepository {
    typealias Model = Task
    
    func fetch(id: UUID) async throws -> Task {
        // Mock implementation
        return Task(title: "Mock Task", notes: "This is a mock task")
    }
    
    func fetchAll() async throws -> [Task] {
        // Load from UserDefaults
        guard let data = UserDefaults.standard.data(forKey: "tasks"),
              let tasks = try? JSONDecoder().decode([Task].self, from: data) else {
            return []
        }
        return tasks
    }
    
    func save(_ model: Task) async throws {
        // Mock implementation
    }
    
    func delete(id: UUID) async throws {
        // Mock implementation
    }
}

class UserRepository: DataRepository {
    typealias Model = User
    
    func fetch(id: UUID) async throws -> User {
        return User(id: id, name: "Mock User", email: "user@example.com")
    }
    
    func fetchAll() async throws -> [User] {
        return [User(id: UUID(), name: "Mock User", email: "user@example.com")]
    }
    
    func save(_ model: User) async throws {
        // Mock implementation
    }
    
    func delete(id: UUID) async throws {
        // Mock implementation
    }
}

struct User: Identifiable, Codable {
    let id: UUID
    let name: String
    let email: String
}

// MARK: - App Intents Implementation

#if canImport(AppIntents)
@available(iOS 16.0, macOS 13.0, watchOS 9.0, tvOS 16.0, *)
struct AddTaskIntent: ArcheryAppIntent {
    typealias Repository = TaskRepository
    
    static var title: LocalizedStringResource = "Add Task"
    static var description = IntentDescription("Add a new task to your list")
    
    @Parameter(title: "Task Title")
    var title: String
    
    @Parameter(title: "Notes")
    var notes: String?
    
    @Parameter(title: "Priority")
    var priority: TaskPriorityEntity?
    
    func performAction() async throws -> IntentResult {
        let taskPriority = priority?.priority ?? .medium
        let task = Task(
            title: title,
            notes: notes ?? "",
            priority: taskPriority
        )
        
        // Save task (in real app, would use repository)
        if let data = UserDefaults.standard.data(forKey: "tasks"),
           var tasks = try? JSONDecoder().decode([Task].self, from: data) {
            tasks.append(task)
            
            if let encoded = try? JSONEncoder().encode(tasks) {
                UserDefaults.standard.set(encoded, forKey: "tasks")
            }
        }
        
        return IntentResultBuilder.success("Added task: \(title)")
    }
}

@available(iOS 16.0, macOS 13.0, watchOS 9.0, tvOS 16.0, *)
struct TaskPriorityEntity: AppEntity {
    let id: String
    let priority: TaskPriority
    
    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(priority.displayName)")
    }
    
    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Priority")
    
    static var defaultQuery = TaskPriorityQuery()
}

@available(iOS 16.0, macOS 13.0, watchOS 9.0, tvOS 16.0, *)
struct TaskPriorityQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [TaskPriorityEntity] {
        TaskPriority.allCases.compactMap { priority in
            if identifiers.contains(priority.rawValue) {
                return TaskPriorityEntity(id: priority.rawValue, priority: priority)
            }
            return nil
        }
    }
    
    func suggestedEntities() async throws -> [TaskPriorityEntity] {
        TaskPriority.allCases.map { priority in
            TaskPriorityEntity(id: priority.rawValue, priority: priority)
        }
    }
}
#endif