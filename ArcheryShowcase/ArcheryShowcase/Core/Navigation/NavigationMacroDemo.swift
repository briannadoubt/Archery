import Foundation
import SwiftUI
import Archery

// MARK: - Navigation & Routing Showcase
//
// This file demonstrates the comprehensive navigation system with LIVE demos:
// - @Route(path:) for URL pattern matching
// - @requires(.entitlement) for case-level gating
// - @presents(.sheet/.fullScreen) for presentation styles
// - @Flow for multi-step wizard flows
// - Deep link composition
// - Recursive sheet presentations

struct NavigationShowcaseView: View {
    @StateObject private var store = StoreKitManager.shared
    @Environment(\.navigationHandle) private var nav

    var body: some View {
        List {
            // Overview
            Section {
                Text("Archery provides a comprehensive navigation system with recursive presentations, entitlement gating, flows, and auto-generated deep links.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // LIVE Presentation Demos
            Section("Live Presentation Demos") {
                // Sheet presentation
                Button {
                    nav?.navigate(to: DashboardRoute.notifications, style: .sheet(detents: [.medium, .large]))
                } label: {
                    LiveDemoRow(
                        icon: "rectangle.bottomhalf.inset.filled",
                        title: "Sheet with Detents",
                        subtitle: "@presents(.sheet, detents: [.medium, .large])"
                    )
                }

                // Full screen presentation
                Button {
                    nav?.navigate(to: TasksRoute.analytics, style: .fullScreen)
                } label: {
                    LiveDemoRow(
                        icon: "rectangle.inset.filled",
                        title: "Full Screen Modal",
                        subtitle: "@presents(.fullScreen) + @requires(.premium)",
                        isLocked: !store.hasEntitlement(.premium)
                    )
                }

                // Push navigation
                Button {
                    nav?.navigate(to: DashboardRoute.stats, style: .push)
                } label: {
                    LiveDemoRow(
                        icon: "arrow.right.square",
                        title: "Push Navigation",
                        subtitle: "Default presentation style"
                    )
                }
            }

            // LIVE Flow Demo
            Section("Live Flow Demo") {
                Button {
                    nav?.navigate(to: TasksRoute.taskWizard, style: .sheet(detents: [.large]))
                } label: {
                    LiveDemoRow(
                        icon: "rectangle.stack.badge.plus",
                        title: "Task Creation Wizard",
                        subtitle: "@Flow with 4 steps: basicInfo → scheduling → priority → review"
                    )
                }

                Text("The TaskCreationFlow uses @Flow macro with FlowState for step management, back/forward navigation, and data collection across steps.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // Recursive Sheet Demo
            Section("Recursive Sheets") {
                NavigationLink {
                    RecursiveSheetDemo()
                } label: {
                    LiveDemoRow(
                        icon: "square.stack.3d.up",
                        title: "Nested Sheet Demo",
                        subtitle: "Sheets can present other sheets via coordinator"
                    )
                }
            }

            // Deep Link Demo
            Section("Deep Link Patterns") {
                NavigationLink {
                    DeepLinkDemoView()
                } label: {
                    LiveDemoRow(
                        icon: "link",
                        title: "Deep Link Demo",
                        subtitle: "Test URL parsing and navigation"
                    )
                }
            }

            // Route Definitions with Live Status
            Section("App Routes (Live Status)") {
                RouteInfoRow(
                    name: "DashboardRoute",
                    path: "/dashboard/*",
                    cases: ["root", "stats", "activity", "notifications", "newTask", "filteredTasks", "editTask"],
                    requirement: "Free"
                )
                RouteInfoRow(
                    name: "TasksRoute",
                    path: "/tasks/*",
                    cases: ["root", "detail", "newTask", "taskWizard", "analytics*", "bulkEdit*"],
                    requirement: "Free (*premium/pro required)",
                    isPartiallyLocked: true
                )
                RouteInfoRow(
                    name: "InsightsRoute",
                    path: "/insights/*",
                    cases: ["root", "reports", "export"],
                    requirement: "Requires .premium",
                    isLocked: !store.hasEntitlement(.premium)
                )
                RouteInfoRow(
                    name: "AdminRoute",
                    path: "/admin/*",
                    cases: ["root", "users", "permissions"],
                    requirement: "Requires .pro",
                    isLocked: !store.hasEntitlement(.pro)
                )
            }

            // Live Entitlement Checking
            Section("Live Entitlement Check") {
                EntitlementCheckRow(
                    label: "TasksRoute.analytics",
                    requirement: TasksRoute.entitlementRequirement(for: .analytics),
                    store: store
                )
                EntitlementCheckRow(
                    label: "TasksRoute.bulkEdit",
                    requirement: TasksRoute.entitlementRequirement(for: .bulkEdit),
                    store: store
                )
                EntitlementCheckRow(
                    label: "InsightsRoute.root",
                    requirement: InsightsRoute.entitlementRequirement(for: .root),
                    store: store
                )
                EntitlementCheckRow(
                    label: "AdminRoute.root",
                    requirement: AdminRoute.entitlementRequirement(for: .root),
                    store: store
                )
            }

            // Presentation Style Lookup
            Section("@presents Style Lookup") {
                PresentationStyleInfoRow(
                    route: "TasksRoute.newTask",
                    style: TasksRoute.presentationStyle(for: .newTask)
                )
                PresentationStyleInfoRow(
                    route: "TasksRoute.analytics",
                    style: TasksRoute.presentationStyle(for: .analytics)
                )
                PresentationStyleInfoRow(
                    route: "DashboardRoute.notifications",
                    style: DashboardRoute.presentationStyle(for: .notifications)
                )
                PresentationStyleInfoRow(
                    route: "SettingsRoute.paywall",
                    style: SettingsRoute.presentationStyle(for: .paywall)
                )
            }

            // Code Examples
            Section("Implementation Examples") {
                CodeExampleRow(
                    title: "Route with @presents",
                    code: """
                    @Route(path: "tasks")
                    enum TasksRoute: NavigationRoute {
                        case root
                        case detail(id: String)

                        @presents(.sheet)
                        case newTask

                        @requires(.premium)
                        @presents(.fullScreen)
                        case analytics
                    }
                    """
                )

                CodeExampleRow(
                    title: "Flow definition",
                    code: """
                    @Flow(path: "taskCreation", persists: false)
                    enum TaskCreationFlow: CaseIterable, Hashable {
                        case basicInfo
                        case scheduling
                        case priority
                        case review
                    }
                    """
                )

                CodeExampleRow(
                    title: "Using NavigationHandle",
                    code: """
                    struct TasksView: View {
                        @Environment(\\.navigationHandle) var nav

                        var body: some View {
                            Button("Create Task") {
                                nav?.navigate(to: TasksRoute.newTask)
                            }
                            Button("Start Wizard") {
                                nav?.navigate(to: TasksRoute.taskWizard)
                            }
                        }
                    }
                    """
                )
            }
        }
        .navigationTitle("Navigation")
    }
}

// MARK: - Recursive Sheet Demo

struct RecursiveSheetDemo: View {
    @Environment(\.navigationHandle) private var nav
    @State private var sheetLevel = 0
    @State private var showSheet = false

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "square.stack.3d.up")
                .font(.system(size: 60))
                .foregroundStyle(.blue)

            Text("Recursive Sheet Demo")
                .font(.title2.weight(.semibold))

            Text("The coordinator supports stacked sheet presentations. Each sheet can present another sheet, and the coordinator tracks the stack depth.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Button("Open First Sheet") {
                sheetLevel = 1
                showSheet = true
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
        .navigationTitle("Recursive Sheets")
        .sheet(isPresented: $showSheet) {
            RecursiveSheetLevel(level: sheetLevel, onOpenNext: {
                sheetLevel += 1
            })
        }
    }
}

struct RecursiveSheetLevel: View {
    let level: Int
    let onOpenNext: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var showNestedSheet = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                ZStack {
                    ForEach(0..<level, id: \.self) { i in
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.blue.opacity(Double(level - i) / Double(level)), lineWidth: 2)
                            .frame(width: 100 + CGFloat(i * 20), height: 60 + CGFloat(i * 12))
                            .offset(y: CGFloat(i * -8))
                    }
                }
                .padding(.vertical, 20)

                Text("Sheet Level \(level)")
                    .font(.title.weight(.bold))

                Text("This sheet is at depth \(level) in the presentation stack.")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                if level < 4 {
                    Button("Open Level \(level + 1)") {
                        showNestedSheet = true
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    Text("Maximum depth reached")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
            .padding()
            .navigationTitle("Level \(level)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents(level == 1 ? [.medium, .large] : [.large])
        .sheet(isPresented: $showNestedSheet) {
            RecursiveSheetLevel(level: level + 1, onOpenNext: {})
        }
    }
}

// MARK: - Deep Link Demo

struct DeepLinkDemoView: View {
    @State private var urlInput = "archery://app/tasks/root"
    @State private var parseResult: String = ""

    let exampleURLs = [
        ("archery://app/tasks/root", "Tasks tab, list view"),
        ("archery://app/tasks/detail/abc123", "Task detail with ID"),
        ("archery://app/dashboard/stats", "Dashboard stats view"),
        ("archery://app/settings/paywall", "Show paywall"),
        ("archery://app/flow/taskCreation", "Start task creation flow"),
        ("archery://app/flow/taskCreation/step/priority", "Jump to priority step"),
    ]

    var body: some View {
        List {
            Section {
                Text("Deep links follow the pattern: {scheme}://{host}/{tab}/{route}[?present={style}]")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Try a URL") {
                TextField("Enter URL", text: $urlInput)
                    .textContentType(.URL)
                    .autocapitalization(.none)
                    .font(.system(.body, design: .monospaced))

                Button("Parse URL") {
                    parseURL()
                }
                .disabled(urlInput.isEmpty)

                if !parseResult.isEmpty {
                    Text(parseResult)
                        .font(.caption)
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(.secondarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
            }

            Section("Example URLs") {
                ForEach(exampleURLs, id: \.0) { url, description in
                    Button {
                        urlInput = url
                        parseURL()
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(url)
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundStyle(.blue)
                            Text(description)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Section("URL Components") {
                if let url = URL(string: urlInput) {
                    LabeledContent("Scheme", value: url.scheme ?? "nil")
                    LabeledContent("Host", value: url.host ?? "nil")
                    LabeledContent("Path", value: url.path)
                    if let query = url.query {
                        LabeledContent("Query", value: query)
                    }
                }
            }
        }
        .navigationTitle("Deep Links")
    }

    private func parseURL() {
        guard let url = URL(string: urlInput) else {
            parseResult = "Invalid URL format"
            return
        }

        let pathComponents = url.path.split(separator: "/").map(String.init)

        if pathComponents.isEmpty {
            parseResult = "No path components found"
            return
        }

        var result = "Parsed:\n"
        result += "- Tab/Route: \(pathComponents.first ?? "unknown")\n"

        if pathComponents.count > 1 {
            result += "- Case: \(pathComponents[1])\n"
        }

        if pathComponents.count > 2 {
            result += "- Parameters: \(pathComponents.dropFirst(2).joined(separator: ", "))\n"
        }

        if let query = url.query {
            result += "- Query: \(query)"
        }

        parseResult = result
    }
}

// MARK: - Supporting Views

private struct LiveDemoRow: View {
    let icon: String
    let title: String
    let subtitle: String
    var isLocked: Bool = false

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(isLocked ? Color.secondary : Color.blue)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(title)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(isLocked ? .secondary : .primary)

                    if isLocked {
                        Image(systemName: "lock.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
    }
}

private struct RouteInfoRow: View {
    let name: String
    let path: String
    let cases: [String]
    let requirement: String
    var isLocked: Bool = false
    var isPartiallyLocked: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(name)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(isLocked ? .secondary : .primary)

                Spacer()

                if isLocked {
                    Image(systemName: "lock.fill")
                        .foregroundStyle(.orange)
                } else if isPartiallyLocked {
                    Image(systemName: "lock.open.fill")
                        .foregroundStyle(.yellow)
                } else {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
            }

            Text(path)
                .font(.caption.monospaced())
                .foregroundStyle(.blue)

            Text("Cases: " + cases.joined(separator: ", "))
                .font(.caption2)
                .foregroundStyle(.secondary)

            Text(requirement)
                .font(.caption2)
                .foregroundStyle(isLocked ? .orange : (isPartiallyLocked ? .yellow : .green))
        }
        .padding(.vertical, 4)
    }
}

private struct EntitlementCheckRow: View {
    let label: String
    let requirement: EntitlementRequirement
    let store: StoreKitManager

    var body: some View {
        let satisfied = requirement.isSatisfied(by: store.entitlements)

        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.caption.monospaced())
                Text(requirement.displayDescription)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text(satisfied ? "Granted" : "Blocked")
                .font(.caption.weight(.medium))
                .foregroundStyle(satisfied ? .green : .orange)
        }
    }
}

private struct PresentationStyleInfoRow: View {
    let route: String
    let style: PresentationStyle

    var body: some View {
        HStack {
            Text(route)
                .font(.caption.monospaced())

            Spacer()

            Text(styleDescription)
                .font(.caption)
                .foregroundStyle(.blue)
        }
    }

    private var styleDescription: String {
        switch style {
        case .push: return ".push"
        case .replace: return ".replace"
        case .sheet(let detents):
            let detentNames = detents.map(\.rawValue).sorted().joined(separator: ", ")
            return ".sheet([\(detentNames)])"
        case .fullScreen: return ".fullScreen"
        case .popover: return ".popover"
        case .window(let id): return ".window(\(id))"
        case .tab(let index): return ".tab(\(index))"
        #if os(visionOS)
        case .immersiveSpace(let id, _): return ".immersive(\(id))"
        #endif
        #if os(macOS)
        case .settingsPane: return ".settings"
        case .inspector: return ".inspector"
        #endif
        }
    }
}

private struct CodeExampleRow: View {
    let title: String
    let code: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.weight(.medium))

            Text(code)
                .font(.system(size: 10, design: .monospaced))
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    NavigationStack {
        NavigationShowcaseView()
    }
}
