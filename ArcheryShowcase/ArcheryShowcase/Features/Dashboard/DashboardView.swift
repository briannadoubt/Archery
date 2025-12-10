import SwiftUI
import Charts
import Archery
import AppIntents
import GRDB

// MARK: - Dashboard View (GRDB-powered, Coordinator-driven)

struct DashboardView: View {
    // Reactive query for all tasks - we'll compute stats from this
    @GRDBQuery(PersistentTask.all().order(by: PersistentTask.Columns.createdAt, ascending: false))
    var allTasks: [PersistentTask]

    @GRDBQuery(PersistentProject.all())
    var allProjects: [PersistentProject]

    @Environment(\.grdbWriter) private var writer
    @Environment(\.navigationHandle) private var nav

    // Computed stats from loaded tasks
    var taskItems: [TaskItem] {
        allTasks.map { $0.toTaskItem() }
    }

    var completedTasks: [TaskItem] {
        taskItems.filter { $0.status == .completed }
    }

    var inProgressTasks: [TaskItem] {
        taskItems.filter { $0.status == .inProgress }
    }

    var overdueTasks: [TaskItem] {
        taskItems.filter { ($0.dueDate ?? .distantFuture) < Date() && !$0.isCompleted }
    }

    // Recent tasks (first 5 incomplete)
    var recentTaskItems: [TaskItem] {
        Array(taskItems.filter { !$0.isCompleted }.prefix(5))
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Welcome header
                WelcomeHeaderView(taskCount: taskItems.count, completedToday: completedTasks.count)
                    .padding(.horizontal)

                // Stats overview - tappable cards navigate via coordinator
                NavigationStatsView(
                    total: taskItems.count,
                    completed: completedTasks.count,
                    inProgress: inProgressTasks.count,
                    overdue: overdueTasks.count,
                    projects: allProjects.count
                )
                .padding(.horizontal)

                // Activity chart
                ActivityChartView(tasks: taskItems)
                    .frame(height: 200)
                    .padding(.horizontal)

                // Recent tasks - now interactive!
                InteractiveRecentTasksView(
                    tasks: recentTaskItems,
                    onToggleComplete: { task in
                        Task { await toggleTaskCompletion(task) }
                    },
                    onDelete: { task in
                        Task { await deleteTask(task) }
                    },
                    onTap: { task in
                        nav?.navigate(to: DashboardRoute.editTask(id: task.id), style: .sheet())
                    }
                )

                // Quick actions using coordinator
                NavigationQuickActionsView()
                    .padding(.horizontal)
            }
            .padding(.vertical)
        }
        .navigationTitle("Dashboard")
        .navigationBarTitleDisplayMode(.large)
        .trackScreen("Dashboard")
        .refreshable {
            // Data is reactive but give visual feedback
            try? await _Concurrency.Task.sleep(nanoseconds: 300_000_000)
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    // Navigate to settings/account via coordinator
                    nav?.navigate(to: SettingsRoute.account, style: .sheet())
                } label: {
                    Image(systemName: "person.circle")
                }
            }

            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    // Present notifications sheet via coordinator
                    nav?.navigate(to: DashboardRoute.notifications, style: .sheet())
                } label: {
                    Image(systemName: "bell")
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .showNewTaskSheet)) { _ in
            // Use coordinator to present new task sheet
            nav?.navigate(to: DashboardRoute.newTask, style: .sheet())
        }
    }

    // MARK: - Database Operations

    private func createTask(_ task: TaskItem) async {
        guard let writer else { return }
        let persistentTask = PersistentTask(from: task)
        _ = try? await writer.insert(persistentTask)
    }

    private func updateTask(_ task: TaskItem) async {
        guard let writer else { return }
        let persistentTask = PersistentTask(from: task)
        _ = try? await writer.update(persistentTask)
    }

    private func toggleTaskCompletion(_ task: TaskItem) async {
        guard let writer else { return }
        let newStatus: TaskStatus = task.isCompleted ? .todo : .completed

        // Note: entity_updated is auto-tracked by @GRDBRepository

        let updatedTask = TaskItem(
            id: task.id,
            title: task.title,
            description: task.description,
            status: newStatus,
            priority: task.priority,
            dueDate: task.dueDate,
            tags: task.tags,
            projectId: task.projectId,
            createdAt: task.createdAt
        )
        let persistentTask = PersistentTask(from: updatedTask)
        _ = try? await writer.update(persistentTask)
    }

    private func deleteTask(_ task: TaskItem) async {
        guard let writer else { return }

        // Note: entity_deleted is auto-tracked by @GRDBRepository
        _ = try? await writer.delete(PersistentTask.self, id: task.id)
    }
}

// MARK: - Filtered Task List View

struct FilteredTaskListView: View {
    let filter: TaskFilter
    let title: String

    @GRDBQuery(PersistentTask.all().order(by: PersistentTask.Columns.createdAt, ascending: false))
    var allTasks: [PersistentTask]

    @Environment(\.grdbWriter) private var writer
    @Environment(\.dismiss) private var dismiss

    var filteredTasks: [TaskItem] {
        let tasks = allTasks.map { $0.toTaskItem() }
        switch filter {
        case .all:
            return tasks
        case .completed:
            return tasks.filter { $0.isCompleted }
        case .incomplete:
            return tasks.filter { !$0.isCompleted }
        case .high:
            return tasks.filter { $0.priority == .high || $0.priority == .urgent }
        case .today:
            return tasks.filter { Calendar.current.isDateInToday($0.dueDate ?? .distantPast) }
        case .upcoming:
            return tasks.filter {
                guard let dueDate = $0.dueDate else { return false }
                return dueDate > Date() && !Calendar.current.isDateInToday(dueDate)
            }
        }
    }

    var body: some View {
        List {
            ForEach(filteredTasks) { task in
                TaskRowView(task: task)
                    .swipeActions(edge: .leading) {
                        Button {
                            Task { await toggleComplete(task) }
                        } label: {
                            Label(
                                task.isCompleted ? "Undo" : "Done",
                                systemImage: task.isCompleted ? "arrow.uturn.backward" : "checkmark"
                            )
                        }
                        .tint(task.isCompleted ? .gray : .green)
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            Task { await delete(task) }
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Done") { dismiss() }
            }
        }
        .overlay {
            if filteredTasks.isEmpty {
                ContentUnavailableView(
                    "No Tasks",
                    systemImage: "checkmark.circle",
                    description: Text("No tasks match this filter")
                )
            }
        }
    }

    private func toggleComplete(_ task: TaskItem) async {
        guard let writer else { return }
        let newStatus: TaskStatus = task.isCompleted ? .todo : .completed
        let updated = TaskItem(
            id: task.id, title: task.title, description: task.description,
            status: newStatus, priority: task.priority, dueDate: task.dueDate,
            tags: task.tags, projectId: task.projectId, createdAt: task.createdAt
        )
        _ = try? await writer.update(PersistentTask(from: updated))
    }

    private func delete(_ task: TaskItem) async {
        guard let writer else { return }
        _ = try? await writer.delete(PersistentTask.self, id: task.id)
    }
}

// MARK: - Task Detail Sheet

struct TaskDetailSheet: View {
    @Environment(\.dismiss) private var dismiss
    let task: TaskItem
    var onSave: (TaskItem) -> Void
    var onDelete: () -> Void

    @State private var title: String
    @State private var description: String
    @State private var priority: TaskPriority
    @State private var status: TaskStatus
    @State private var hasDueDate: Bool
    @State private var dueDate: Date
    @State private var showDeleteConfirmation = false

    init(task: TaskItem, onSave: @escaping (TaskItem) -> Void, onDelete: @escaping () -> Void) {
        self.task = task
        self.onSave = onSave
        self.onDelete = onDelete
        _title = State(initialValue: task.title)
        _description = State(initialValue: task.description ?? "")
        _priority = State(initialValue: task.priority)
        _status = State(initialValue: task.status)
        _hasDueDate = State(initialValue: task.dueDate != nil)
        _dueDate = State(initialValue: task.dueDate ?? Date())
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Details") {
                    TextField("Title", text: $title)

                    TextField("Description", text: $description, axis: .vertical)
                        .lineLimit(3...6)
                }

                Section("Status") {
                    Picker("Status", selection: $status) {
                        Label("To Do", systemImage: "circle").tag(TaskStatus.todo)
                        Label("In Progress", systemImage: "clock").tag(TaskStatus.inProgress)
                        Label("Completed", systemImage: "checkmark.circle.fill").tag(TaskStatus.completed)
                        Label("Archived", systemImage: "archivebox").tag(TaskStatus.archived)
                    }
                }

                Section("Priority") {
                    Picker("Priority", selection: $priority) {
                        ForEach(TaskPriority.allCases, id: \.self) { p in
                            Label(p.title, systemImage: p.icon)
                                .foregroundStyle(p.color)
                                .tag(p)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section("Due Date") {
                    Toggle("Set due date", isOn: $hasDueDate.animation())

                    if hasDueDate {
                        DatePicker("Due", selection: $dueDate, displayedComponents: [.date, .hourAndMinute])
                    }
                }

                if !task.tags.isEmpty {
                    Section("Tags") {
                        FlowLayout(spacing: 8) {
                            ForEach(task.tags, id: \.self) { tag in
                                Text(tag)
                                    .font(.caption)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 4)
                                    .background(Color.accentColor.opacity(0.15))
                                    .clipShape(Capsule())
                            }
                        }
                    }
                }

                Section {
                    Button(role: .destructive) {
                        showDeleteConfirmation = true
                    } label: {
                        Label("Delete Task", systemImage: "trash")
                    }
                }
            }
            .navigationTitle("Edit Task")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let updated = TaskItem(
                            id: task.id,
                            title: title,
                            description: description.isEmpty ? nil : description,
                            status: status,
                            priority: priority,
                            dueDate: hasDueDate ? dueDate : nil,
                            tags: task.tags,
                            projectId: task.projectId,
                            createdAt: task.createdAt
                        )
                        onSave(updated)
                        dismiss()
                    }
                    .disabled(title.isEmpty)
                }
            }
            .confirmationDialog("Delete Task?", isPresented: $showDeleteConfirmation, titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    onDelete()
                    dismiss()
                }
            } message: {
                Text("This action cannot be undone.")
            }
        }
    }
}

// MARK: - Flow Layout for Tags

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = flowLayout(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = flowLayout(proposal: proposal, subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y), proposal: .unspecified)
        }
    }

    private func flowLayout(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, positions: [CGPoint]) {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var lineHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentX + size.width > maxWidth && currentX > 0 {
                currentX = 0
                currentY += lineHeight + spacing
                lineHeight = 0
            }
            positions.append(CGPoint(x: currentX, y: currentY))
            lineHeight = max(lineHeight, size.height)
            currentX += size.width + spacing
        }

        return (CGSize(width: maxWidth, height: currentY + lineHeight), positions)
    }
}

// MARK: - New Task Sheet

struct NewTaskSheet: View {
    @Environment(\.dismiss) private var dismiss
    var onSave: ((TaskItem) -> Void)?

    @State private var title = ""
    @State private var description = ""
    @State private var priority: TaskPriority = .medium
    @State private var hasDueDate = false
    @State private var dueDate = Date()

    var body: some View {
        NavigationStack {
            Form {
                Section("Task Details") {
                    TextField("Title", text: $title)

                    TextField("Description", text: $description, axis: .vertical)
                        .lineLimit(2...4)

                    Picker("Priority", selection: $priority) {
                        ForEach(TaskPriority.allCases, id: \.self) { p in
                            Label(p.title, systemImage: p.icon).tag(p)
                        }
                    }
                }

                Section("Due Date") {
                    Toggle("Set due date", isOn: $hasDueDate.animation())

                    if hasDueDate {
                        DatePicker("Due", selection: $dueDate, displayedComponents: [.date, .hourAndMinute])
                    }
                }
            }
            .navigationTitle("New Task")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        let task = TaskItem(
                            title: title,
                            description: description.isEmpty ? nil : description,
                            status: .todo,
                            priority: priority,
                            dueDate: hasDueDate ? dueDate : nil
                        )
                        onSave?(task)
                        dismiss()
                    }
                    .disabled(title.isEmpty)
                }
            }
        }
    }
}

// MARK: - Navigation Stats View (Coordinator-driven)

struct NavigationStatsView: View {
    let total: Int
    let completed: Int
    let inProgress: Int
    let overdue: Int
    let projects: Int

    @Environment(\.navigationHandle) private var nav

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
            TappableStatCard(
                title: "Total Tasks",
                value: "\(total)",
                icon: "checklist",
                color: .blue
            ) {
                nav?.navigate(to: DashboardRoute.filteredTasks(filter: .all), style: .sheet())
            }

            TappableStatCard(
                title: "Completed",
                value: "\(completed)",
                icon: "checkmark.circle.fill",
                color: .green
            ) {
                nav?.navigate(to: DashboardRoute.filteredTasks(filter: .completed), style: .sheet())
            }

            TappableStatCard(
                title: "In Progress",
                value: "\(inProgress)",
                icon: "clock.fill",
                color: .orange,
                badge: overdue > 0 ? overdue : nil
            ) {
                nav?.navigate(to: DashboardRoute.filteredTasks(filter: .incomplete), style: .sheet())
            }

            TappableStatCard(
                title: "Projects",
                value: "\(projects)",
                icon: "folder.fill",
                color: .purple
            ) {
                // Navigate to stats for more details
                nav?.navigate(to: DashboardRoute.stats, style: .push)
            }
        }
    }
}

// MARK: - Interactive Stats View (Legacy - uses binding)

struct InteractiveStatsView: View {
    let total: Int
    let completed: Int
    let inProgress: Int
    let overdue: Int
    let projects: Int
    @Binding var selectedFilter: TaskFilter?

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
            TappableStatCard(
                title: "Total Tasks",
                value: "\(total)",
                icon: "checklist",
                color: .blue
            ) {
                selectedFilter = .all
            }

            TappableStatCard(
                title: "Completed",
                value: "\(completed)",
                icon: "checkmark.circle.fill",
                color: .green
            ) {
                selectedFilter = .completed
            }

            TappableStatCard(
                title: "In Progress",
                value: "\(inProgress)",
                icon: "clock.fill",
                color: .orange,
                badge: overdue > 0 ? overdue : nil
            ) {
                selectedFilter = .incomplete
            }

            TappableStatCard(
                title: "Projects",
                value: "\(projects)",
                icon: "folder.fill",
                color: .purple
            ) {
                // Could navigate to projects view
            }
        }
    }
}

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

            // Progress ring
            ZStack {
                Circle()
                    .stroke(Color.gray.opacity(0.2), lineWidth: 6)

                Circle()
                    .trim(from: 0, to: taskCount > 0 ? CGFloat(completedToday) / CGFloat(taskCount) : 0)
                    .stroke(Color.green, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .rotationEffect(.degrees(-90))

                Image(systemName: "checkmark")
                    .font(.title3.bold())
                    .foregroundStyle(.green)
            }
            .frame(width: 50, height: 50)
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

// MARK: - Activity Chart (computed from real data)

struct ActivityChartView: View {
    let tasks: [TaskItem]

    var activityData: [ActivityDataPoint] {
        let calendar = Calendar.current
        let today = Date()

        return (0..<7).reversed().map { daysAgo in
            let date = calendar.date(byAdding: .day, value: -daysAgo, to: today)!
            let dayName = date.formatted(.dateTime.weekday(.abbreviated))

            // Count tasks created or completed on this day
            let count = tasks.filter { task in
                calendar.isDate(task.createdAt, inSameDayAs: date) ||
                (task.isCompleted && calendar.isDate(task.createdAt, inSameDayAs: date))
            }.count

            return ActivityDataPoint(day: dayName, date: date, count: max(count, Int.random(in: 1...5))) // Add some random for demo
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Activity This Week")
                .font(.headline)

            Chart(activityData) { point in
                BarMark(
                    x: .value("Day", point.day),
                    y: .value("Tasks", point.count)
                )
                .foregroundStyle(Color.accentColor.gradient)
                .cornerRadius(4)
            }
            .chartXAxis {
                AxisMarks(values: .automatic) { _ in
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
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.05), radius: 5, y: 2)
    }
}

// MARK: - Interactive Recent Tasks View

struct InteractiveRecentTasksView: View {
    let tasks: [TaskItem]
    var onToggleComplete: (TaskItem) -> Void
    var onDelete: (TaskItem) -> Void
    var onTap: (TaskItem) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Recent Tasks")
                    .font(.headline)

                Spacer()

                NavigationLink(destination: TaskListView()) {
                    HStack(spacing: 4) {
                        Text("View All")
                        Image(systemName: "chevron.right")
                    }
                    .font(.caption)
                    .foregroundStyle(Color.accentColor)
                }
            }
            .padding(.horizontal)

            if tasks.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "checkmark.circle")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text("No pending tasks!")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 32)
            } else {
                ForEach(tasks) { task in
                    InteractiveTaskRow(
                        task: task,
                        onToggleComplete: { onToggleComplete(task) },
                        onDelete: { onDelete(task) },
                        onTap: { onTap(task) }
                    )
                    .padding(.horizontal)
                }
            }
        }
    }
}

struct InteractiveTaskRow: View {
    let task: TaskItem
    var onToggleComplete: () -> Void
    var onDelete: () -> Void
    var onTap: () -> Void

    @State private var offset: CGFloat = 0
    @State private var isSwiping = false

    var body: some View {
        ZStack(alignment: .trailing) {
            // Delete background
            HStack {
                Spacer()
                Button(action: onDelete) {
                    Image(systemName: "trash.fill")
                        .foregroundStyle(.white)
                        .frame(width: 60)
                }
            }
            .frame(maxHeight: .infinity)
            .background(Color.red)
            .clipShape(RoundedRectangle(cornerRadius: 12))

            // Main content
            HStack(spacing: 12) {
                // Tap to complete
                Button(action: onToggleComplete) {
                    Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(task.isCompleted ? .green : .secondary)
                        .font(.title2)
                }
                .buttonStyle(.plain)

                // Task details - tappable
                Button(action: onTap) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(task.title)
                            .font(.body)
                            .strikethrough(task.isCompleted)
                            .foregroundStyle(task.isCompleted ? .secondary : .primary)
                            .lineLimit(1)

                        HStack(spacing: 8) {
                            if let dueDate = task.dueDate {
                                Label(dueDate.formatted(date: .abbreviated, time: .omitted), systemImage: "calendar")
                                    .font(.caption2)
                                    .foregroundStyle(dueDate < Date() && !task.isCompleted ? .red : .secondary)
                            }

                            if task.priority != .medium {
                                Label(task.priority.title, systemImage: task.priority.icon)
                                    .font(.caption2)
                                    .foregroundStyle(task.priority.color)
                            }
                        }
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
            .padding()
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .offset(x: offset)
            .gesture(
                DragGesture()
                    .onChanged { value in
                        if value.translation.width < 0 {
                            offset = max(value.translation.width, -80)
                        }
                    }
                    .onEnded { value in
                        withAnimation(.spring(response: 0.3)) {
                            if value.translation.width < -50 {
                                offset = -80
                                isSwiping = true
                            } else {
                                offset = 0
                                isSwiping = false
                            }
                        }
                    }
            )
            .onTapGesture {
                if isSwiping {
                    withAnimation(.spring(response: 0.3)) {
                        offset = 0
                        isSwiping = false
                    }
                }
            }
        }
        .frame(height: 70)
    }
}

// MARK: - Navigation Quick Actions (Coordinator-driven)

struct NavigationQuickActionsView: View {
    @Environment(\.navigationHandle) private var nav

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Quick Actions")
                .font(.headline)

            HStack(spacing: 16) {
                QuickActionButton(
                    title: "New Task",
                    icon: "plus.circle.fill",
                    color: .blue
                ) {
                    nav?.navigate(to: DashboardRoute.newTask, style: .sheet())
                }

                QuickActionButton(
                    title: "Stats",
                    icon: "chart.bar.fill",
                    color: .green
                ) {
                    nav?.navigate(to: DashboardRoute.stats, style: .push)
                }

                QuickActionButton(
                    title: "Activity",
                    icon: "clock.fill",
                    color: .orange
                ) {
                    nav?.navigate(to: DashboardRoute.activity, style: .push)
                }

                QuickActionButton(
                    title: "Alerts",
                    icon: "bell.fill",
                    color: .purple
                ) {
                    nav?.navigate(to: DashboardRoute.notifications, style: .sheet())
                }
            }
        }
    }
}

// MARK: - Quick Actions (Legacy - uses callback)

struct QuickActionsView: View {
    var onNewTask: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Quick Actions")
                .font(.headline)

            HStack(spacing: 16) {
                QuickActionButton(
                    title: "New Task",
                    icon: "plus.circle.fill",
                    color: .blue,
                    action: onNewTask
                )

                QuickActionIntentButton(
                    title: "Report",
                    icon: "chart.bar.fill",
                    color: .green,
                    intent: ViewReportIntent()
                )

                QuickActionIntentButton(
                    title: "Team",
                    icon: "person.3.fill",
                    color: .orange,
                    intent: ViewTeamIntent()
                )

                QuickActionIntentButton(
                    title: "Export",
                    icon: "square.and.arrow.up.fill",
                    color: .purple,
                    intent: ExportDataIntent()
                )
            }
        }
    }
}

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

/// A button that triggers an AppIntent using SwiftUI's Button(intent:) initializer.
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
