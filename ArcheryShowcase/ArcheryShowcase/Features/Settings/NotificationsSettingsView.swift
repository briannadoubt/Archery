import SwiftUI

/// Notification preferences view using @KeyValueStore-backed SettingsManager.
struct NotificationsSettingsView: View {
    @ObservedObject private var settings = SettingsManager.shared

    @State private var pushEnabled = true
    @State private var taskReminders = true
    @State private var weeklyReport = true

    // Convert minutes from midnight to Date for DatePicker
    private var reminderTimeDate: Binding<Date> {
        Binding(
            get: {
                let calendar = Calendar.current
                let today = calendar.startOfDay(for: Date())
                return calendar.date(byAdding: .minute, value: settings.dailyReminderTime, to: today) ?? today
            },
            set: { newDate in
                let calendar = Calendar.current
                let components = calendar.dateComponents([.hour, .minute], from: newDate)
                let minutes = (components.hour ?? 0) * 60 + (components.minute ?? 0)
                settings.dailyReminderTime = minutes
            }
        )
    }

    var body: some View {
        Form {
            Section("Push Notifications") {
                Toggle("Enable Notifications", isOn: $pushEnabled)
            }

            Section("Reminders") {
                Toggle("Task Reminders", isOn: $taskReminders)
                    .disabled(!pushEnabled)

                Toggle("Daily Summary", isOn: $settings.dailyReminderEnabled)
                .disabled(!pushEnabled)

                if settings.dailyReminderEnabled && pushEnabled {
                    DatePicker(
                        "Summary Time",
                        selection: reminderTimeDate,
                        displayedComponents: .hourAndMinute
                    )
                }

                Toggle("Weekly Report", isOn: $weeklyReport)
                    .disabled(!pushEnabled)
            }

            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Settings saved with @KeyValueStore")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Text("Manage notification permissions in System Settings.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
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
