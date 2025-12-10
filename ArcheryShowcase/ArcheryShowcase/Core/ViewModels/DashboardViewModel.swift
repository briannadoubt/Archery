import Foundation
import Archery

// MARK: - Dashboard ViewModel (using @ObservableViewModel macro)

/// Demonstrates the @ObservableViewModel macro which generates:
/// - Observation support (Observable conformance)
/// - Lifecycle management (onAppear, onDisappear, reset)
/// - Task tracking and cancellation
/// - Debounce and throttle utilities
/// - LoadState helpers (beginLoading, endSuccess, endFailure)
@ObservableViewModel
@MainActor
class DashboardViewModel: Resettable {
    // MARK: - State

    var statsState: LoadState<DashboardStats> = .idle
    var activityState: LoadState<[ActivityDataPoint]> = .idle
    var tasksState: LoadState<[TaskItem]> = .idle

    // MARK: - Dependencies

    private let dashboardRepository: DashboardRepositoryProtocol
    private let taskRepository: TaskRepositoryProtocol

    // MARK: - Init

    init(
        dashboardRepository: DashboardRepositoryProtocol? = nil,
        taskRepository: TaskRepositoryProtocol? = nil
    ) {
        // Use generated Live implementations with DI
        self.dashboardRepository = dashboardRepository ?? DashboardRepositoryLive()
        self.taskRepository = taskRepository ?? TaskRepositoryLive()
    }

    // MARK: - Load (called by generated onAppear)

    func load() async {
        await loadDashboard()
    }

    // MARK: - Actions

    func loadDashboard() async {
        beginLoading(\.statsState)
        beginLoading(\.activityState)
        beginLoading(\.tasksState)

        do {
            async let stats = dashboardRepository.getStats()
            async let activity = dashboardRepository.getActivityData(days: 7)
            async let tasks = taskRepository.getTasks()

            let (statsResult, activityResult, tasksResult) = try await (stats, activity, tasks)

            endSuccess(\.statsState, value: statsResult)
            endSuccess(\.activityState, value: activityResult)
            endSuccess(\.tasksState, value: tasksResult)
        } catch {
            endFailure(\.statsState, error: error)
            endFailure(\.activityState, error: error)
            endFailure(\.tasksState, error: error)
        }
    }

    func refresh() async {
        await loadDashboard()
    }

    func searchTasks(query: String) {
        // Debounce search to avoid excessive API calls
        debounce(id: "search", dueTime: .milliseconds(300)) { [weak self] in
            guard self != nil else { return }
            // Perform search
            print("Searching for: \(query)")
        }
    }

    func trackAnalyticsEvent() {
        // Throttle analytics to avoid flooding
        throttle(id: "analytics", interval: .seconds(1)) {
            print("Analytics event tracked")
        }
    }
}

// MARK: - Task List ViewModel (using @ObservableViewModel macro)

@ObservableViewModel
@MainActor
class TaskListViewModel: Resettable {
    // MARK: - State

    var tasksState: LoadState<[TaskItem]> = .idle
    var selectedFilter: TaskFilter = .all
    var searchQuery: String = ""

    // MARK: - Dependencies

    private let repository: TaskRepositoryProtocol

    // MARK: - Init

    init(repository: TaskRepositoryProtocol? = nil) {
        self.repository = repository ?? TaskRepositoryLive()
    }

    // MARK: - Load

    func load() async {
        await loadTasks()
    }

    // MARK: - Actions

    func loadTasks() async {
        beginLoading(\.tasksState)

        do {
            let tasks = try await repository.getTasks()
            endSuccess(\.tasksState, value: tasks)
        } catch {
            endFailure(\.tasksState, error: error)
        }
    }

    func deleteTask(id: String) async {
        do {
            try await repository.deleteTask(id: id)
            await loadTasks()
        } catch {
            print("Failed to delete task: \(error)")
        }
    }

    func setFilter(_ filter: TaskFilter) {
        selectedFilter = filter
    }

    var filteredTasks: [TaskItem] {
        guard case .success(let tasks) = tasksState else { return [] }

        var result = tasks

        // Apply filter
        switch selectedFilter {
        case .all:
            break
        case .today:
            result = result.filter { Calendar.current.isDateInToday($0.dueDate ?? .distantPast) }
        case .upcoming:
            result = result.filter { ($0.dueDate ?? .distantPast) > Date() }
        case .completed:
            result = result.filter { $0.status == .completed }
        case .incomplete:
            result = result.filter { $0.status != .completed }
        case .high:
            result = result.filter { $0.priority == .high }
        }

        // Apply search
        if !searchQuery.isEmpty {
            result = result.filter {
                $0.title.localizedCaseInsensitiveContains(searchQuery)
            }
        }

        return result
    }
}
