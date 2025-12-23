import SwiftUI

struct NotificationsView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            Section {
                NotificationRow(
                    title: "Task Due Soon",
                    message: "Complete project proposal by tomorrow",
                    icon: "clock.badge.exclamationmark",
                    color: .orange,
                    time: "2h ago"
                )
                NotificationRow(
                    title: "Task Completed",
                    message: "Design review has been marked as done",
                    icon: "checkmark.circle.fill",
                    color: .green,
                    time: "5h ago"
                )
                NotificationRow(
                    title: "New Comment",
                    message: "Alex commented on your task",
                    icon: "bubble.left.fill",
                    color: .blue,
                    time: "1d ago"
                )
            }
        }
        .navigationTitle("Notifications")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }
            }
        }
    }
}

// MARK: - Notification Row

struct NotificationRow: View {
    let title: String
    let message: String
    let icon: String
    let color: Color
    let time: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(color)
                .frame(width: 40)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .fontWeight(.medium)
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text(time)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    NavigationStack {
        NotificationsView()
    }
}
