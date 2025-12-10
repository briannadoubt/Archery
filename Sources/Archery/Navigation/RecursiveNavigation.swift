import SwiftUI

// MARK: - Recursive Navigation View Modifier

/// Applies recursive navigation handling to a view.
///
/// Enables sheets to present other sheets, full screens to present sheets, etc.
/// Each presentation level gets its own NavigationStack and can present further.
///
/// Usage (in generated ShellView):
/// ```swift
/// tabContent(for: selectedTab)
///     .recursiveNavigation(
///         coordinator: coordinator,
///         context: .tab(tabIndex)
///     )
/// ```
public struct RecursiveNavigationModifier<Tab: Hashable & CaseIterable & Sendable>: ViewModifier {
    @ObservedObject var coordinator: NavigationCoordinator<Tab>
    let context: PresentationContext
    let routeResolver: (AnyRoute) -> AnyView

    public init(
        coordinator: NavigationCoordinator<Tab>,
        context: PresentationContext,
        routeResolver: @escaping (AnyRoute) -> AnyView
    ) {
        self.coordinator = coordinator
        self.context = context
        self.routeResolver = routeResolver
    }

    public func body(content: Content) -> some View {
        content
            // Sheet stack - each sheet can present another sheet
            .sheet(item: coordinator.sheetBinding(depth: context.sheetDepth)) { route in
                sheetContent(for: route)
            }
            // Full screen presentation (not available on macOS)
            #if !os(macOS)
            .fullScreenCover(item: coordinator.fullScreenBinding) { route in
                fullScreenContent(for: route)
            }
            #endif
            // Inject navigation handle for this context
            .environment(\.navigationHandle, coordinator.makeHandle(for: context))
    }

    @ViewBuilder
    private func sheetContent(for route: AnyRoute) -> some View {
        let newContext = PresentationContext.sheet(
            depth: context.sheetDepth + 1,
            parentTab: context.parentTab
        )

        NavigationStack {
            routeResolver(route)
                .recursiveNavigation(
                    coordinator: coordinator,
                    context: newContext,
                    routeResolver: routeResolver
                )
        }
        .presentationDetents(detents(for: route))
        .interactiveDismissDisabled(isInteractiveDismissDisabled(for: route))
    }

    @ViewBuilder
    private func fullScreenContent(for route: AnyRoute) -> some View {
        let newContext = PresentationContext.fullScreen(parentTab: context.parentTab)

        NavigationStack {
            routeResolver(route)
                .recursiveNavigation(
                    coordinator: coordinator,
                    context: newContext,
                    routeResolver: routeResolver
                )
        }
    }

    private func detents(for route: AnyRoute) -> Set<PresentationDetent> {
        if case .sheet(let detents) = route.presentationStyle {
            return Set(detents.map(\.presentationDetent))
        }
        return [.large]
    }

    private func isInteractiveDismissDisabled(for route: AnyRoute) -> Bool {
        // Could be configured per-route via metadata
        false
    }
}

// MARK: - View Extension

public extension View {
    /// Apply recursive navigation handling
    func recursiveNavigation<Tab: Hashable & CaseIterable & Sendable>(
        coordinator: NavigationCoordinator<Tab>,
        context: PresentationContext,
        routeResolver: @escaping (AnyRoute) -> AnyView
    ) -> some View {
        modifier(RecursiveNavigationModifier(
            coordinator: coordinator,
            context: context,
            routeResolver: routeResolver
        ))
    }
}

// MARK: - Flow Container View

/// Container view for flow steps with automatic back/next handling.
///
/// Wraps flow step content and provides:
/// - Back/Next toolbar buttons
/// - Progress indicator
/// - Cancel button
/// - Automatic step transitions
public struct FlowContainerView<Content: View>: View {
    @Environment(\.navigationHandle) private var baseHandle
    @Environment(\.dismiss) private var dismiss

    let flowState: FlowState
    let content: () -> Content
    let onAdvance: ([String: Any]?) -> Void
    let onBack: () -> Void
    let onCancel: () -> Void

    public init(
        flowState: FlowState,
        @ViewBuilder content: @escaping () -> Content,
        onAdvance: @escaping ([String: Any]?) -> Void,
        onBack: @escaping () -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.flowState = flowState
        self.content = content
        self.onAdvance = onAdvance
        self.onBack = onBack
        self.onCancel = onCancel
    }

    public var body: some View {
        content()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if flowState.canGoBack {
                        Button("Back") {
                            onBack()
                        }
                    } else {
                        Button("Cancel") {
                            onCancel()
                        }
                    }
                }

                ToolbarItem(placement: .principal) {
                    FlowProgressIndicator(
                        currentStep: flowState.currentStepIndex,
                        totalSteps: flowState.totalSteps
                    )
                }

                ToolbarItem(placement: .confirmationAction) {
                    if flowState.isComplete {
                        Button("Done") {
                            onAdvance(nil)
                        }
                    } else {
                        Button("Next") {
                            onAdvance(nil)
                        }
                    }
                }
            }
    }
}

// MARK: - Flow Progress Indicator

/// Visual indicator of flow progress
public struct FlowProgressIndicator: View {
    let currentStep: Int
    let totalSteps: Int

    public init(currentStep: Int, totalSteps: Int) {
        self.currentStep = currentStep
        self.totalSteps = totalSteps
    }

    public var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<totalSteps, id: \.self) { index in
                Circle()
                    .fill(index <= currentStep ? Color.accentColor : Color.secondary.opacity(0.3))
                    .frame(width: 8, height: 8)
            }
        }
    }
}

// MARK: - Flow Context Environment Key

/// Environment key for flow-specific navigation handle
public struct FlowContextKey: @preconcurrency EnvironmentKey {
    @MainActor public static let defaultValue: FlowNavigationContext? = nil
}

public extension EnvironmentValues {
    var flowContext: FlowNavigationContext? {
        get { self[FlowContextKey.self] }
        set { self[FlowContextKey.self] = newValue }
    }
}

/// Context provided to views within a flow
@MainActor
public final class FlowNavigationContext: ObservableObject {
    public let flowId: String
    @Published public private(set) var state: FlowState

    private weak var coordinator: (any NavigationCoordinatorProtocol)?

    public init(flowId: String, state: FlowState, coordinator: (any NavigationCoordinatorProtocol)?) {
        self.flowId = flowId
        self.state = state
        self.coordinator = coordinator
    }

    /// Advance to the next step, optionally passing data
    public func advance(with data: [String: AnySendable]? = nil) {
        var newState = state
        if let data {
            newState.collectedData.merge(data) { _, new in new }
        }
        if newState.advance() {
            state = newState
        }
    }

    /// Go back to the previous step
    public func back() {
        var newState = state
        if newState.back() {
            state = newState
        }
    }

    /// Cancel the flow
    public func cancel() {
        coordinator?.dismiss(levels: 1)
    }

    /// Get collected data for a key
    public func data<T: Sendable>(for key: String) -> T? {
        state.collectedData[key]?.value()
    }

    /// Whether back navigation is available
    public var canGoBack: Bool { state.canGoBack }

    /// Whether forward navigation is available
    public var canGoForward: Bool { state.canGoForward }

    /// Current step index
    public var currentStepIndex: Int { state.currentStepIndex }

    /// Total steps
    public var totalSteps: Int { state.totalSteps }
}

// MARK: - Presentation Configuration

/// Configuration for sheet presentation
public struct SheetConfiguration {
    public let detents: Set<SheetDetent>
    public let dragIndicatorVisibility: Visibility
    public let interactiveDismissDisabled: Bool
    public let cornerRadius: CGFloat?

    public init(
        detents: Set<SheetDetent> = [.large],
        dragIndicatorVisibility: Visibility = .automatic,
        interactiveDismissDisabled: Bool = false,
        cornerRadius: CGFloat? = nil
    ) {
        self.detents = detents
        self.dragIndicatorVisibility = dragIndicatorVisibility
        self.interactiveDismissDisabled = interactiveDismissDisabled
        self.cornerRadius = cornerRadius
    }

    public static var `default`: SheetConfiguration {
        SheetConfiguration()
    }

    public static var medium: SheetConfiguration {
        SheetConfiguration(detents: [.medium])
    }

    public static var mediumLarge: SheetConfiguration {
        SheetConfiguration(detents: [.medium, .large])
    }
}
