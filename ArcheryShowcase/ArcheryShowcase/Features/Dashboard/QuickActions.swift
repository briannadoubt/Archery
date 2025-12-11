import SwiftUI
import AppIntents
import Archery

// MARK: - Navigation Quick Actions

struct NavigationQuickActionsView: View {
    @Environment(\.navigationHandle) private var nav

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Quick Actions")
                .font(.headline)

            HStack(spacing: 16) {
                QuickActionButton(title: "New Task", icon: "plus.circle.fill", color: .blue) {
                    nav?.navigate(to: DashboardRoute.newTask, style: .sheet())
                }

                QuickActionButton(title: "Stats", icon: "chart.bar.fill", color: .green) {
                    nav?.navigate(to: DashboardRoute.stats, style: .push)
                }

                QuickActionButton(title: "Activity", icon: "clock.fill", color: .orange) {
                    nav?.navigate(to: DashboardRoute.activity, style: .push)
                }

                QuickActionButton(title: "Alerts", icon: "bell.fill", color: .purple) {
                    nav?.navigate(to: DashboardRoute.notifications, style: .sheet())
                }
            }
        }
    }
}

// MARK: - Quick Action Button

struct QuickActionButton: View {
    let title: String
    let icon: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundStyle(color)

                Text(title)
                    .font(.caption)
                    .foregroundStyle(.primary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }
}

// MARK: - Quick Action Intent Button

struct QuickActionIntentButton<Intent: AppIntent>: View {
    let title: String
    let icon: String
    let color: Color
    let intent: Intent

    var body: some View {
        Button(intent: intent) {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundStyle(color)

                Text(title)
                    .font(.caption)
                    .foregroundStyle(.primary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }
}
