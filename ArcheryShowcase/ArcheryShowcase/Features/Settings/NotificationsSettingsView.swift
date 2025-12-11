import SwiftUI

struct NotificationsSettingsView: View {
    @State private var pushEnabled = true
    @State private var taskReminders = true
    @State private var dailySummary = false
    @State private var weeklyReport = true

    var body: some View {
        Form {
            Section("Push Notifications") {
                Toggle("Enable Notifications", isOn: $pushEnabled)
            }

            Section("Reminders") {
                Toggle("Task Reminders", isOn: $taskReminders)
                    .disabled(!pushEnabled)
                Toggle("Daily Summary", isOn: $dailySummary)
                    .disabled(!pushEnabled)
                Toggle("Weekly Report", isOn: $weeklyReport)
                    .disabled(!pushEnabled)
            }

            Section {
                Text("Manage notification permissions in System Settings.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Notifications")
    }
}

#Preview {
    NavigationStack {
        NotificationsSettingsView()
    }
}
