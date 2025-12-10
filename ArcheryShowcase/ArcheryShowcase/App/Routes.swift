import SwiftUI
import Archery

// MARK: - App Routes
//
// Route definitions for the app's navigation system.
// Each @Route enum defines the screens available in a tab/feature.

@Route(path: "dashboard")
enum DashboardRoute: NavigationRoute {
    case root
    case stats
    case activity

    @presents(.sheet, detents: [.medium, .large])
    case notifications

    @presents(.sheet)
    case newTask

    @presents(.sheet, detents: [.large])
    case filteredTasks(filter: TaskFilter)

    @presents(.sheet)
    case editTask(id: String)
}

@Route(path: "tasks")
enum TasksRoute: NavigationRoute {
    case root
    case detail(id: String)

    @presents(.sheet)
    case newTask

    @presents(.sheet, detents: [.large])
    case taskWizard

    @requires(.premium)
    @presents(.fullScreen)
    case analytics

    @requires(.pro)
    @presents(.sheet, detents: [.large])
    case bulkEdit
}

@Route(path: "forms")
enum FormsRoute: NavigationRoute {
    case root
    case validation
    case builder
}

@Route(path: "insights", requires: .premium)
enum InsightsRoute: NavigationRoute {
    case root
    case reports
    case export
}

@Route(path: "admin", requires: .pro)
enum AdminRoute: NavigationRoute {
    case root
    case users
    case permissions
}

@Route(path: "settings")
enum SettingsRoute: NavigationRoute {
    case root
    case account
    case appearance
    case about

    @presents(.sheet, detents: [.large])
    case paywall

    @presents(.sheet, detents: [.large])
    case premiumPaywall
}

// MARK: - Task Creation Flow

@Flow(path: "taskCreation", persists: false)
enum TaskCreationFlow: CaseIterable, Hashable {
    case basicInfo      // Step 1: Title and description
    case scheduling     // Step 2: Due date and reminders
    case priority       // Step 3: Priority and tags
    case review         // Step 4: Review and confirm
}
