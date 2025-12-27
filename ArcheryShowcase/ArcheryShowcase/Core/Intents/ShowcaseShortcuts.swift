import AppIntents

// MARK: - App Shortcuts Provider

/// Provides Siri shortcuts for the Archery Showcase app.
///
/// Uses macro-generated Intent types from @Persistable:
/// - `TaskItemEntityListIntent` - Lists all tasks
/// - `TaskItemEntityDeleteIntent` - Deletes a task
/// - `PersistentProjectEntityListIntent` - Lists all projects
struct ShowcaseShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: TaskItemEntityListIntent(),
            phrases: [
                "Show my tasks in \(.applicationName)",
                "List tasks in \(.applicationName)"
            ],
            shortTitle: "List Tasks",
            systemImageName: "checklist"
        )
        AppShortcut(
            intent: PersistentProjectEntityListIntent(),
            phrases: [
                "Show my projects in \(.applicationName)",
                "List projects in \(.applicationName)"
            ],
            shortTitle: "List Projects",
            systemImageName: "folder"
        )
    }
}
