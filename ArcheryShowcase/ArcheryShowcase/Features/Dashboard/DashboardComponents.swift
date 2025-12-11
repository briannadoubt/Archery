import SwiftUI
import Archery

// MARK: - Welcome Header

struct WelcomeHeaderView: View {
    let taskCount: Int
    let completedToday: Int

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(greeting)
                    .font(.title2)
                    .fontWeight(.semibold)

                Text("Demo User")
                    .font(.title)
                    .fontWeight(.bold)

                if taskCount > 0 {
                    Text("\(taskCount) tasks, \(completedToday) completed")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            ProgressRing(completed: completedToday, total: taskCount)
        }
    }

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 0..<12: return "Good Morning"
        case 12..<17: return "Good Afternoon"
        default: return "Good Evening"
        }
    }
}

// MARK: - Progress Ring

struct ProgressRing: View {
    let completed: Int
    let total: Int

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.gray.opacity(0.2), lineWidth: 6)

            Circle()
                .trim(from: 0, to: total > 0 ? CGFloat(completed) / CGFloat(total) : 0)
                .stroke(Color.green, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                .rotationEffect(.degrees(-90))

            Image(systemName: "checkmark")
                .font(.title3.bold())
                .foregroundStyle(.green)
        }
        .frame(width: 50, height: 50)
    }
}

// MARK: - Navigation Stats View

struct NavigationStatsView: View {
    let total: Int
    let completed: Int
    let inProgress: Int
    let overdue: Int
    let projects: Int

    @Environment(\.navigationHandle) private var nav

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
            TappableStatCard(title: "Total Tasks", value: "\(total)", icon: "checklist", color: .blue) {
                nav?.navigate(to: DashboardRoute.filteredTasks(filter: .all), style: .sheet())
            }

            TappableStatCard(title: "Completed", value: "\(completed)", icon: "checkmark.circle.fill", color: .green) {
                nav?.navigate(to: DashboardRoute.filteredTasks(filter: .completed), style: .sheet())
            }

            TappableStatCard(title: "In Progress", value: "\(inProgress)", icon: "clock.fill", color: .orange, badge: overdue > 0 ? overdue : nil) {
                nav?.navigate(to: DashboardRoute.filteredTasks(filter: .incomplete), style: .sheet())
            }

            TappableStatCard(title: "Projects", value: "\(projects)", icon: "folder.fill", color: .purple) {
                nav?.navigate(to: DashboardRoute.stats, style: .push)
            }
        }
    }
}

// MARK: - Tappable Stat Card

struct TappableStatCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    var badge: Int? = nil
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: icon)
                        .foregroundStyle(color)
                    Spacer()
                    if let badge, badge > 0 {
                        Text("\(badge)")
                            .font(.caption2.bold())
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.red)
                            .clipShape(Capsule())
                    }
                }

                Text(value)
                    .font(.title)
                    .fontWeight(.bold)
                    .foregroundStyle(.primary)

                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding()
        }
        .buttonStyle(StatCardButtonStyle(color: color))
    }
}

struct StatCardButtonStyle: ButtonStyle {
    let color: Color

    func makeBody(configuration: ButtonStyleConfiguration) -> some View {
        configuration.label
            .background(color.opacity(configuration.isPressed ? 0.2 : 0.1))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.easeInOut(duration: 0.15), value: configuration.isPressed)
    }
}

// MARK: - Badge View

struct Badge: View {
    let count: Int

    var body: some View {
        Text("\(count)")
            .font(.caption2)
            .fontWeight(.bold)
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.red)
            .clipShape(Capsule())
            .offset(x: 8, y: -8)
    }
}
