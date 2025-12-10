import Foundation
import SwiftUI
import Archery

// MARK: - Task Creation Flow Demo
//
// This file demonstrates the @Flow macro and FlowContainerView in action.
// The TaskCreationFlow is defined in ArcheryShowcaseApp.swift using @Flow.

// MARK: - Flow Host View

/// Hosts the task creation flow, managing state and step resolution
struct TaskCreationFlowHost: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.grdbWriter) private var writer

    @State private var flowState: FlowState
    @State private var flowData = TaskFlowData()

    init() {
        // Initialize with the TaskCreationFlow type
        _flowState = State(initialValue: FlowState(flowType: TaskCreationFlow.self))
    }

    var body: some View {
        NavigationStack {
            FlowContainerView(
                flowState: flowState,
                content: { currentStepView },
                onAdvance: { _ in advance() },
                onBack: { back() },
                onCancel: { dismiss() }
            )
            .navigationTitle(stepTitle)
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    @ViewBuilder
    private var currentStepView: some View {
        switch currentStep {
        case .basicInfo:
            TaskFlowBasicInfoStep(data: $flowData)
        case .scheduling:
            TaskFlowSchedulingStep(data: $flowData)
        case .priority:
            TaskFlowPriorityStep(data: $flowData)
        case .review:
            TaskFlowReviewStep(data: flowData, onComplete: completeFlow)
        }
    }

    private var currentStep: TaskCreationFlow {
        TaskCreationFlow.steps[flowState.currentStepIndex]
    }

    private var stepTitle: String {
        switch currentStep {
        case .basicInfo: return "Basic Info"
        case .scheduling: return "Schedule"
        case .priority: return "Priority"
        case .review: return "Review"
        }
    }

    private func advance() {
        guard flowState.canGoForward else {
            // Flow complete - should not happen, review step has its own complete button
            return
        }
        flowState.advance()
    }

    private func back() {
        flowState.back()
    }

    private func completeFlow() {
        // Create the task from collected data
        Task {
            guard let writer else { return }
            let taskItem = TaskItem(
                id: UUID().uuidString,
                title: flowData.title,
                description: flowData.description.isEmpty ? nil : flowData.description,
                status: .todo,
                priority: flowData.priority,
                dueDate: flowData.hasDueDate ? flowData.dueDate : nil,
                tags: flowData.tags,
                projectId: nil,
                createdAt: Date()
            )
            try? await writer.insert(PersistentTask(from: taskItem))
        }
        dismiss()
    }
}

// MARK: - Flow Data Model

struct TaskFlowData {
    var title: String = ""
    var description: String = ""
    var hasDueDate: Bool = false
    var dueDate: Date = Date().addingTimeInterval(86400) // Tomorrow
    var hasReminder: Bool = false
    var reminderDate: Date = Date().addingTimeInterval(82800) // Tomorrow - 1 hour
    var priority: TaskPriority = .medium
    var tags: [String] = []
    var tagInput: String = ""
}

// MARK: - Flow Step Views

struct TaskFlowBasicInfoStep: View {
    @Binding var data: TaskFlowData

    var body: some View {
        Form {
            Section {
                TextField("Task title", text: $data.title)
                    .font(.headline)

                TextField("Description (optional)", text: $data.description, axis: .vertical)
                    .lineLimit(3...6)
            } header: {
                Text("What needs to be done?")
            } footer: {
                Text("Give your task a clear, actionable title.")
            }
        }
    }
}

struct TaskFlowSchedulingStep: View {
    @Binding var data: TaskFlowData

    var body: some View {
        Form {
            Section {
                Toggle("Set due date", isOn: $data.hasDueDate.animation())

                if data.hasDueDate {
                    DatePicker(
                        "Due date",
                        selection: $data.dueDate,
                        in: Date()...,
                        displayedComponents: [.date, .hourAndMinute]
                    )
                }
            } header: {
                Text("When is it due?")
            }

            if data.hasDueDate {
                Section {
                    Toggle("Remind me", isOn: $data.hasReminder.animation())

                    if data.hasReminder {
                        DatePicker(
                            "Reminder",
                            selection: $data.reminderDate,
                            in: Date()...data.dueDate,
                            displayedComponents: [.date, .hourAndMinute]
                        )
                    }
                } header: {
                    Text("Reminders")
                }
            }
        }
    }
}

struct TaskFlowPriorityStep: View {
    @Binding var data: TaskFlowData

    var body: some View {
        Form {
            Section {
                ForEach(TaskPriority.allCases, id: \.self) { priority in
                    Button {
                        data.priority = priority
                    } label: {
                        HStack {
                            Image(systemName: priority.icon)
                                .foregroundStyle(priority.color)
                                .frame(width: 24)

                            VStack(alignment: .leading) {
                                Text(priority.title)
                                    .foregroundStyle(.primary)
                                Text(priorityDescription(for: priority))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            if data.priority == priority {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.tint)
                            }
                        }
                    }
                }
            } header: {
                Text("How important is this?")
            }

            Section {
                HStack {
                    TextField("Add tag", text: $data.tagInput)
                        .submitLabel(.done)
                        .onSubmit(addTag)

                    Button("Add", action: addTag)
                        .disabled(data.tagInput.isEmpty)
                }

                if !data.tags.isEmpty {
                    TagFlowLayout(spacing: 8) {
                        ForEach(data.tags, id: \.self) { tag in
                            TagChip(tag: tag) {
                                data.tags.removeAll { $0 == tag }
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            } header: {
                Text("Tags (optional)")
            }
        }
    }

    private func priorityDescription(for priority: TaskPriority) -> String {
        switch priority {
        case .low: return "Can wait, do when you have time"
        case .medium: return "Normal importance"
        case .high: return "Important, prioritize this"
        case .urgent: return "Critical, do this first"
        }
    }

    private func addTag() {
        let tag = data.tagInput.trimmingCharacters(in: .whitespaces)
        guard !tag.isEmpty, !data.tags.contains(tag) else { return }
        data.tags.append(tag)
        data.tagInput = ""
    }
}

struct TaskFlowReviewStep: View {
    let data: TaskFlowData
    let onComplete: () -> Void

    var body: some View {
        Form {
            Section("Task Details") {
                LabeledContent("Title", value: data.title)

                if !data.description.isEmpty {
                    LabeledContent("Description", value: data.description)
                }
            }

            Section("Schedule") {
                if data.hasDueDate {
                    LabeledContent("Due", value: data.dueDate.formatted(date: .abbreviated, time: .shortened))

                    if data.hasReminder {
                        LabeledContent("Reminder", value: data.reminderDate.formatted(date: .abbreviated, time: .shortened))
                    }
                } else {
                    Text("No due date set")
                        .foregroundStyle(.secondary)
                }
            }

            Section("Priority & Tags") {
                HStack {
                    Image(systemName: data.priority.icon)
                        .foregroundStyle(data.priority.color)
                    Text(data.priority.title)
                }

                if !data.tags.isEmpty {
                    HStack {
                        ForEach(data.tags, id: \.self) { tag in
                            Text(tag)
                                .font(.caption)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.accentColor.opacity(0.15))
                                .clipShape(Capsule())
                        }
                    }
                }
            }

            Section {
                Button(action: onComplete) {
                    HStack {
                        Spacer()
                        Label("Create Task", systemImage: "checkmark.circle.fill")
                            .font(.headline)
                        Spacer()
                    }
                }
                .buttonStyle(.borderedProminent)
                .listRowBackground(Color.clear)
            }
        }
    }
}

// MARK: - Helper Views

private struct TagChip: View {
    let tag: String
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            Text(tag)
                .font(.caption)
            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.caption)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.accentColor.opacity(0.15))
        .clipShape(Capsule())
    }
}

/// Simple flow layout for wrapping tags
private struct TagFlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = computeLayout(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = computeLayout(proposal: proposal, subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y), proposal: .unspecified)
        }
    }

    private func computeLayout(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, positions: [CGPoint]) {
        var positions: [CGPoint] = []
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var lineHeight: CGFloat = 0
        let maxWidth = proposal.width ?? .infinity

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)

            if currentX + size.width > maxWidth, currentX > 0 {
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

// MARK: - Preview

#Preview("Task Creation Flow") {
    TaskCreationFlowHost()
}
