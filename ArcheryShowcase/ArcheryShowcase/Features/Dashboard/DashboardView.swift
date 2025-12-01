import SwiftUI
import Charts
import Archery

// MARK: - Dashboard View with Multiple ViewModels

@ViewModelBound(viewModel: DashboardViewModel.self)
struct DashboardView: View {
    @StateObject var vm: DashboardViewModel
    @EnvironmentObject var authManager: AuthManager
    @Environment(\.designTokens) var tokens
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: tokens.spacing.large) {
                    // Welcome header
                    WelcomeHeaderView(user: authManager.currentUser)
                        .padding(.horizontal)
                    
                    // Stats overview
                    StatsOverviewView(stats: vm.stats)
                        .padding(.horizontal)
                    
                    // Activity chart
                    if !vm.activityData.isEmpty {
                        ActivityChartView(data: vm.activityData)
                            .frame(height: 200)
                            .padding(.horizontal)
                    }
                    
                    // Recent tasks
                    RecentTasksView(tasks: vm.recentTasks)
                    
                    // Quick actions
                    QuickActionsView()
                        .padding(.horizontal)
                }
                .padding(.vertical)
            }
            .navigationTitle("Dashboard")
            .navigationBarTitleDisplayMode(.large)
            .refreshable {
                await vm.refresh()
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { vm.showingProfile = true }) {
                        Image(systemName: "person.circle")
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { vm.showingNotifications = true }) {
                        ZStack {
                            Image(systemName: "bell")
                            if vm.unreadNotifications > 0 {
                                Badge(count: vm.unreadNotifications)
                            }
                        }
                    }
                }
            }
            .sheet(isPresented: $vm.showingProfile) {
                ProfileView()
            }
            .sheet(isPresented: $vm.showingNotifications) {
                NotificationsView()
            }
            .task {
                await vm.load()
            }
        }
    }
}

// MARK: - Dashboard ViewModel

@ObservableViewModel
class DashboardViewModel: ObservableObject {
    @Published var stats: DashboardStats?
    @Published var activityData: [ActivityDataPoint] = []
    @Published var recentTasks: [Task] = []
    @Published var unreadNotifications = 0
    @Published var showingProfile = false
    @Published var showingNotifications = false
    @Published var isLoading = false
    @Published var error: Error?
    
    @Injected private var dashboardRepository: DashboardRepository
    @Injected private var taskRepository: TaskRepository
    @Injected private var notificationService: NotificationService
    @Injected private var analyticsService: AnalyticsService
    
    @MainActor
    func load() async {
        isLoading = true
        
        async let statsTask = loadStats()
        async let activityTask = loadActivity()
        async let tasksTask = loadRecentTasks()
        async let notificationsTask = loadNotifications()
        
        await (statsTask, activityTask, tasksTask, notificationsTask)
        
        isLoading = false
        
        // Track dashboard view
        analyticsService.track(.dashboardViewed)
    }
    
    @MainActor
    func refresh() async {
        await load()
    }
    
    private func loadStats() async {
        do {
            stats = try await dashboardRepository.getStats()
        } catch {
            self.error = error
        }
    }
    
    private func loadActivity() async {
        do {
            activityData = try await dashboardRepository.getActivityData(days: 7)
        } catch {
            self.error = error
        }
    }
    
    private func loadRecentTasks() async {
        do {
            recentTasks = try await taskRepository.getRecentTasks(limit: 5)
        } catch {
            self.error = error
        }
    }
    
    private func loadNotifications() async {
        unreadNotifications = await notificationService.getUnreadCount()
    }
}

// MARK: - Supporting Views

struct WelcomeHeaderView: View {
    let user: User?
    @Environment(\.designTokens) var tokens
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: tokens.spacing.small) {
                Text(greeting)
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Text(user?.name ?? "User")
                    .font(.title)
                    .fontWeight(.bold)
            }
            
            Spacer()
            
            AsyncImage(url: user?.avatar) { image in
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } placeholder: {
                Image(systemName: "person.circle.fill")
                    .font(.system(size: 50))
                    .foregroundStyle(.quaternary)
            }
            .frame(width: 60, height: 60)
            .clipShape(Circle())
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

struct StatsOverviewView: View {
    let stats: DashboardStats?
    @Environment(\.designTokens) var tokens
    
    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: tokens.spacing.medium) {
            StatCard(
                title: "Total Tasks",
                value: "\(stats?.totalTasks ?? 0)",
                icon: "checklist",
                color: .blue
            )
            
            StatCard(
                title: "Completed",
                value: "\(stats?.completedTasks ?? 0)",
                icon: "checkmark.circle.fill",
                color: .green
            )
            
            StatCard(
                title: "In Progress",
                value: "\(stats?.inProgressTasks ?? 0)",
                icon: "clock.fill",
                color: .orange
            )
            
            StatCard(
                title: "This Week",
                value: "\(stats?.thisWeekTasks ?? 0)",
                icon: "calendar",
                color: .purple
            )
        }
    }
}

struct StatCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    @Environment(\.designTokens) var tokens
    
    var body: some View {
        VStack(alignment: .leading, spacing: tokens.spacing.small) {
            HStack {
                Image(systemName: icon)
                    .foregroundStyle(color)
                Spacer()
            }
            
            Text(value)
                .font(.title)
                .fontWeight(.bold)
            
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(color.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: tokens.cornerRadius.medium))
    }
}

struct ActivityChartView: View {
    let data: [ActivityDataPoint]
    @Environment(\.designTokens) var tokens
    
    var body: some View {
        VStack(alignment: .leading, spacing: tokens.spacing.small) {
            Text("Activity This Week")
                .font(.headline)
            
            Chart(data) { point in
                BarMark(
                    x: .value("Day", point.day),
                    y: .value("Tasks", point.count)
                )
                .foregroundStyle(.accent.gradient)
                .cornerRadius(tokens.cornerRadius.small)
            }
            .chartXAxis {
                AxisMarks(values: .automatic) { value in
                    AxisValueLabel()
                        .font(.caption)
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading)
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: tokens.cornerRadius.medium))
        .shadow(color: .black.opacity(0.05), radius: 5, y: 2)
    }
}

struct RecentTasksView: View {
    let tasks: [Task]
    @Environment(\.designTokens) var tokens
    
    var body: some View {
        VStack(alignment: .leading, spacing: tokens.spacing.medium) {
            HStack {
                Text("Recent Tasks")
                    .font(.headline)
                
                Spacer()
                
                NavigationLink(destination: TaskListView()) {
                    Text("View All")
                        .font(.caption)
                        .foregroundStyle(.accent)
                }
            }
            .padding(.horizontal)
            
            ForEach(tasks) { task in
                TaskRowView(task: task)
                    .padding(.horizontal)
            }
        }
    }
}

struct QuickActionsView: View {
    @Environment(\.designTokens) var tokens
    
    var body: some View {
        VStack(alignment: .leading, spacing: tokens.spacing.medium) {
            Text("Quick Actions")
                .font(.headline)
            
            HStack(spacing: tokens.spacing.medium) {
                QuickActionButton(
                    title: "New Task",
                    icon: "plus.circle.fill",
                    color: .blue
                ) {
                    // Action
                }
                
                QuickActionButton(
                    title: "Report",
                    icon: "chart.bar.fill",
                    color: .green
                ) {
                    // Action
                }
                
                QuickActionButton(
                    title: "Team",
                    icon: "person.3.fill",
                    color: .orange
                ) {
                    // Action
                }
                
                QuickActionButton(
                    title: "Export",
                    icon: "square.and.arrow.up.fill",
                    color: .purple
                ) {
                    // Action
                }
            }
        }
    }
}

struct QuickActionButton: View {
    let title: String
    let icon: String
    let color: Color
    let action: () -> Void
    @Environment(\.designTokens) var tokens
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: tokens.spacing.small) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundStyle(color)
                
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.primary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, tokens.spacing.medium)
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: tokens.cornerRadius.medium))
        }
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