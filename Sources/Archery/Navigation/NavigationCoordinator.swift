import Foundation
import SwiftUI

// MARK: - Navigation Coordinator

/// Base class for app-level navigation coordination.
///
/// Subclassed by the generated coordinator from @AppShell macro.
/// Manages:
/// - Tab selection
/// - Navigation stacks per tab
/// - Sheet/fullscreen presentation stacks
/// - Active flows
/// - Deep link handling
/// - State persistence
///
/// Example generated subclass:
/// ```swift
/// @MainActor
/// final class MyAppNavigationCoordinator: NavigationCoordinator<MyApp.Tab> {
///     // Generated route resolution, handle creation, etc.
/// }
/// ```
@MainActor
open class NavigationCoordinator<Tab: Hashable & CaseIterable>: ObservableObject, NavigationCoordinatorProtocol {

    // MARK: - Published State

    /// Currently selected tab
    @Published public var selectedTab: Tab

    /// Navigation paths per tab (using [AnyHashable] for type erasure)
    @Published public var tabPaths: [Tab: [AnyHashable]] = [:]

    /// Stack of presented sheets (supports stacked sheets)
    @Published public var sheetStack: [AnyRoute] = []

    /// Currently presented full screen route
    @Published public var fullScreenRoute: AnyRoute?

    /// Active flows keyed by flow ID
    @Published public var activeFlows: [String: FlowState] = [:]

    // MARK: - Dependencies

    /// Store for checking entitlements
    public var storeKitManager: StoreKitManager?

    /// Persistence configuration
    public let persistence: NavigationPersistence

    /// Callback when navigation is blocked due to entitlements
    public var onEntitlementBlocked: ((AnyRoute, EntitlementRequirement, Bool) -> Void)?

    // MARK: - Private State

    private var presentationMetadataCache: [String: PresentationMetadata] = [:]

    // MARK: - Initialization

    public init(
        initialTab: Tab,
        persistence: NavigationPersistence = .disabled()
    ) {
        self.selectedTab = initialTab
        self.persistence = persistence

        // Initialize empty paths for all tabs
        for tab in Tab.allCases {
            tabPaths[tab] = []
        }
    }

    // MARK: - NavigationCoordinatorProtocol

    open func navigate<R: NavigationRoute>(to route: R, style: PresentationStyle?) {
        let resolvedStyle = style ?? resolveStyle(for: route)
        let anyRoute = AnyRoute(route, style: resolvedStyle)

        // === AUTO-TRACK NAVIGATION ===
        trackNavigation(route: route, style: resolvedStyle)

        switch resolvedStyle {
        case .push:
            pushToCurrentStack(anyRoute)

        case .replace:
            replaceInCurrentStack(anyRoute)

        case .sheet:
            presentSheet(anyRoute)

        case .fullScreen:
            presentFullScreen(anyRoute)

        case .popover:
            // Treat as sheet on iPhone
            presentSheet(anyRoute)

        case .window(let id):
            openWindow(id: id, route: anyRoute)

        case .tab(let index):
            if let tab = tabForIndex(index) {
                selectedTab = tab
            }

        #if os(visionOS)
        case .immersiveSpace(let id, _):
            openImmersiveSpace(id: id, route: anyRoute)
        #endif

        #if os(macOS)
        case .settingsPane:
            openSettings(route: anyRoute)
        case .inspector:
            openInspector(route: anyRoute)
        #endif
        }

        persistIfEnabled()
    }

    open func navigateIfAllowed<R: NavigationRoute>(to route: R) async -> Bool {
        // Check entitlements if route conforms to EntitlementGatedRoute
        if let requirement = checkEntitlement(for: route) {
            if !requirement.isSatisfied(by: currentEntitlements) {
                let anyRoute = AnyRoute(route)

                // === AUTO-TRACK ENTITLEMENT BLOCKED ===
                trackEntitlementBlocked(route: anyRoute, requirement: requirement)

                onEntitlementBlocked?(anyRoute, requirement, true)
                return false
            }
        }

        navigate(to: route, style: nil)
        return true
    }

    /// Check entitlement requirement for a route (override in generated coordinator)
    open func checkEntitlement<R: NavigationRoute>(for route: R) -> EntitlementRequirement? {
        nil
    }

    open func dismiss(levels: Int) {
        for _ in 0..<levels {
            if fullScreenRoute != nil {
                fullScreenRoute = nil
            } else if !sheetStack.isEmpty {
                sheetStack.removeLast()
            } else {
                // Pop from current tab's stack
                if var path = tabPaths[selectedTab], !path.isEmpty {
                    path.removeLast()
                    tabPaths[selectedTab] = path
                }
            }
        }
        persistIfEnabled()
    }

    open func popToRoot(in context: PresentationContext) {
        if let tabIndex = context.parentTab, let tab = tabForIndex(tabIndex) {
            tabPaths[tab] = []
        } else {
            tabPaths[selectedTab] = []
        }
        persistIfEnabled()
    }

    open func canNavigate(to identifier: String) -> Bool {
        // Override in generated subclass to check entitlements
        true
    }

    open var currentEntitlements: Set<Entitlement> {
        storeKitManager?.entitlements ?? []
    }

    // MARK: - Presentation Style Resolution

    /// Override to provide presentation metadata for routes
    open func resolveStyle<R: NavigationRoute>(for route: R) -> PresentationStyle {
        // Look up cached metadata or use default
        let identifier = route.navigationIdentifier
        if let cached = presentationMetadataCache[identifier] {
            return cached.style
        }
        return .default
    }

    /// Register presentation metadata (called by generated code)
    public func registerPresentationMetadata(_ metadata: PresentationMetadata, for identifier: String) {
        presentationMetadataCache[identifier] = metadata
    }

    // MARK: - Tab Helpers

    /// Convert tab index to Tab type
    open func tabForIndex(_ index: Int) -> Tab? {
        let allTabs = Array(Tab.allCases)
        guard index >= 0, index < allTabs.count else { return nil }
        return allTabs[index]
    }

    /// Convert Tab type to index
    open func indexForTab(_ tab: Tab) -> Int? {
        let allTabs = Array(Tab.allCases)
        return allTabs.firstIndex(of: tab)
    }

    // MARK: - Navigation Actions

    private func pushToCurrentStack(_ route: AnyRoute) {
        var path = tabPaths[selectedTab] ?? []
        path.append(route)
        tabPaths[selectedTab] = path
    }

    private func replaceInCurrentStack(_ route: AnyRoute) {
        var path = tabPaths[selectedTab] ?? []
        if !path.isEmpty {
            path[path.count - 1] = route
        } else {
            path.append(route)
        }
        tabPaths[selectedTab] = path
    }

    private func presentSheet(_ route: AnyRoute) {
        sheetStack.append(route)
    }

    private func presentFullScreen(_ route: AnyRoute) {
        fullScreenRoute = route
    }

    /// Override for window presentation (platform-specific)
    open func openWindow(id: String, route: AnyRoute) {
        #if os(macOS) || os(iOS)
        // Window presentation requires Scene-level handling
        // Generated code will handle this
        #endif
    }

    #if os(visionOS)
    /// Override for immersive space presentation
    open func openImmersiveSpace(id: String, route: AnyRoute) {
        // Immersive space requires Scene-level handling
        // Generated code will handle this
    }
    #endif

    #if os(macOS)
    /// Override for Settings pane presentation
    open func openSettings(route: AnyRoute) {
        // Settings presentation requires Scene-level handling
        // Generated code will handle this
    }

    /// Override for inspector presentation
    open func openInspector(route: AnyRoute) {
        // Inspector presentation requires Scene-level handling
        // Generated code will handle this
    }
    #endif

    // MARK: - Flow Management

    /// Start a new flow
    public func startFlow<F: NavigationFlow>(_ flowType: F.Type, startingStep: F? = nil) {
        let state = FlowState(
            flowType: flowType,
            startingStep: startingStep
        )
        activeFlows[state.id] = state

        // === AUTO-TRACK FLOW START ===
        trackFlowStart(flowType: flowType, state: state)

        // Present flow as sheet by default
        if flowType.steps.first != nil {
            // Route resolution for flow steps handled by generated code
        }
    }

    /// Advance a flow to the next step
    public func advanceFlow(_ flowId: String, data: [String: AnySendable]? = nil) {
        guard var state = activeFlows[flowId] else { return }

        if let data {
            state.collectedData.merge(data) { _, new in new }
        }

        let previousStep = state.currentStepIndex

        if state.advance() {
            activeFlows[flowId] = state

            // === AUTO-TRACK STEP COMPLETED ===
            trackFlowStep(state: state, fromStep: previousStep)
        } else {
            // === AUTO-TRACK FLOW COMPLETED ===
            trackFlowCompleted(state: state)

            // Flow complete
            activeFlows[flowId] = nil
        }
    }

    /// Go back in a flow
    public func flowBack(_ flowId: String) {
        guard var state = activeFlows[flowId] else { return }
        state.back()
        activeFlows[flowId] = state
    }

    /// Cancel a flow
    public func cancelFlow(_ flowId: String) {
        // === AUTO-TRACK FLOW ABANDONED ===
        if let state = activeFlows[flowId] {
            trackFlowAbandoned(state: state)
        }

        activeFlows[flowId] = nil
        dismiss(levels: 1)
    }

    // MARK: - Deep Link Handling

    /// Handle a deep link URL
    open func handle(url: URL) -> Bool {
        guard let resolution = resolveDeepLink(url) else { return false }

        switch resolution {
        case .success(let actions):
            execute(actions: actions)
            return true

        case .flow(let id, let step):
            // Flow deep link handling
            return handleFlowDeepLink(id: id, step: step)

        case .blocked(let requirement, let action):
            // Notify about blocked navigation
            if case .push(let route) = action {
                onEntitlementBlocked?(route, requirement, true)
            }
            return false

        case .notFound, .invalidFormat:
            return false
        }
    }

    /// Override to implement deep link resolution
    open func resolveDeepLink(_ url: URL) -> DeepLinkResolution? {
        // Generated code will implement URL parsing
        nil
    }

    private func execute(actions: [CoordinatorAction]) {
        for action in actions {
            switch action {
            case .selectTab(let index):
                if let tab = tabForIndex(index) {
                    selectedTab = tab
                }
            case .push(let route):
                pushToCurrentStack(route)
            case .present(let route, let style):
                switch style {
                case .sheet: presentSheet(route)
                case .fullScreen: presentFullScreen(route)
                default: pushToCurrentStack(route)
                }
            case .dismiss(let levels):
                dismiss(levels: levels)
            case .popToRoot:
                tabPaths[selectedTab] = []
            case .startFlow(let id, let step):
                handleFlowDeepLink(id: id, step: step)
            }
        }
    }

    @discardableResult
    private func handleFlowDeepLink(id: String, step: String?) -> Bool {
        // Flow deep link handling implemented by generated code
        false
    }

    // MARK: - Persistence

    private func persistIfEnabled() {
        guard persistence.mode == .enabled else { return }
        // Persistence implementation using NavigationRestorer
    }

    /// Restore navigation state on launch
    public func restoreState() {
        guard persistence.mode == .enabled else { return }
        // State restoration implementation
    }

    // MARK: - Handle Factory

    /// Create a navigation handle for a specific context
    open func makeHandle(for context: PresentationContext) -> any NavigationHandle {
        BaseNavigationHandle(coordinator: self, context: context)
    }

    // MARK: - Analytics Tracking

    /// Track navigation to a route
    private func trackNavigation<R: NavigationRoute>(route: R, style: PresentationStyle) {
        let config = ArcheryAnalyticsConfiguration.shared
        guard config.enabledCategories.contains(.navigation) else { return }

        // Get tab name if available
        let tabName: String?
        if let index = indexForTab(selectedTab) {
            tabName = "tab_\(index)"
        } else {
            tabName = nil
        }

        let event = ArcheryEvent.screenViewed(
            route: route.navigationIdentifier,
            style: style.analyticsName,
            tab: tabName
        )
        config.track(event)
    }

    /// Track flow start
    private func trackFlowStart<F: NavigationFlow>(flowType: F.Type, state: FlowState) {
        let config = ArcheryAnalyticsConfiguration.shared
        guard config.enabledCategories.contains(.navigation) else { return }

        let event = ArcheryEvent.flowStarted(
            flowType: String(describing: flowType),
            flowId: state.id
        )
        config.track(event)
    }

    /// Track flow step completion
    private func trackFlowStep(state: FlowState, fromStep: Int) {
        let config = ArcheryAnalyticsConfiguration.shared
        guard config.enabledCategories.contains(.navigation) else { return }

        let event = ArcheryEvent.flowStepCompleted(
            flowType: state.flowTypeIdentifier,
            flowId: state.id,
            step: state.currentStepIndex,
            stepName: state.currentStepPath ?? "step_\(state.currentStepIndex)"
        )
        config.track(event)
    }

    /// Track flow completion
    private func trackFlowCompleted(state: FlowState) {
        let config = ArcheryAnalyticsConfiguration.shared
        guard config.enabledCategories.contains(.navigation) else { return }

        let event = ArcheryEvent.flowCompleted(
            flowType: state.flowTypeIdentifier,
            flowId: state.id,
            totalSteps: state.totalSteps
        )
        config.track(event)
    }

    /// Track flow abandonment
    private func trackFlowAbandoned(state: FlowState) {
        let config = ArcheryAnalyticsConfiguration.shared
        guard config.enabledCategories.contains(.navigation) else { return }

        let event = ArcheryEvent.flowAbandoned(
            flowType: state.flowTypeIdentifier,
            flowId: state.id,
            atStep: state.currentStepIndex
        )
        config.track(event)
    }

    /// Track entitlement blocked navigation
    private func trackEntitlementBlocked(route: AnyRoute, requirement: EntitlementRequirement) {
        let config = ArcheryAnalyticsConfiguration.shared
        guard config.enabledCategories.contains(.monetization) else { return }

        let event = ArcheryEvent.entitlementBlocked(
            route: route.id,
            required: requirement.analyticsDescription
        )
        config.track(event)
    }
}

// MARK: - Bindings for SwiftUI

public extension NavigationCoordinator {
    /// Binding for sheet presentation at a specific depth
    func sheetBinding(depth: Int = 0) -> Binding<AnyRoute?> {
        Binding(
            get: { [weak self] in
                guard let self, depth < self.sheetStack.count else { return nil }
                return self.sheetStack[depth]
            },
            set: { [weak self] newValue in
                guard let self else { return }
                if newValue == nil, depth < self.sheetStack.count {
                    // Remove this sheet and all above it
                    self.sheetStack.removeSubrange(depth...)
                }
            }
        )
    }

    /// Binding for full screen presentation
    var fullScreenBinding: Binding<AnyRoute?> {
        Binding(
            get: { [weak self] in self?.fullScreenRoute },
            set: { [weak self] newValue in self?.fullScreenRoute = newValue }
        )
    }

    /// Binding for navigation path of current tab
    var currentPathBinding: Binding<[AnyHashable]> {
        Binding(
            get: { [weak self] in
                guard let self else { return [] }
                return self.tabPaths[self.selectedTab] ?? []
            },
            set: { [weak self] newValue in
                guard let self else { return }
                self.tabPaths[self.selectedTab] = newValue
            }
        )
    }

    /// Binding for navigation path of a specific tab
    func pathBinding(for tab: Tab) -> Binding<[AnyHashable]> {
        Binding(
            get: { [weak self] in self?.tabPaths[tab] ?? [] },
            set: { [weak self] newValue in self?.tabPaths[tab] = newValue }
        )
    }
}
