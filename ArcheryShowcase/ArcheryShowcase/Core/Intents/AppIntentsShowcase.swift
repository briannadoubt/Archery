import Foundation
import AppIntents
import SwiftUI
import Archery

// MARK: - App Intents Showcase
//
// This file demonstrates App Intents using model types that have
// @IntentEntity and @IntentEnum macros applied (see Models.swift).
//
// The macros generate: typeDisplayRepresentation, displayRepresentation,
// and caseDisplayRepresentations automatically.

// MARK: - App Intents (using macro-annotated model types)

struct ViewTasksIntent: AppIntent {
    static let title: LocalizedStringResource = "View Tasks"
    static let description: IntentDescription = IntentDescription("Opens the task list")
    static let openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult {
        .result()
    }
}

struct CreateTaskIntent: AppIntent {
    static let title: LocalizedStringResource = "Create Task"
    static let description: IntentDescription = IntentDescription("Creates a new task")

    @Parameter(title: "Title")
    var title: String

    @Parameter(title: "Priority")
    var priority: TaskPriority  // Uses @IntentEnum from Models.swift

    @Parameter(title: "Due Date")
    var dueDate: Date?

    static var parameterSummary: some ParameterSummary {
        Summary("Create \(\.$title) with \(\.$priority) priority") {
            \.$dueDate
        }
    }

    func perform() async throws -> some IntentResult & ReturnsValue<TaskItem> {
        let newTask = TaskItem(
            id: UUID().uuidString,
            title: title,
            priority: priority
        )
        return .result(value: newTask)  // Returns @IntentEntity from Models.swift
    }
}

struct CompleteTaskIntent: AppIntent {
    static let title: LocalizedStringResource = "Complete Task"
    static let description: IntentDescription = IntentDescription("Marks a task as completed")

    @Parameter(title: "Task")
    var task: TaskItem  // Uses @IntentEntity from Models.swift

    func perform() async throws -> some IntentResult & ProvidesDialog {
        .result(dialog: "Marked '\(task.title)' as completed!")
    }
}

struct GetTaskCountIntent: AppIntent {
    static let title: LocalizedStringResource = "Get Task Count"
    static let description: IntentDescription = IntentDescription("Returns incomplete task count")

    func perform() async throws -> some IntentResult & ReturnsValue<Int> & ProvidesDialog {
        let count = TaskItem.mockTasks.filter { !$0.isCompleted }.count
        return .result(value: count, dialog: "You have \(count) incomplete tasks")
    }
}

struct FilterTasksByStatusIntent: AppIntent {
    static let title: LocalizedStringResource = "Filter Tasks by Status"
    static let description: IntentDescription = IntentDescription("Filters tasks by their status")

    @Parameter(title: "Status")
    var status: TaskStatus  // Uses @IntentEnum from Models.swift

    func perform() async throws -> some IntentResult & ReturnsValue<[TaskItem]> & ProvidesDialog {
        let filtered = TaskItem.mockTasks.filter { $0.status == status }
        return .result(
            value: filtered,
            dialog: "Found \(filtered.count) tasks with status '\(status.rawValue)'"
        )
    }
}

// MARK: - Quick Action Intents
//
// These intents power the Dashboard Quick Actions buttons using Button(intent:)

struct NewTaskIntent: AppIntent {
    static let title: LocalizedStringResource = "New Task"
    static let description = IntentDescription("Create a new task")
    static let openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult {
        await MainActor.run {
            NotificationCenter.default.post(name: .showNewTaskSheet, object: nil)
        }
        return .result()
    }
}

struct ViewReportIntent: AppIntent {
    static let title: LocalizedStringResource = "View Report"
    static let description = IntentDescription("View analytics and reports")
    static let openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult {
        await MainActor.run {
            NotificationCenter.default.post(name: .navigateToInsights, object: nil)
        }
        return .result()
    }
}

struct ViewTeamIntent: AppIntent {
    static let title: LocalizedStringResource = "View Team"
    static let description = IntentDescription("View team members")
    static let openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult {
        await MainActor.run {
            NotificationCenter.default.post(name: .navigateToTeam, object: nil)
        }
        return .result()
    }
}

struct ExportDataIntent: AppIntent {
    static let title: LocalizedStringResource = "Export Data"
    static let description = IntentDescription("Export tasks and data")

    @Parameter(title: "Format", default: .csv)
    var format: ExportFormat

    func perform() async throws -> some IntentResult & ProvidesDialog {
        return .result(dialog: "Data exported as \(format.rawValue.uppercased())")
    }
}

@IntentEnum
enum ExportFormat: String, AppEnum {
    case csv
    case json
    case pdf
}

// MARK: - Notification Names for Intent Navigation

extension Notification.Name {
    static let showNewTaskSheet = Notification.Name("showNewTaskSheet")
    static let navigateToInsights = Notification.Name("navigateToInsights")
    static let navigateToTeam = Notification.Name("navigateToTeam")
}

// MARK: - App Shortcuts

struct ShowcaseShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: ViewTasksIntent(),
            phrases: ["Show my tasks in \(.applicationName)"],
            shortTitle: "View Tasks",
            systemImageName: "checklist"
        )
        AppShortcut(
            intent: GetTaskCountIntent(),
            phrases: ["How many tasks in \(.applicationName)"],
            shortTitle: "Task Count",
            systemImageName: "number"
        )
        AppShortcut(
            intent: NewTaskIntent(),
            phrases: ["Create a task in \(.applicationName)", "New task in \(.applicationName)"],
            shortTitle: "New Task",
            systemImageName: "plus.circle"
        )
        AppShortcut(
            intent: ViewReportIntent(),
            phrases: ["Show reports in \(.applicationName)", "View insights in \(.applicationName)"],
            shortTitle: "View Reports",
            systemImageName: "chart.bar"
        )
        AppShortcut(
            intent: ExportDataIntent(),
            phrases: ["Export data from \(.applicationName)"],
            shortTitle: "Export Data",
            systemImageName: "square.and.arrow.up"
        )
    }
}

// MARK: - Demo View

struct AppIntentsShowcaseView: View {
    var body: some View {
        List {
            Section("Model Types with Macros") {
                LabeledContent("TaskItem") {
                    Text("@IntentEntity → AppEntity")
                        .font(.caption.monospaced())
                }
                Text("Generates typeDisplayRepresentation and displayRepresentation. You add AppEntity conformance and provide defaultQuery.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                LabeledContent("TaskPriority") {
                    Text("@IntentEnum → AppEnum")
                        .font(.caption.monospaced())
                }
                LabeledContent("TaskStatus") {
                    Text("@IntentEnum → AppEnum")
                        .font(.caption.monospaced())
                }
                Text("Generates typeDisplayRepresentation and caseDisplayRepresentations. You add AppEnum conformance.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("App Intents") {
                ForEach([
                    ("ViewTasksIntent", "Opens task list"),
                    ("CreateTaskIntent", "Uses TaskPriority param"),
                    ("CompleteTaskIntent", "Uses TaskItem param"),
                    ("GetTaskCountIntent", "Returns count"),
                    ("FilterTasksByStatusIntent", "Uses TaskStatus param")
                ], id: \.0) { intent in
                    LabeledContent(intent.0) {
                        Text(intent.1)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section("Quick Action Intents") {
                ForEach([
                    ("NewTaskIntent", "Opens new task sheet"),
                    ("ViewReportIntent", "Navigates to Insights"),
                    ("ViewTeamIntent", "Navigates to Team"),
                    ("ExportDataIntent", "Uses @IntentEnum ExportFormat")
                ], id: \.0) { intent in
                    LabeledContent(intent.0) {
                        Text(intent.1)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Text("These power the Dashboard Quick Actions using Button(intent:)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Text("Model types in Models.swift have @IntentEntity/@IntentEnum macros. The intents here use those types directly!")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("App Intents")
    }
}

#Preview {
    NavigationStack {
        AppIntentsShowcaseView()
    }
}
