import SwiftUI
import Archery

// MARK: - Task Search ViewModel

/// ViewModel for task search with debounced filtering.
/// Uses @ObservableViewModel for lifecycle management and debounce support.
///
/// The macro generates:
/// - `debounce(id:dueTime:action:)` for debounced updates
/// - `throttle(id:interval:action:)` for throttled updates
/// - `onAppear()` / `onDisappear()` for lifecycle
/// - `track(_:)` for task cancellation management
@Observable
@MainActor
@ObservableViewModel
final class TaskSearchViewModel: Resettable {
    // MARK: - State

    var searchText: String = "" {
        didSet {
            guard searchText != oldValue else { return }
            performDebouncedSearch()
        }
    }

    var selectedFilter: TaskFilter = .all
    var isSearching: Bool = false
    var recentSearches: [String] = []

    // MARK: - Private

    private var allTasks: [TaskItem] = []

    // MARK: - Computed

    var filteredTasks: [TaskItem] {
        var result = allTasks

        // Apply filter
        switch selectedFilter {
        case .all:
            break
        case .today:
            result = result.filter { Calendar.current.isDateInToday($0.dueDate ?? .distantPast) }
        case .upcoming:
            result = result.filter {
                guard let dueDate = $0.dueDate else { return false }
                return dueDate > Date() && !Calendar.current.isDateInToday(dueDate)
            }
        case .completed:
            result = result.filter { $0.isCompleted }
        case .incomplete:
            result = result.filter { !$0.isCompleted }
        case .high:
            result = result.filter { $0.priority == .high || $0.priority == .urgent }
        }

        // Apply search (already debounced)
        if !searchText.isEmpty {
            let query = searchText.lowercased()
            result = result.filter {
                $0.title.lowercased().contains(query) ||
                ($0.taskDescription?.lowercased().contains(query) ?? false)
            }
        }

        return result
    }

    var hasActiveFilters: Bool {
        !searchText.isEmpty || selectedFilter != .all
    }

    // MARK: - Public Methods

    func updateTasks(_ tasks: [TaskItem]) {
        allTasks = tasks
    }

    func clearSearch() {
        searchText = ""
        selectedFilter = .all
    }

    func addToRecentSearches() {
        guard !searchText.isEmpty else { return }
        recentSearches.removeAll { $0 == searchText }
        recentSearches.insert(searchText, at: 0)
        if recentSearches.count > 5 {
            recentSearches = Array(recentSearches.prefix(5))
        }
    }

    // MARK: - Private Methods

    private func performDebouncedSearch() {
        isSearching = true

        // Use the generated debounce method from @ObservableViewModel
        debounce(id: "search", dueTime: .milliseconds(300)) { [weak self] in
            await MainActor.run {
                self?.isSearching = false
                if !(self?.searchText.isEmpty ?? true) {
                    self?.addToRecentSearches()
                }
            }
        }
    }
}

// MARK: - Preview Support

extension TaskSearchViewModel {
    static func preview(with tasks: [TaskItem] = []) -> TaskSearchViewModel {
        let vm = TaskSearchViewModel()
        vm.updateTasks(tasks)
        return vm
    }
}
