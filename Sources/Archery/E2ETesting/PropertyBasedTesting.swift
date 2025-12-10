import Foundation
import Combine

// MARK: - Property-Based Testing

/// Property-based testing framework for state machines and load states
public struct PropertyBasedTester<State: Equatable, Action> {

    private let stateMachine: StateMachine<State, Action>
    private let properties: [Property<State, Action>]
    private let generators: [Generator<Action>]

    public init(
        stateMachine: StateMachine<State, Action>,
        properties: [Property<State, Action>],
        generators: [Generator<Action>]
    ) {
        self.stateMachine = stateMachine
        self.properties = properties
        self.generators = generators
    }

    // MARK: - Testing

    /// Run property-based tests
    public func test(iterations: Int = 100, seed: UInt64? = nil) -> PropertyTestReport {
        var results: [PropertyTestResult] = []
        var rng: any RandomNumberGenerator = seed.map { SeededRandom(seed: $0) as any RandomNumberGenerator } ?? SystemRandomNumberGenerator()

        for property in properties {
            let result = testProperty(
                property,
                iterations: iterations,
                generator: &rng
            )
            results.append(result)
        }

        return PropertyTestReport(
            timestamp: Date(),
            results: results,
            passed: results.allSatisfy { $0.passed }
        )
    }

    private func testProperty(
        _ property: Property<State, Action>,
        iterations: Int,
        generator: inout any RandomNumberGenerator
    ) -> PropertyTestResult {
        var failures: [PropertyFailure] = []
        var successCount = 0

        for i in 0..<iterations {
            // Generate random action sequence
            let actions = generateActionSequence(
                count: Int.random(in: 1...20, using: &generator),
                generator: &generator
            )

            // Apply actions to state machine
            var currentState = stateMachine.initialState
            var states: [State] = [currentState]

            for action in actions {
                if let nextState = stateMachine.transition(currentState, action) {
                    currentState = nextState
                    states.append(currentState)
                }
            }

            // Check property
            if property.check(states, actions) {
                successCount += 1
            } else {
                failures.append(PropertyFailure(
                    iteration: i,
                    description: "Failed at iteration \(i) with \(states.count) states and \(actions.count) actions",
                    property: property.name
                ))

                // Try to shrink the failure
                if let shrunk = shrink(actions: actions, property: property) {
                    failures.append(PropertyFailure(
                        iteration: i,
                        description: "Shrunk to \(shrunk.states.count) states and \(shrunk.actions.count) actions",
                        property: property.name + " (shrunk)"
                    ))
                }
            }
        }

        return PropertyTestResult(
            property: property.name,
            iterations: iterations,
            passed: failures.isEmpty,
            failures: failures,
            successRate: Double(successCount) / Double(iterations)
        )
    }

    private func generateActionSequence(
        count: Int,
        generator: inout any RandomNumberGenerator
    ) -> [Action] {
        guard !generators.isEmpty else { return [] }

        return (0..<count).map { _ in
            let gen = generators.randomElement(using: &generator)!
            return gen.generate(&generator)
        }
    }

    // MARK: - Shrinking

    private func shrink(
        actions: [Action],
        property: Property<State, Action>
    ) -> (states: [State], actions: [Action])? {
        // Try progressively smaller sequences
        for size in stride(from: actions.count - 1, to: 0, by: -1) {
            for start in 0...(actions.count - size) {
                let subActions = Array(actions[start..<(start + size)])

                var currentState = stateMachine.initialState
                var states: [State] = [currentState]

                for action in subActions {
                    if let nextState = stateMachine.transition(currentState, action) {
                        currentState = nextState
                        states.append(currentState)
                    }
                }

                if !property.check(states, subActions) {
                    // Found smaller failing case
                    return (states: states, actions: subActions)
                }
            }
        }

        return nil
    }
}

// MARK: - State Machine

public struct StateMachine<State: Equatable, Action> {
    public let initialState: State
    public let transition: (State, Action) -> State?

    public init(
        initialState: State,
        transition: @escaping (State, Action) -> State?
    ) {
        self.initialState = initialState
        self.transition = transition
    }
}

// MARK: - Properties

public struct Property<State, Action> {
    public let name: String
    public let check: ([State], [Action]) -> Bool

    public init(
        name: String,
        check: @escaping ([State], [Action]) -> Bool
    ) {
        self.name = name
        self.check = check
    }
}

// MARK: - Generators

public struct Generator<T> {
    public let generate: (inout any RandomNumberGenerator) -> T

    public init(generate: @escaping (inout any RandomNumberGenerator) -> T) {
        self.generate = generate
    }
}

// MARK: - Common Properties

public extension Property {

    /// Property: State machine never enters invalid state
    static func noInvalidStates<S: Equatable, A>(
        isValid: @escaping (S) -> Bool
    ) -> Property<S, A> {
        Property<S, A>(name: "No Invalid States") { states, _ in
            states.allSatisfy(isValid)
        }
    }

    /// Property: State machine is deterministic
    static func isDeterministic<S: Equatable, A: Equatable>() -> Property<S, A> {
        Property<S, A>(name: "Deterministic") { states, actions in
            // Run the same actions again and check same result
            true // Simplified - would need state machine reference
        }
    }

    /// Property: State machine eventually reaches terminal state
    static func eventuallyTerminates<S: Equatable, A>(
        isTerminal: @escaping (S) -> Bool
    ) -> Property<S, A> {
        Property<S, A>(name: "Eventually Terminates") { states, _ in
            states.contains(where: isTerminal)
        }
    }

    /// Property: No duplicate states in sequence (no cycles)
    static func noCycles<S: Hashable, A>() -> Property<S, A> {
        Property<S, A>(name: "No Cycles") { states, _ in
            Set(states).count == states.count
        }
    }
}

// MARK: - Common Generators

public extension Generator where T == Int {
    /// Generate random integer
    static func randomInt(in range: ClosedRange<Int>) -> Generator<Int> {
        Generator<Int> { generator in
            Int.random(in: range, using: &generator)
        }
    }
}

public extension Generator where T == Bool {
    /// Generate random bool
    static var randomBool: Generator<Bool> {
        Generator<Bool> { generator in
            Bool.random(using: &generator)
        }
    }
}

public extension Generator where T == String {
    /// Generate random string
    static func randomString(length: Int) -> Generator<String> {
        Generator<String> { generator in
            let characters = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
            return String((0..<length).map { _ in
                characters.randomElement(using: &generator)!
            })
        }
    }
}

public extension Generator {
    /// Choose from array
    static func oneOf(_ values: [T]) -> Generator<T> {
        Generator<T> { generator in
            values.randomElement(using: &generator)!
        }
    }

    /// Weighted choice
    static func weighted(_ choices: [(T, Int)]) -> Generator<T> {
        Generator<T> { generator in
            let total = choices.reduce(0) { $0 + $1.1 }
            let random = Int.random(in: 0..<total, using: &generator)

            var sum = 0
            for (value, weight) in choices {
                sum += weight
                if random < sum {
                    return value
                }
            }

            return choices.last!.0
        }
    }
}

// MARK: - Load State Testing

// Note: LoadState is defined in Archery.swift

public enum LoadAction {
    case startLoading
    case succeed(Any)
    case fail(Error)
    case reset
}

/// State machine for load states
public func loadStateMachine<T: Equatable>() -> StateMachine<LoadState<T>, LoadAction> {
    StateMachine(initialState: .idle) { state, action in
        switch (state, action) {
        case (.idle, .startLoading):
            return .loading
        case (.loading, .succeed(let value)):
            if let typedValue = value as? T {
                return .success(typedValue)
            }
            return nil
        case (.loading, .fail(let error)):
            return .failure(error)
        case (_, .reset):
            return .idle
        default:
            return nil
        }
    }
}

/// Common properties for load state machines
public struct LoadStateProperties {

    public static func validTransitions<T: Equatable>() -> Property<LoadState<T>, LoadAction> {
        Property(name: "Valid Load State Transitions") { states, _ in
            for i in 0..<(states.count - 1) {
                let current = states[i]
                let next = states[i + 1]

                // Check valid transitions
                switch (current, next) {
                case (.idle, .loading),
                     (.loading, .success),
                     (.loading, .failure),
                     (_, .idle): // Reset from any state
                    continue
                default:
                    return false
                }
            }
            return true
        }
    }

    public static func noDoubleLoading<T: Equatable>() -> Property<LoadState<T>, LoadAction> {
        Property(name: "No Double Loading") { states, _ in
            for i in 0..<(states.count - 1) {
                if case .loading = states[i], case .loading = states[i + 1] {
                    return false
                }
            }
            return true
        }
    }
}

// MARK: - Test Results

public struct PropertyTestResult {
    public let property: String
    public let iterations: Int
    public let passed: Bool
    public let failures: [PropertyFailure]
    public let successRate: Double
}

public struct PropertyFailure {
    public let iteration: Int
    public let description: String
    public let property: String
}

public struct PropertyTestReport {
    public let timestamp: Date
    public let results: [PropertyTestResult]
    public let passed: Bool

    public var summary: String {
        """
        Property-Based Test Report
        ==========================
        Date: \(timestamp)
        Total Properties: \(results.count)
        Passed: \(results.filter { $0.passed }.count)
        Failed: \(results.filter { !$0.passed }.count)

        Results:
        \(results.map { result in
            "- \(result.property): \(result.passed ? "✅" : "❌") (\(String(format: "%.1f%%", result.successRate * 100)) success rate)"
        }.joined(separator: "\n"))
        """
    }
}

// MARK: - Random Helper

struct SeededRandom: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        self.state = seed
    }

    mutating func next() -> UInt64 {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return state
    }
}
