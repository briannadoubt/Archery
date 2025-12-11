import SwiftUI

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
                EmptyTasksView()
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

// MARK: - Empty Tasks View

private struct EmptyTasksView: View {
    var body: some View {
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
    }
}

// MARK: - Interactive Task Row

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
            DeleteBackground(onDelete: onDelete)

            // Main content
            TaskRowContent(
                task: task,
                onToggleComplete: onToggleComplete,
                onTap: onTap
            )
            .offset(x: offset)
            .gesture(swipeGesture)
            .onTapGesture { resetSwipeIfNeeded() }
        }
        .frame(height: 70)
    }

    private var swipeGesture: some Gesture {
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
    }

    private func resetSwipeIfNeeded() {
        if isSwiping {
            withAnimation(.spring(response: 0.3)) {
                offset = 0
                isSwiping = false
            }
        }
    }
}

// MARK: - Delete Background

private struct DeleteBackground: View {
    let onDelete: () -> Void

    var body: some View {
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
    }
}

// MARK: - Task Row Content

private struct TaskRowContent: View {
    let task: TaskItem
    var onToggleComplete: () -> Void
    var onTap: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onToggleComplete) {
                Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(task.isCompleted ? .green : .secondary)
                    .font(.title2)
            }
            .buttonStyle(.plain)

            Button(action: onTap) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(task.title)
                        .font(.body)
                        .strikethrough(task.isCompleted)
                        .foregroundStyle(task.isCompleted ? .secondary : .primary)
                        .lineLimit(1)

                    TaskMetadata(task: task)
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
    }
}

// MARK: - Task Metadata

private struct TaskMetadata: View {
    let task: TaskItem

    var body: some View {
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
}
