import SwiftUI
import Archery

struct DashboardActivityView: View {
    @Query(\.recent)
    var recentTasks: [TaskItem]

    var body: some View {
        List {
            Section("Recent Activity") {
                ForEach(recentTasks) { task in
                    ActivityRow(task: task)
                }
            }
        }
        .navigationTitle("Activity")
    }
}

private struct ActivityRow: View {
    let task: TaskItem

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(task.title)
                .fontWeight(.medium)
            HStack {
                Text(task.status.title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(task.createdAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 2)
    }
}

#Preview {
    NavigationStack {
        DashboardActivityView()
    }
}
