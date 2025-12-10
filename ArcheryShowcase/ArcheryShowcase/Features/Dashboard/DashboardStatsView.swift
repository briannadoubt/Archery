import SwiftUI
import Archery
import GRDB

struct DashboardStatsView: View {
    @GRDBQuery(PersistentTask.all()) var allTasks: [PersistentTask]
    @GRDBQuery(PersistentProject.all()) var allProjects: [PersistentProject]

    var body: some View {
        List {
            Section("Task Statistics") {
                StatRow(label: "Total Tasks", value: "\(allTasks.count)", icon: "checklist", color: .blue)
                StatRow(label: "Completed", value: "\(completedCount)", icon: "checkmark.circle.fill", color: .green)
                StatRow(label: "In Progress", value: "\(inProgressCount)", icon: "clock.fill", color: .orange)
                StatRow(label: "Overdue", value: "\(overdueCount)", icon: "exclamationmark.triangle.fill", color: .red)
            }

            Section("Projects") {
                StatRow(label: "Total Projects", value: "\(allProjects.count)", icon: "folder.fill", color: .purple)
            }
        }
        .navigationTitle("Statistics")
    }

    private var completedCount: Int {
        allTasks.filter { $0.status == TaskStatus.completed.rawValue }.count
    }

    private var inProgressCount: Int {
        allTasks.filter { $0.status == TaskStatus.inProgress.rawValue }.count
    }

    private var overdueCount: Int {
        allTasks.filter { ($0.dueDate ?? .distantFuture) < Date() && $0.status != TaskStatus.completed.rawValue }.count
    }
}

struct StatRow: View {
    let label: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundStyle(color)
                .frame(width: 30)
            Text(label)
            Spacer()
            Text(value)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
        }
    }
}

#Preview {
    NavigationStack {
        DashboardStatsView()
    }
}
