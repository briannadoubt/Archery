Recursive Navigation & Flow System Plan

Overview

Design a comprehensive navigation system that:
1. Scaffolds all routes with custom presentations via @AppShell macro
2. Supports multiple presentation styles (tabs, stacks, sheets, fullscreen, windows, immersive
spaces)
3. Defines "flows" that piece together multiple routes
4. Auto-generates composable deep links
5. Keeps features atomic and isolated from routing internals

---
Core Design Principles

1. Feature Isolation

Features receive a NavigationHandle - an opaque interface for requesting navigation actions.
Features never know:
- What tab they're in
- How they were presented (sheet vs push vs tab)
- The global route structure

Features only know:
- How to request "show X" or "dismiss"
- Their own route cases (for internal sub-navigation)

2. Recursive Presentation

Any route can present any other route with any presentation style. The presentation tree is:
App
├── Tab: Dashboard
│   └── Stack: [DashboardRoute]
│       └── Sheet: TaskDetail
│           └── Stack: [TaskDetailRoute]
│               └── FullScreen: ImageViewer
├── Tab: Tasks
│   └── Stack: [TasksRoute]
│       └── Sheet: EditTask (Flow)
│           └── Step 1: BasicInfo
│           └── Step 2: Priority
│           └── Step 3: Confirmation
└── Window: Settings (macOS)
    └── Stack: [SettingsRoute]

3. Composable Deep Links

Every presentation path generates a unique deep link:
- /dashboard → Dashboard tab
- /tasks/123 → Tasks tab, detail view
- /tasks/123/edit → Tasks tab, detail, edit sheet
- /flows/onboarding/step/2 → Onboarding flow at step 2

---
API Design

Route Definition with Presentation Metadata

@Route(path: "tasks")
enum TasksRoute: NavigationRoute {
    case list
    case detail(id: String)

    @presents(.sheet)
    case create

    @presents(.fullScreen)
    case bulkEdit

    @requires(.premium)
    @presents(.sheet, detents: [.medium, .large])
    case analytics
}

Flow Definition

@Flow(path: "onboarding", persists: true)  // Survives app termination
enum OnboardingFlow: NavigationFlow {
    // Steps execute in order
    case welcome           // Step 1
    case permissions       // Step 2
    case accountSetup      // Step 3
    case complete          // Final

    // Conditional branching - replaces accountSetup if condition met
    @branch(replacing: .accountSetup, when: .hasExistingAccount)
    case signIn

    // Skip conditions
    @skip(when: .permissionsAlreadyGranted)
    case permissions
}

@Flow(path: "checkout", persists: false)  // Always restarts
enum CheckoutFlow: NavigationFlow {
    case cart
    case shipping
    case payment

    @branch(replacing: .shipping, when: .digitalOnly)
    case digitalDelivery

    case confirmation
}

// Flow provides:
// - Automatic step tracking with back/forward
// - Conditional branching via @branch
// - Step skipping via @skip
// - Configurable persistence
// - Completion/cancellation callbacks
// - Deep link to any step

Feature View with Typed NavigationHandle

Each feature gets its own typed handle - features never see global routing:

// Generated per-feature handle protocol
@FeatureNavigation
protocol TasksNavigation {
    func showDetail(id: String)
    func showCreate()
    func showEdit(id: String)
    func showAnalytics()  // @requires checked at call site
    func dismiss()
    func popToRoot()
}

// Feature uses its own handle type
struct TaskDetailView: View {
    let task: Task
    @Environment(\.tasksNavigation) private var nav: any TasksNavigation

    var body: some View {
        VStack {
            // Feature doesn't know HOW edit is presented
            // Just calls typed method
            Button("Edit") {
                nav.showEdit(id: task.id)
            }

            Button("Back to List") {
                nav.popToRoot()
            }
        }
    }
}

// AppShell generates the concrete implementation
// that maps handle methods → actual routes + presentations

AppShell Configuration

@AppShell
@main
struct MyApp: App {
    enum Tab: CaseIterable {
        case dashboard
        case tasks

        @requires(.premium, behavior: .locked)
        case insights
    }

    // Scene definitions
    @Window(id: "settings")
    enum SettingsScene { case root }

    @ImmersiveSpace(id: "viewer", style: .mixed)  // visionOS
    enum ViewerScene { case model(id: String) }

    // Flow definitions
    @Flow
    enum Onboarding: OnboardingFlow { ... }

    // Route → View resolution
    static func resolve(_ route: TasksRoute) -> some View {
        switch route {
        case .list: TaskListView()
        case .detail(let id): TaskDetailView(id: id)
        case .create: TaskCreateView()
        // ...
        }
    }
}

---
Generated Infrastructure

NavigationHandle Protocol

@MainActor
public protocol NavigationHandle {
    /// Present a route (presentation style from route metadata)
    func present<R: NavigationRoute>(_ route: R)

    /// Present with explicit style override
    func present<R: NavigationRoute>(_ route: R, style: PresentationStyle)

    /// Dismiss current presentation
    func dismiss()

    /// Dismiss to root of current stack
    func popToRoot()

    /// Start a flow
    func startFlow<F: NavigationFlow>(_ flow: F.Type, from: F? = nil)

    /// Check if can navigate (entitlements, etc.)
    func canNavigate<R: NavigationRoute>(to route: R) -> Bool
}

PresentationStyle Enum

public enum PresentationStyle: Sendable {
    // Stack navigation
    case push
    case replace  // Replace current in stack

    // Modal
    case sheet(detents: Set<PresentationDetent> = [.large])
    case fullScreen
    case popover(attachmentAnchor: PopoverAttachmentAnchor = .rect(.bounds))

    // Scene (platform-specific)
    case window(id: String)
    case tab(Tab)

    #if os(visionOS)
    case immersiveSpace(id: String, style: ImmersiveSpaceStyle = .mixed)
    case ornament(edge: Edge)
    #endif

    #if os(macOS)
    case settingsPane
    case inspector
    #endif
}

NavigationCoordinator (Generated by @AppShell)

@MainActor
final class NavigationCoordinator: ObservableObject {
    // State
    @Published var selectedTab: Tab
    @Published var tabStacks: [Tab: NavigationPath]
    @Published var presentedSheet: AnyRoute?
    @Published var presentedFullScreen: AnyRoute?
    @Published var activeFlows: [String: FlowState]

    // Deep link registry
    private var deepLinkRouter: DeepLinkRouter<AnyRoute>

    // Navigation methods
    func navigate(to route: AnyRoute, style: PresentationStyle)
    func dismiss(levels: Int = 1)
    func switchTab(to: Tab, thenNavigate: [AnyRoute]?)

    // Flow management
    func startFlow<F: NavigationFlow>(_ type: F.Type)
    func advanceFlow(_ id: String)
    func cancelFlow(_ id: String)

    // Deep link handling
    func handle(url: URL) -> Bool
    func handle(userActivity: NSUserActivity) -> Bool

    // State persistence
    func persist()
    func restore()
}

Recursive Presentation View Modifier

Sheets stack naturally using iOS 16+ behavior:

extension View {
    func recursiveNavigation(
        coordinator: NavigationCoordinator,
        context: PresentationContext
    ) -> some View {
        self
            // Sheet stack - each sheet can present another sheet
            .sheet(item: coordinator.sheetBinding(for: context)) { route in
                coordinator.resolve(route)
                    .environment(\.navigationHandle, coordinator.makeHandle(for: .sheet))
                    .recursiveNavigation(coordinator: coordinator, context: .sheet(depth:
context.sheetDepth + 1))
            }
            // FullScreen presentations
            .fullScreenCover(item: coordinator.fullScreenBinding(for: context)) { route in
                coordinator.resolve(route)
                    .recursiveNavigation(coordinator: coordinator, context: .fullScreen)
            }
            // Inject typed handle based on context
            .environment(\.navigationHandle, coordinator.makeHandle(for: context))
    }
}

// Sheet stacking example:
// User flow: TaskList → TaskDetail (push) → Edit (sheet) → ImagePicker (sheet on sheet)
// Each sheet gets its own NavigationStack and can present further sheets

---
Flow System Design

NavigationFlow Protocol

public protocol NavigationFlow: CaseIterable, Hashable, Sendable {
    /// Path component for deep links
    static var flowPath: String { get }

    /// All steps in order
    static var steps: [Self] { get }

    /// Can skip from one step to another?
    func canSkip(to: Self) -> Bool

    /// Validate before advancing
    func validate() async -> Result<Void, FlowError>

    /// Deep link path for this step
    var stepPath: String { get }
}

FlowState

public struct FlowState: Identifiable {
    public let id: String
    public let flowType: any NavigationFlow.Type
    public var currentStep: Int
    public var data: [String: Any]  // Collected across steps
    public var history: [Int]       // For back navigation

    var canGoBack: Bool { !history.isEmpty }
    var canGoForward: Bool { currentStep < flowType.steps.count - 1 }
    var isComplete: Bool { currentStep >= flowType.steps.count - 1 }
}

Flow View Wrapper

struct FlowContainer<F: NavigationFlow>: View {
    @Environment(\.navigationHandle) private var nav
    @State private var state: FlowState

    var body: some View {
        NavigationStack {
            resolveCurrentStep()
                .toolbar {
                    if state.canGoBack {
                        Button("Back") { nav.flowBack() }
                    }
                    if state.canGoForward {
                        Button("Next") { nav.flowAdvance() }
                    }
                }
        }
    }
}

---
Deep Link Composition

Auto-Generated URL Structure

Deep links ALWAYS include explicit tab to avoid ambiguity:

{scheme}://{host}/{tab}/{route-path}[/{nested-route}][?present={style}]
{scheme}://{host}/flow/{flow-name}[/step/{step-name-or-index}]
{scheme}://{host}/scene/{scene-type}/{scene-id}[/{route}]

Examples:
myapp://app/tasks/list                    → Tasks tab, list view
myapp://app/tasks/detail/123              → Tasks tab, detail(id: "123")
myapp://app/tasks/detail/123/edit?present=sheet  → ... then present edit sheet
myapp://app/dashboard/stats?present=fullscreen   → Dashboard, stats fullscreen
myapp://app/flow/onboarding               → Start onboarding flow
myapp://app/flow/onboarding/step/permissions     → Onboarding at specific step
myapp://app/scene/window/settings         → Open settings window (macOS)
myapp://app/scene/immersive/viewer/model/abc     → Immersive space (visionOS)

// Tab is REQUIRED - these would fail:
myapp://app/detail/123                    → ❌ Error: ambiguous route
myapp://app/123                           → ❌ Error: no tab specified

Deep Link Resolution

// Generated by @AppShell
extension NavigationCoordinator {
    func resolve(deepLink url: URL) -> DeepLinkResolution {
        // 1. Parse URL into components
        let components = DeepLinkComponents(url: url)

        // 2. Check for flow
        if components.isFlow {
            return .flow(type: components.flowType, step: components.step)
        }

        // 3. Resolve tab + route
        guard let tab = Tab(path: components.tab) else { return .notFound }

        // 4. Build navigation sequence
        var actions: [NavigationAction] = [.selectTab(tab)]

        for (route, presentation) in components.routeStack {
            actions.append(.navigate(route, style: presentation))
        }

        // 5. Check entitlements
        for action in actions {
            if let requirement = action.entitlementRequirement {
                if !store.hasEntitlement(requirement) {
                    return .blocked(requirement, action)
                }
            }
        }

        return .success(actions)
    }
}

---
Platform-Specific Scenes

visionOS

@AppShell
struct MyApp: App {
    @ImmersiveSpace(id: "viewer", style: .mixed)
    enum ViewerScene: NavigationRoute {
        case model(id: String)
        case environment(name: String)
    }

    var body: some Scene {
        // Generated: WindowGroup + ImmersiveSpace
    }
}

// Usage in feature:
Button("View in AR") {
    nav.present(.model(id: "123"), style: .immersiveSpace(id: "viewer"))
}

macOS

@AppShell
struct MyApp: App {
    @Window(id: "preferences", title: "Preferences")
    enum PreferencesWindow: NavigationRoute {
        case general
        case accounts
        case advanced
    }

    @Settings
    enum SettingsScene: NavigationRoute {
        case appearance
        case notifications
    }
}

// Usage:
nav.present(.general, style: .window(id: "preferences"))
nav.present(.appearance, style: .settingsPane)

---
Implementation Phases

Phase 1: Core Infrastructure

1. Define NavigationHandle protocol
2. Define PresentationStyle enum
3. Create NavigationCoordinator base class
4. Implement recursive presentation view modifier

Phase 2: Macro Updates

1. Update @Route to support @presents annotations
2. Update @AppShell to generate NavigationCoordinator
3. Add @Window, @ImmersiveSpace, @Settings scene macros
4. Generate deep link registration

Phase 3: Flow System

1. Define NavigationFlow protocol
2. Create @Flow macro
3. Implement FlowState and step management
4. Add flow-specific deep link support

Phase 4: Platform Scenes

1. visionOS: ImmersiveSpace, ornaments
2. macOS: Window, Settings, inspector
3. iOS: Sheet detents, popover

Phase 5: Deep Link Composition

1. Auto-generate URL patterns from routes
2. Parse presentation style from URL
3. Handle flow deep links
4. State restoration from deep links

---
Critical Files to Modify

| File                                                       | Changes
                   |
|------------------------------------------------------------|----------------------------------
-------------------|
| Sources/ArcheryMacros/AppShellMacro.swift                  | Generate NavigationCoordinator,
recursive modifiers |
| Sources/ArcheryMacros/RouteMacro.swift                     | Support @presents, generate
presentation metadata   |
| Sources/Archery/NavigationRouter.swift                     | Add NavigationHandle,
PresentationStyle             |
| New Sources/ArcheryMacros/FlowMacro.swift                  | @Flow macro implementation
                   |
| New Sources/Archery/Navigation/NavigationCoordinator.swift | Base coordinator class
                   |
| New Sources/Archery/Navigation/NavigationHandle.swift      | Handle protocol + implementations
                   |
| New Sources/Archery/Navigation/FlowState.swift             | Flow management
                   |
| New Sources/ArcheryMacros/PresentsMacro.swift              | @presents annotation macro
                   |

---
Design Decisions (Confirmed)

1. Sheet nesting: Stack sheets (iOS 16+ native behavior) - sheets can present other sheets
2. Flow persistence: Configurable per-flow via @Flow(persists: true/false)
3. Flow branching: Yes, support @branch(replacing:when:) for conditional paths
4. Tab ambiguity: Deep links require explicit tab - no ambiguous routes allowed
5. Feature API: Typed handles per feature (TasksNavigation, DashboardNavigation, etc.)

---
Remaining Considerations

1. Animation customization: Could add @presents(.sheet, transition: .slide) later
2. Cross-tab navigation: Typed handles could include switchTo(tab:then:) for explicit cross-tab
3. Mock handles for testing: Generate MockTasksNavigation that records calls
4. Entitlement blocking UX: When nav.showAnalytics() is blocked, auto-show paywall?

---
Complete Example: ArcheryShowcase

Here's how the final system would look in the showcase app:

// ═══════════════════════════════════════════════════════════════
// MARK: - App Shell Definition
// ═══════════════════════════════════════════════════════════════

@AppShell
@main
struct ArcheryShowcaseApp: App {
    // ─── Tabs ───
    enum Tab: CaseIterable {
        case dashboard
        case tasks

        @requires(.premium, behavior: .locked)
        case insights

        @requires(.pro, behavior: .hidden)
        case admin

        case settings
    }

    // ─── Platform Scenes ───
    #if os(macOS)
    @Window(id: "preferences", title: "Preferences")
    struct PreferencesWindow {}

    @Settings
    struct AppSettings {}
    #endif

    #if os(visionOS)
    @ImmersiveSpace(id: "taskViewer", style: .mixed)
    struct TaskViewerSpace {}
    #endif

    // ─── Flows ───
    @Flow(path: "onboarding", persists: true)
    enum OnboardingFlow {
        case welcome
        case permissions
        case accountSetup
        case complete

        @branch(replacing: .accountSetup, when: .hasExistingAccount)
        case signIn
    }

    @Flow(path: "taskWizard", persists: false)
    enum TaskCreationFlow {
        case basicInfo
        case scheduling
        case priority
        case review
    }

    var body: some Scene {
        WindowGroup {
            ShellView()  // Generated
        }
    }
}

// ═══════════════════════════════════════════════════════════════
// MARK: - Route Definitions
// ═══════════════════════════════════════════════════════════════

@Route(path: "tasks")
enum TasksRoute: NavigationRoute {
    case list
    case detail(id: String)

    @presents(.sheet)
    case quickCreate

    @presents(.sheet, detents: [.medium, .large])
    case edit(id: String)

    @requires(.premium)
    @presents(.fullScreen)
    case analytics

    @requires(.pro)
    case bulkEdit(ids: [String])
}

// ═══════════════════════════════════════════════════════════════
// MARK: - Generated Feature Navigation Handle
// ═══════════════════════════════════════════════════════════════

// Generated by @AppShell from TasksRoute
@MainActor
protocol TasksNavigation {
    func showList()
    func showDetail(id: String)
    func showQuickCreate()
    func showEdit(id: String)
    func showAnalytics() async -> Bool  // Returns false if blocked
    func showBulkEdit(ids: [String]) async -> Bool
    func dismiss()
    func popToRoot()

    // Flow integration
    func startTaskCreation()  // Starts TaskCreationFlow
}

// ═══════════════════════════════════════════════════════════════
// MARK: - Feature Views (Completely Isolated)
// ═══════════════════════════════════════════════════════════════

struct TaskListView: View {
    @GRDBQuery(PersistentTask.all()) var tasks: [PersistentTask]
    @Environment(\.tasksNavigation) private var nav

    var body: some View {
        List(tasks) { task in
            Button {
                nav.showDetail(id: task.id)  // Feature doesn't know this pushes
            } label: {
                TaskRowView(task: task)
            }
        }
        .toolbar {
            Button("New Task") {
                nav.showQuickCreate()  // Feature doesn't know this is a sheet
            }
            Button("Wizard") {
                nav.startTaskCreation()  // Starts the flow
            }
        }
    }
}

struct TaskDetailView: View {
    let taskId: String
    @GRDBQueryOne(PersistentTask.find(id:)) var task: PersistentTask?
    @Environment(\.tasksNavigation) private var nav

    init(id: String) {
        self.taskId = id
        _task = GRDBQueryOne(PersistentTask.find(id: id))
    }

    var body: some View {
        if let task {
            VStack {
                Text(task.title)

                Button("Edit") {
                    nav.showEdit(id: task.id)  // Doesn't know this is sheet
                }

                Button("Analytics") {
                    Task {
                        let allowed = await nav.showAnalytics()
                        // If blocked, paywall was auto-shown
                    }
                }
            }
        }
    }
}

// ═══════════════════════════════════════════════════════════════
// MARK: - Flow Step Views
// ═══════════════════════════════════════════════════════════════

struct TaskWizardBasicInfoStep: View {
    @Environment(\.flowContext) private var flow  // Typed for TaskCreationFlow

    @State private var title = ""
    @State private var description = ""

    var body: some View {
        Form {
            TextField("Title", text: $title)
            TextField("Description", text: $description)
        }
        .toolbar {
            Button("Next") {
                flow.advance(with: ["title": title, "description": description])
            }
            .disabled(title.isEmpty)
        }
    }
}

// ═══════════════════════════════════════════════════════════════
// MARK: - Deep Links (Auto-Generated)
// ═══════════════════════════════════════════════════════════════

// All these URLs work automatically:
// archery://app/tasks/list
// archery://app/tasks/detail/abc123
// archery://app/tasks/detail/abc123/edit?present=sheet
// archery://app/flow/taskWizard
// archery://app/flow/taskWizard/step/scheduling
// archery://app/scene/window/preferences  (macOS)
// archery://app/scene/immersive/taskViewer  (visionOS)

What Gets Generated

The @AppShell macro generates:

1. ShellView - TabView with per-tab NavigationStacks
2. NavigationCoordinator - Manages all navigation state
3. Per-Feature Handles - TasksNavigation, DashboardNavigation, etc.
4. Flow Containers - Wraps flow steps with back/next/cancel
5. Deep Link Router - Registers all routes automatically
6. Environment Keys - \.tasksNavigation, \.flowContext, etc.
7. Mock Handles - For testing: MockTasksNavigation
8. Scene Definitions - Window/ImmersiveSpace where applicable
