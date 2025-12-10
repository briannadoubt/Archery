import Foundation

// MARK: - Navigation Flow Protocol

/// Protocol for multi-step navigation flows.
///
/// Flows are wizard-like sequences of steps that collect data progressively.
/// Define flows using the `@Flow` macro:
///
/// ```swift
/// @Flow(path: "onboarding", persists: true)
/// enum OnboardingFlow: NavigationFlow {
///     case welcome
///     case permissions
///     case accountSetup
///     case complete
///
///     @branch(replacing: .accountSetup, when: .hasExistingAccount)
///     case signIn
/// }
/// ```
public protocol NavigationFlow: CaseIterable, Hashable, Sendable {
    /// Path component for deep links (e.g., "onboarding" → /flow/onboarding)
    static var flowPath: String { get }

    /// Whether flow progress should survive app termination
    static var persists: Bool { get }

    /// All steps in the flow (in order)
    static var steps: [Self] { get }

    /// Deep link path for this step
    var stepPath: String { get }
}

// MARK: - Default Implementations

public extension NavigationFlow {
    /// Default: flow does not persist
    static var persists: Bool { false }

    /// Default steps: all cases in declaration order
    static var steps: [Self] {
        Array(allCases)
    }

    /// Default step path: case name as string
    var stepPath: String {
        String(describing: self)
    }
}

// MARK: - Flow State

/// Tracks the state of an active flow.
///
/// Manages:
/// - Current step
/// - Navigation history (for back)
/// - Collected data across steps
/// - Branch evaluation
public struct FlowState: Identifiable, Sendable {
    public let id: String
    public let flowTypeIdentifier: String

    /// Current step index (0-based)
    public private(set) var currentStepIndex: Int

    /// History of visited step indices (for back navigation)
    public private(set) var history: [Int]

    /// Data collected across steps
    public var collectedData: [String: AnySendable]

    /// Total number of steps in the flow
    public let totalSteps: Int

    /// Step paths for deep linking
    public let stepPaths: [String]

    /// Whether this flow persists across app launches
    public let persists: Bool

    public init<F: NavigationFlow>(
        flowType: F.Type,
        startingStep: F? = nil
    ) {
        self.id = UUID().uuidString
        self.flowTypeIdentifier = String(describing: flowType)
        self.totalSteps = F.steps.count
        self.stepPaths = F.steps.map(\.stepPath)
        self.persists = F.persists
        self.history = []
        self.collectedData = [:]

        if let starting = startingStep,
           let index = F.steps.firstIndex(of: starting) {
            self.currentStepIndex = F.steps.distance(from: F.steps.startIndex, to: index)
        } else {
            self.currentStepIndex = 0
        }
    }

    // MARK: - Navigation

    /// Whether back navigation is available
    public var canGoBack: Bool {
        !history.isEmpty
    }

    /// Whether forward navigation is available
    public var canGoForward: Bool {
        currentStepIndex < totalSteps - 1
    }

    /// Whether the flow is complete
    public var isComplete: Bool {
        currentStepIndex >= totalSteps - 1
    }

    /// Current step path for deep linking
    public var currentStepPath: String? {
        guard currentStepIndex < stepPaths.count else { return nil }
        return stepPaths[currentStepIndex]
    }

    /// Advance to the next step
    /// - Returns: `true` if advanced, `false` if already at end
    @discardableResult
    public mutating func advance() -> Bool {
        guard canGoForward else { return false }
        history.append(currentStepIndex)
        currentStepIndex += 1
        return true
    }

    /// Go back to the previous step
    @discardableResult
    public mutating func back() -> Bool {
        guard let previousIndex = history.popLast() else { return false }
        currentStepIndex = previousIndex
        return true
    }

    /// Skip to a specific step by path
    /// - Returns: `true` if skipped, `false` if step not found or not allowed
    @discardableResult
    public mutating func skip(to stepPath: String) -> Bool {
        guard let index = stepPaths.firstIndex(of: stepPath) else { return false }
        // Only allow skipping forward
        guard index > currentStepIndex else { return false }
        history.append(currentStepIndex)
        currentStepIndex = index
        return true
    }

    /// Skip to a specific step by index
    @discardableResult
    public mutating func skip(toIndex index: Int) -> Bool {
        guard index >= 0, index < totalSteps else { return false }
        guard index > currentStepIndex else { return false }
        history.append(currentStepIndex)
        currentStepIndex = index
        return true
    }

    /// Reset to the beginning
    public mutating func reset() {
        currentStepIndex = 0
        history = []
        collectedData = [:]
    }
}

// MARK: - Sendable Any Wrapper

/// Type-erased Sendable wrapper for flow data
public struct AnySendable: @unchecked Sendable {
    private let _value: Any

    public init<T: Sendable>(_ value: T) {
        self._value = value
    }

    public func value<T>() -> T? {
        _value as? T
    }
}

// MARK: - Flow Error

/// Errors that can occur during flow navigation
public enum FlowError: Error, LocalizedError, Sendable {
    case validationFailed(String)
    case stepNotFound(String)
    case cannotSkip(from: String, to: String)
    case flowNotActive(String)
    case dataRequired(String)

    public var errorDescription: String? {
        switch self {
        case .validationFailed(let message):
            return "Validation failed: \(message)"
        case .stepNotFound(let step):
            return "Step not found: \(step)"
        case .cannotSkip(let from, let to):
            return "Cannot skip from \(from) to \(to)"
        case .flowNotActive(let id):
            return "Flow not active: \(id)"
        case .dataRequired(let field):
            return "Required data missing: \(field)"
        }
    }
}

// MARK: - Flow Persistence

/// Codable representation for flow state persistence
public struct FlowSnapshot: Codable, Sendable {
    public let id: String
    public let flowTypeIdentifier: String
    public let currentStepIndex: Int
    public let history: [Int]
    public let stepPaths: [String]
    public let createdAt: Date

    public init(from state: FlowState) {
        self.id = state.id
        self.flowTypeIdentifier = state.flowTypeIdentifier
        self.currentStepIndex = state.currentStepIndex
        self.history = state.history
        self.stepPaths = state.stepPaths
        self.createdAt = Date()
    }
}

// MARK: - Flow Branch Condition

/// Represents a branch condition evaluated at runtime
public struct FlowBranchCondition: Sendable {
    public let identifier: String
    public let evaluate: @Sendable () -> Bool

    public init(identifier: String, evaluate: @escaping @Sendable () -> Bool) {
        self.identifier = identifier
        self.evaluate = evaluate
    }
}

// MARK: - Flow Branch

/// Describes a conditional branch in a flow
public struct FlowBranch: Sendable {
    /// The step this branch replaces
    public let replacing: String

    /// The alternative step to use
    public let with: String

    /// The condition identifier
    public let conditionIdentifier: String

    public init(replacing: String, with: String, when conditionIdentifier: String) {
        self.replacing = replacing
        self.with = with
        self.conditionIdentifier = conditionIdentifier
    }
}

// MARK: - Flow Skip Condition

/// Describes a skip condition for a step
public struct FlowSkipCondition: Sendable {
    /// The step to potentially skip
    public let step: String

    /// The condition identifier
    public let conditionIdentifier: String

    public init(step: String, when conditionIdentifier: String) {
        self.step = step
        self.conditionIdentifier = conditionIdentifier
    }
}

// MARK: - Flow Configuration

/// Runtime configuration for a flow type
public struct FlowConfiguration: Sendable {
    public let flowPath: String
    public let persists: Bool
    public let steps: [String]
    public let branches: [FlowBranch]
    public let skipConditions: [FlowSkipCondition]

    public init(
        flowPath: String,
        persists: Bool = false,
        steps: [String],
        branches: [FlowBranch] = [],
        skipConditions: [FlowSkipCondition] = []
    ) {
        self.flowPath = flowPath
        self.persists = persists
        self.steps = steps
        self.branches = branches
        self.skipConditions = skipConditions
    }
}
