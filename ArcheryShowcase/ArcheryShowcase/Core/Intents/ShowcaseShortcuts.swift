// MARK: - App Shortcuts Provider
//
// Note: App Intents and Shortcuts require manually-defined types.
// Macro-generated types (like @Persistable's Entity types) don't work with
// AppShortcutsProvider because it requires static analysis at compile time.
//
// To add Siri shortcuts to this app:
// 1. Define AppIntent structs manually in this file
// 2. Create an AppShortcutsProvider that references them
// 3. Implement the intents to interact with the database
//
// Example:
// ```swift
// import AppIntents
//
// struct ListTasksIntent: AppIntent {
//     static var title: LocalizedStringResource { "List Tasks" }
//
//     @MainActor
//     func perform() async throws -> some IntentResult {
//         // Access database and return tasks
//         return .result()
//     }
// }
//
// struct ShowcaseShortcuts: AppShortcutsProvider {
//     static var appShortcuts: [AppShortcut] {
//         AppShortcut(
//             intent: ListTasksIntent(),
//             phrases: ["Show my tasks in \(.applicationName)"],
//             shortTitle: "List Tasks",
//             systemImageName: "checklist"
//         )
//     }
// }
// ```
