import SwiftUI
import Archery

// MARK: - Task List View with @Repository

@ViewModelBound(viewModel: TaskListViewModel.self)
struct TaskListView: View {
    @StateObject var vm: TaskListViewModel
    @State private var showingNewTask = false
    @State private var searchText = ""
    @State private var selectedFilter: TaskFilter = .all
    @Environment(\.designTokens) var tokens
    
    var body: some View {
        NavigationStack {
            List {
                // Search and filter bar
                VStack(spacing: tokens.spacing.medium) {
                    SearchBar(text: $searchText)
                        .onChange(of: searchText) { _, newValue in
                            vm.searchTasks(query: newValue)
                        }
                    
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: tokens.spacing.small) {
                            ForEach(TaskFilter.allCases, id: \.self) { filter in
                                FilterChip(
                                    title: filter.title,
                                    isSelected: selectedFilter == filter
                                ) {
                                    selectedFilter = filter
                                    vm.applyFilter(filter)
                                }
                            }
                        }
                    }
                }
                .listRowInsets(EdgeInsets())
                .listRowSeparator(.hidden)
                .padding()
                
                // Task sections
                ForEach(vm.taskSections) { section in
                    Section(header: TaskSectionHeader(section: section)) {
                        ForEach(section.tasks) { task in
                            TaskRowView(task: task)
                                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                    Button(role: .destructive) {
                                        Task { await vm.deleteTask(task) }
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                    
                                    Button {
                                        Task { await vm.archiveTask(task) }
                                    } label: {
                                        Label("Archive", systemImage: "archivebox")
                                    }
                                    .tint(.orange)
                                }
                                .swipeActions(edge: .leading) {
                                    Button {
                                        Task { await vm.toggleComplete(task) }
                                    } label: {
                                        Label(
                                            task.isCompleted ? "Incomplete" : "Complete",
                                            systemImage: task.isCompleted ? "xmark.circle" : "checkmark.circle"
                                        )
                                    }
                                    .tint(task.isCompleted ? .gray : .green)
                                }
                                .contextMenu {
                                    TaskContextMenu(task: task, viewModel: vm)
                                }
                        }
                        .onDelete { indexSet in
                            Task {
                                await vm.deleteTasks(at: indexSet, in: section)
                            }
                        }
                    }
                }
                
                // Load more button for pagination
                if vm.hasMorePages {
                    HStack {
                        Spacer()
                        Button("Load More") {
                            Task { await vm.loadNextPage() }
                        }
                        .disabled(vm.isLoadingMore)
                        if vm.isLoadingMore {
                            ProgressView()
                                .scaleEffect(0.8)
                        }
                        Spacer()
                    }
                    .listRowSeparator(.hidden)
                    .padding()
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Tasks")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    EditButton()
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button(action: { vm.sortBy(.dueDate) }) {
                            Label("Due Date", systemImage: "calendar")
                        }
                        Button(action: { vm.sortBy(.priority) }) {
                            Label("Priority", systemImage: "exclamationmark.circle")
                        }
                        Button(action: { vm.sortBy(.name) }) {
                            Label("Name", systemImage: "textformat")
                        }
                        Button(action: { vm.sortBy(.createdDate) }) {
                            Label("Created Date", systemImage: "clock")
                        }
                    } label: {
                        Image(systemName: "arrow.up.arrow.down")
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { showingNewTask = true }) {
                        Image(systemName: "plus")
                    }
                }
            }
            .refreshable {
                await vm.refresh()
            }
            .sheet(isPresented: $showingNewTask) {
                NewTaskView()
            }
            .task {
                await vm.load()
            }
            .overlay {
                if vm.isLoading && vm.taskSections.isEmpty {
                    ProgressView("Loading tasks...")
                } else if vm.taskSections.isEmpty {
                    EmptyStateView(
                        title: "No Tasks",
                        message: "Create your first task to get started",
                        systemImage: "checklist",
                        action: {
                            showingNewTask = true
                        }
                    )
                }
            }
        }
    }
}

// MARK: - Task List ViewModel

@ObservableViewModel
class TaskListViewModel: ObservableObject {
    @Published var taskSections: [TaskSection] = []
    @Published var isLoading = false
    @Published var isLoadingMore = false
    @Published var error: Error?
    @Published var hasMorePages = true
    @Published var currentPage = 1
    
    @Injected private var taskRepository: TaskRepository
    @Injected private var analyticsService: AnalyticsService
    
    private var allTasks: [Task] = []
    private var currentFilter: TaskFilter = .all
    private var currentSort: TaskSort = .dueDate
    private var searchQuery = ""
    
    @MainActor
    func load() async {
        isLoading = true
        error = nil
        
        do {
            let tasks = try await taskRepository.getTasks(
                page: 1,
                limit: 20,
                filter: currentFilter,
                sort: currentSort
            )
            
            allTasks = tasks
            updateSections()
            hasMorePages = tasks.count == 20
            currentPage = 1
            
            analyticsService.track(.taskListViewed(count: tasks.count))
        } catch {
            self.error = error
        }
        
        isLoading = false
    }
    
    @MainActor
    func refresh() async {
        await load()
    }
    
    @MainActor
    func loadNextPage() async {
        guard hasMorePages && !isLoadingMore else { return }
        
        isLoadingMore = true
        
        do {
            let tasks = try await taskRepository.getTasks(
                page: currentPage + 1,
                limit: 20,
                filter: currentFilter,
                sort: currentSort
            )
            
            allTasks.append(contentsOf: tasks)
            updateSections()
            hasMorePages = tasks.count == 20
            currentPage += 1
        } catch {
            self.error = error
        }
        
        isLoadingMore = false
    }
    
    @MainActor
    func deleteTask(_ task: Task) async {
        do {
            try await taskRepository.deleteTask(task.id)
            allTasks.removeAll { $0.id == task.id }
            updateSections()
            
            analyticsService.track(.taskDeleted(id: task.id))
        } catch {
            self.error = error
        }
    }
    
    @MainActor
    func deleteTasks(at indexSet: IndexSet, in section: TaskSection) async {
        for index in indexSet {
            let task = section.tasks[index]
            await deleteTask(task)
        }
    }
    
    @MainActor
    func archiveTask(_ task: Task) async {
        do {
            try await taskRepository.archiveTask(task.id)
            allTasks.removeAll { $0.id == task.id }
            updateSections()
            
            analyticsService.track(.taskArchived(id: task.id))
        } catch {
            self.error = error
        }
    }
    
    @MainActor
    func toggleComplete(_ task: Task) async {
        do {
            let updatedTask = try await taskRepository.updateTask(
                task.id,
                updates: ["isCompleted": !task.isCompleted]
            )
            
            if let index = allTasks.firstIndex(where: { $0.id == task.id }) {
                allTasks[index] = updatedTask
            }
            updateSections()
            
            analyticsService.track(.taskCompleted(id: task.id))
        } catch {
            self.error = error
        }
    }
    
    func searchTasks(query: String) {
        searchQuery = query
        updateSections()
    }
    
    func applyFilter(_ filter: TaskFilter) {
        currentFilter = filter
        Task {
            await load()
        }
    }
    
    func sortBy(_ sort: TaskSort) {
        currentSort = sort
        updateSections()
    }
    
    private func updateSections() {
        var filteredTasks = allTasks
        
        // Apply search
        if !searchQuery.isEmpty {
            filteredTasks = filteredTasks.filter { task in
                task.title.localizedCaseInsensitiveContains(searchQuery) ||
                task.description?.localizedCaseInsensitiveContains(searchQuery) == true
            }
        }
        
        // Sort tasks
        switch currentSort {
        case .dueDate:
            filteredTasks.sort { ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture) }
        case .priority:
            filteredTasks.sort { $0.priority.rawValue > $1.priority.rawValue }
        case .name:
            filteredTasks.sort { $0.title < $1.title }
        case .createdDate:
            filteredTasks.sort { $0.createdAt > $1.createdAt }
        }
        
        // Group into sections
        let grouped = Dictionary(grouping: filteredTasks) { task in
            task.sectionTitle
        }
        
        taskSections = grouped.map { key, tasks in
            TaskSection(title: key, tasks: tasks)
        }.sorted { $0.title < $1.title }
    }
}

// MARK: - Supporting Types

struct TaskSection: Identifiable {
    let id = UUID()
    let title: String
    let tasks: [Task]
}

enum TaskFilter: String, CaseIterable {
    case all = "All"
    case today = "Today"
    case upcoming = "Upcoming"
    case completed = "Completed"
    case incomplete = "Incomplete"
    case high = "High Priority"
    
    var title: String { rawValue }
}

enum TaskSort {
    case dueDate
    case priority
    case name
    case createdDate
}

// MARK: - Task Row View

struct TaskRowView: View {
    let task: Task
    @Environment(\.designTokens) var tokens
    
    var body: some View {
        HStack(spacing: tokens.spacing.medium) {
            // Completion checkbox
            Button(action: {}) {
                Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(task.isCompleted ? .green : .secondary)
                    .font(.title3)
            }
            .buttonStyle(.plain)
            
            // Task details
            VStack(alignment: .leading, spacing: tokens.spacing.xSmall) {
                Text(task.title)
                    .font(.body)
                    .strikethrough(task.isCompleted)
                    .foregroundStyle(task.isCompleted ? .secondary : .primary)
                
                if let description = task.description {
                    Text(description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                
                HStack(spacing: tokens.spacing.small) {
                    if let dueDate = task.dueDate {
                        Label(dueDate.formatted(date: .abbreviated, time: .omitted), systemImage: "calendar")
                            .font(.caption2)
                            .foregroundStyle(dueDate < Date() ? .red : .secondary)
                    }
                    
                    if task.priority != .medium {
                        Label(task.priority.title, systemImage: task.priority.icon)
                            .font(.caption2)
                            .foregroundStyle(task.priority.color)
                    }
                    
                    if let project = task.project {
                        Label(project.name, systemImage: "folder")
                            .font(.caption2)
                            .foregroundStyle(.blue)
                    }
                }
            }
            
            Spacer()
            
            // Tags
            if !task.tags.isEmpty {
                HStack(spacing: 4) {
                    ForEach(task.tags.prefix(2), id: \.self) { tag in
                        Text(tag)
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.accentColor.opacity(0.1))
                            .clipShape(Capsule())
                    }
                    if task.tags.count > 2 {
                        Text("+\(task.tags.count - 2)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(.vertical, tokens.spacing.xSmall)
    }
}