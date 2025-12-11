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

    // @requiresAny: User needs EITHER premium OR pro
    @requiresAny(.premium, .pro)
    @presents(.sheet, detents: [.medium, .large])
    case advancedFilters

    // @requiresAll: User needs BOTH admin AND verified status
    @requiresAll(.admin, .verified)
    @presents(.fullScreen)
    case auditLog
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

    // @requiresAny: Any elevated role grants access
    @requiresAny(.admin, .moderator, .support)
    @presents(.sheet)
    case userManagement

    // @requiresAll: Requires admin AND 2FA for security settings
    @requiresAll(.admin, .twoFactorEnabled)
    @presents(.fullScreen)
    case securitySettings

    // @requiresAll with verified status check
    @requiresAll(.moderator, .verified)
    case moderationQueue
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

// MARK: - Onboarding Flow (with @branch and @skip)
//
// Demonstrates conditional flow control:
// - @skip: Skip steps when condition is already met
// - @branch: Replace a step with an alternative when condition is met

/// Condition keys used by @skip and @branch macros.
/// The macro reads these as string identifiers for runtime evaluation.
enum FlowCondition {
    case hasExistingAccount
    case permissionsAlreadyGranted
    case isFreeTier
}

@Flow(path: "onboarding", persists: true)
enum SetupFlow: CaseIterable, Hashable {
    case welcome                // Always shown first

    case createAccount          // For new users

    @skip(when: FlowCondition.permissionsAlreadyGranted)
    case requestPermissions     // Skip if already granted

    case selectTheme            // Let user pick appearance

    @skip(when: FlowCondition.isFreeTier)
    case premiumSetup           // Skip for free users

    case complete               // Finish onboarding

    // Branch: If user has existing account, show sign-in instead of create
    @branch(replacing: SetupFlow.createAccount, when: FlowCondition.hasExistingAccount)
    case signIn
}
