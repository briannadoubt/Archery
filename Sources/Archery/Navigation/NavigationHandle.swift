import Foundation
import SwiftUI

// MARK: - Navigation Handle Protocol

/// Protocol for feature-level navigation.
///
/// Features receive typed navigation handles via environment, allowing them to
/// request navigation without knowing the global routing structure.
///
/// The handle is opaque to features - they don't know:
/// - What tab they're in
/// - How they were presented (sheet vs push)
/// - The global route structure
///
/// Example usage in a feature view:
/// ```swift
/// struct TaskDetailView: View {
///     @Environment(\.tasksNavigation) private var nav
///
///     var body: some View {
///         Button("Edit") {
///             nav.showEdit(id: task.id)  // Feature doesn't know this opens a sheet
///         }
///     }
/// }
/// ```
@MainActor
public protocol NavigationHandle: AnyObject {
    /// Navigate to a route with its declared presentation style
    func navigate<R: NavigationRoute>(to route: R)

    /// Navigate to a route with an explicit presentation style
    func navigate<R: NavigationRoute>(to route: R, style: PresentationStyle)

    /// Dismiss the current presentation
    func dismiss()

    /// Dismiss multiple levels of presentation
    func dismiss(levels: Int)

    /// Pop to root of the current navigation stack
    func popToRoot()

    /// Check if a navigation action is allowed (entitlements, etc.)
    func canNavigate(to identifier: String) -> Bool
}

// MARK: - Base Navigation Handle

/// Base implementation of NavigationHandle with common functionality.
///
/// Subclassed by generated per-feature handles.
@MainActor
@Observable
open class BaseNavigationHandle: NavigationHandle {
    /// Reference to the coordinator (weak to avoid retain cycles)
    public weak var coordinator: (any NavigationCoordinatorProtocol)?

    /// The current presentation context
    public let context: PresentationContext

    public init(coordinator: (any NavigationCoordinatorProtocol)?, context: PresentationContext) {
        self.coordinator = coordinator
        self.context = context
    }

    // MARK: - NavigationHandle

    open func dismiss() {
        coordinator?.dismiss(levels: 1)
    }

    open func dismiss(levels: Int) {
        coordinator?.dismiss(levels: levels)
    }

    open func popToRoot() {
        coordinator?.popToRoot(in: context)
    }

    open func canNavigate(to identifier: String) -> Bool {
        coordinator?.canNavigate(to: identifier) ?? false
    }

    // MARK: - Protected Helpers for Subclasses

    /// Navigate to a route with its declared presentation style
    public func navigate<R: NavigationRoute>(to route: R) {
        coordinator?.navigate(to: route, style: nil)
    }

    /// Navigate to a route with an explicit presentation style
    public func navigate<R: NavigationRoute>(to route: R, style: PresentationStyle) {
        coordinator?.navigate(to: route, style: style)
    }

    /// Check entitlement and navigate, returning success status
    public func navigateIfAllowed<R: NavigationRoute>(to route: R) async -> Bool {
        guard let coordinator else { return false }
        return await coordinator.navigateIfAllowed(to: route)
    }
}

// MARK: - Navigation Coordinator Protocol

/// Protocol for the generated NavigationCoordinator.
///
/// Defines the interface that BaseNavigationHandle uses to communicate
/// with the coordinator.
@MainActor
public protocol NavigationCoordinatorProtocol: AnyObject {
    /// Navigate to a route with optional style override
    func navigate<R: NavigationRoute>(to route: R, style: PresentationStyle?)

    /// Navigate to a route if entitlements allow, showing paywall if blocked
    func navigateIfAllowed<R: NavigationRoute>(to route: R) async -> Bool

    /// Dismiss the current presentation
    func dismiss(levels: Int)

    /// Pop to root of a navigation stack
    func popToRoot(in context: PresentationContext)

    /// Check if navigation to an identifier is allowed
    func canNavigate(to identifier: String) -> Bool

    /// Get the current entitlements
    var currentEntitlements: Set<Entitlement> { get }
}

// MARK: - Flow Navigation Handle

/// Extended handle for views inside a flow
@MainActor
public protocol FlowNavigationHandle: NavigationHandle {
    /// Advance to the next step in the flow
    func advance()

    /// Advance to the next step, passing collected data
    func advance(with data: [String: Any])

    /// Go back to the previous step
    func back()

    /// Cancel the flow entirely
    func cancel()

    /// Skip to a specific step (if allowed)
    func skip(to step: String) -> Bool

    /// Whether back navigation is available
    var canGoBack: Bool { get }

    /// Whether forward navigation is available
    var canGoForward: Bool { get }

    /// The current step index (0-based)
    var currentStepIndex: Int { get }

    /// Total number of steps
    var totalSteps: Int { get }
}

// MARK: - Environment Keys

/// Environment key for generic navigation handle
public struct NavigationHandleKey: @preconcurrency EnvironmentKey {
    @MainActor public static let defaultValue: (any NavigationHandle)? = nil
}

public extension EnvironmentValues {
    var navigationHandle: (any NavigationHandle)? {
        get { self[NavigationHandleKey.self] }
        set { self[NavigationHandleKey.self] = newValue }
    }
}

// MARK: - Type-Erased Route

/// Type-erased wrapper for any NavigationRoute
public struct AnyRoute: Identifiable, Hashable, Sendable {
    public let id: String
    private let _route: any NavigationRoute
    private let _presentationStyle: PresentationStyle

    public init<R: NavigationRoute>(_ route: R, style: PresentationStyle = .default) {
        self.id = route.navigationIdentifier
        self._route = route
        self._presentationStyle = style
    }

    public var presentationStyle: PresentationStyle { _presentationStyle }

    /// Attempt to cast back to a specific route type
    public func `as`<R: NavigationRoute>(_ type: R.Type) -> R? {
        _route as? R
    }

    public static func == (lhs: AnyRoute, rhs: AnyRoute) -> Bool {
        lhs.id == rhs.id
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

// MARK: - Navigation Action

/// Represents a single navigation action to be executed by the coordinator
public enum CoordinatorAction: Sendable {
    case selectTab(index: Int)
    case push(AnyRoute)
    case present(AnyRoute, style: PresentationStyle)
    case dismiss(levels: Int)
    case popToRoot
    case startFlow(id: String, step: String?)

    /// The entitlement requirement for this action, if any
    public var entitlementRequirement: EntitlementRequirement? {
        switch self {
        case .push, .present:
            // Note: Actual requirement lookup happens in coordinator
            return nil
        default:
            return nil
        }
    }
}

// MARK: - Deep Link Resolution

/// Result of resolving a deep link
public enum DeepLinkResolution: Sendable {
    case success([CoordinatorAction])
    case flow(id: String, step: String?)
    case blocked(EntitlementRequirement, CoordinatorAction)
    case notFound
    case invalidFormat(String)
}

// MARK: - Mock Navigation Handle

/// Mock handle for testing and previews
@MainActor
public final class MockNavigationHandle: NavigationHandle {
    public var dismissCallCount = 0
    public var popToRootCallCount = 0
    public var navigations: [(identifier: String, style: PresentationStyle?)] = []
    public var navigationAttempts: [(identifier: String, allowed: Bool)] = []

    public init() {}

    public func navigate<R: NavigationRoute>(to route: R) {
        navigations.append((route.navigationIdentifier, nil))
    }

    public func navigate<R: NavigationRoute>(to route: R, style: PresentationStyle) {
        navigations.append((route.navigationIdentifier, style))
    }

    public func dismiss() {
        dismissCallCount += 1
    }

    public func dismiss(levels: Int) {
        dismissCallCount += levels
    }

    public func popToRoot() {
        popToRootCallCount += 1
    }

    public func canNavigate(to identifier: String) -> Bool {
        let allowed = true // Always allow in mock
        navigationAttempts.append((identifier, allowed))
        return allowed
    }
}
