import Foundation
import WidgetKit
import AppIntents
import SwiftUI

// MARK: - Widget Shared Code
//
// This file contains code that can be shared between the main app and widget extension.
// To create a widget extension:
// 1. In Xcode: File > New > Target > Widget Extension
// 2. Name it "ArcheryShowcaseWidgets"
// 3. Add this file to the widget target (check the target membership)
// 4. Set up App Group for data sharing (optional but recommended)

// MARK: - Widget Entry

struct TaskWidgetEntry: TimelineEntry {
    let date: Date
    let tasks: [TaskWidgetData]
    let stats: TaskWidgetStats

    static let placeholder = TaskWidgetEntry(
        date: Date(),
        tasks: [
            TaskWidgetData(id: "1", title: "Sample Task", priority: .high, isCompleted: false),
            TaskWidgetData(id: "2", title: "Another Task", priority: .medium, isCompleted: true)
        ],
        stats: TaskWidgetStats(total: 10, completed: 6, overdue: 1)
    )
}

struct TaskWidgetData: Identifiable, Codable, Sendable {
    let id: String
    let title: String
    let priority: WidgetPriority
    let isCompleted: Bool
    let dueDate: Date?

    init(id: String, title: String, priority: WidgetPriority, isCompleted: Bool, dueDate: Date? = nil) {
        self.id = id
        self.title = title
        self.priority = priority
        self.isCompleted = isCompleted
        self.dueDate = dueDate
    }
}

struct TaskWidgetStats: Codable, Sendable {
    let total: Int
    let completed: Int
    let overdue: Int

    var completionPercentage: Double {
        guard total > 0 else { return 0 }
        return Double(completed) / Double(total)
    }
}

enum WidgetPriority: String, Codable, Sendable {
    case low, medium, high, urgent

    var color: Color {
        switch self {
        case .low: return .gray
        case .medium: return .blue
        case .high: return .orange
        case .urgent: return .red
        }
    }

    var icon: String {
        switch self {
        case .low: return "arrow.down.circle"
        case .medium: return "minus.circle"
        case .high: return "arrow.up.circle"
        case .urgent: return "exclamationmark.circle.fill"
        }
    }
}

// MARK: - Timeline Provider

struct TaskWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> TaskWidgetEntry {
        .placeholder
    }

    func getSnapshot(in context: Context, completion: @escaping (TaskWidgetEntry) -> Void) {
        let entry = TaskWidgetEntry.placeholder
        completion(entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TaskWidgetEntry>) -> Void) {
        Task { @MainActor in
            // In a real app, fetch from shared UserDefaults/App Group
            let tasks = TaskItem.mockTasks.prefix(5).map { task in
                TaskWidgetData(
                    id: task.id,
                    title: task.title,
                    priority: WidgetPriority(rawValue: task.priority.title.lowercased()) ?? .medium,
                    isCompleted: task.isCompleted,
                    dueDate: task.dueDate
                )
            }

            let allTasks = TaskItem.mockTasks
            let stats = TaskWidgetStats(
                total: allTasks.count,
                completed: allTasks.filter(\.isCompleted).count,
                overdue: allTasks.filter { $0.dueDate ?? .distantFuture < Date() && !$0.isCompleted }.count
            )

            let entry = TaskWidgetEntry(date: Date(), tasks: Array(tasks), stats: stats)
            let nextUpdate = Calendar.current.date(byAdding: .minute, value: 15, to: Date())!
            let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
            completion(timeline)
        }
    }
}

// MARK: - Widget Views

struct TaskListWidgetView: View {
    let entry: TaskWidgetEntry
    @Environment(\.widgetFamily) var family

    var body: some View {
        switch family {
        case .systemSmall:
            smallView
        case .systemMedium:
            mediumView
        case .systemLarge:
            largeView
        default:
            smallView
        }
    }

    private var smallView: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: "checklist")
                Text("Tasks")
                    .font(.headline)
            }

            Spacer()

            Text("\(entry.stats.completed)/\(entry.stats.total)")
                .font(.system(size: 32, weight: .bold, design: .rounded))

            Text("completed")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
    }

    private var mediumView: some View {
        HStack(spacing: 16) {
            // Stats
            VStack(alignment: .leading) {
                HStack {
                    Image(systemName: "checklist")
                    Text("Tasks")
                        .font(.headline)
                }

                Spacer()

                Text("\(entry.stats.completed)/\(entry.stats.total)")
                    .font(.system(size: 28, weight: .bold, design: .rounded))

                if entry.stats.overdue > 0 {
                    Text("\(entry.stats.overdue) overdue")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Task list
            VStack(alignment: .leading, spacing: 4) {
                ForEach(entry.tasks.prefix(3)) { task in
                    HStack(spacing: 6) {
                        Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(task.isCompleted ? .green : task.priority.color)
                            .font(.caption)

                        Text(task.title)
                            .font(.caption)
                            .lineLimit(1)
                            .strikethrough(task.isCompleted)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding()
    }

    private var largeView: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "checklist")
                Text("Tasks")
                    .font(.headline)
                Spacer()
                Text("\(entry.stats.completed)/\(entry.stats.total)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Divider()

            ForEach(entry.tasks) { task in
                HStack(spacing: 8) {
                    Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(task.isCompleted ? .green : task.priority.color)

                    Text(task.title)
                        .lineLimit(1)
                        .strikethrough(task.isCompleted)

                    Spacer()

                    if let dueDate = task.dueDate {
                        Text(dueDate, style: .relative)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .font(.subheadline)
            }

            Spacer()
        }
        .padding()
    }
}

// MARK: - Widget Configuration (use in Widget Extension)
//
// Copy this to your Widget Extension's main file:
//
// @main
// struct ArcheryShowcaseWidgets: WidgetBundle {
//     var body: some Widget {
//         TaskListWidget()
//     }
// }
//
// struct TaskListWidget: Widget {
//     let kind = "TaskListWidget"
//
//     var body: some WidgetConfiguration {
//         StaticConfiguration(kind: kind, provider: TaskWidgetProvider()) { entry in
//             TaskListWidgetView(entry: entry)
//                 .containerBackground(.fill.tertiary, for: .widget)
//         }
//         .configurationDisplayName("Task List")
//         .description("View your upcoming tasks")
//         .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
//     }
// }

// MARK: - Preview

struct WidgetSharedPreview: View {
    var body: some View {
        List {
            Section("Widget Entry") {
                LabeledContent("TaskWidgetEntry") {
                    Text("TimelineEntry")
                        .font(.caption.monospaced())
                }
                LabeledContent("TaskWidgetData") {
                    Text("Codable, Sendable")
                        .font(.caption.monospaced())
                }
                LabeledContent("TaskWidgetStats") {
                    Text("Codable, Sendable")
                        .font(.caption.monospaced())
                }
            }

            Section("Timeline Provider") {
                LabeledContent("TaskWidgetProvider") {
                    Text("TimelineProvider")
                        .font(.caption.monospaced())
                }
            }

            Section("Widget Views") {
                Text("Small, Medium, Large sizes supported")
                    .font(.caption)
            }

            Section {
                Text("To add widgets:\n1. File > New > Target\n2. Choose Widget Extension\n3. Add this file to widget target")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Widget Setup")
    }
}

#Preview("Widget Setup Guide") {
    NavigationStack {
        WidgetSharedPreview()
    }
}
