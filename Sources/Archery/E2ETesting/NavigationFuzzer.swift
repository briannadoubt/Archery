import SwiftUI
import Combine

// MARK: - Navigation Graph Fuzzer

/// Fuzzes navigation paths to find invalid routes and crashes
public final class NavigationFuzzer {
    
    private let graph: NavigationGraph
    private let maxDepth: Int
    private let maxIterations: Int
    private let seed: UInt64?
    
    public init(
        graph: NavigationGraph,
        maxDepth: Int = 10,
        maxIterations: Int = 1000,
        seed: UInt64? = nil
    ) {
        self.graph = graph
        self.maxDepth = maxDepth
        self.maxIterations = maxIterations
        self.seed = seed
    }
    
    // MARK: - Fuzzing
    
    /// Run fuzzing session
    public func fuzz() async -> FuzzingReport {
        let startTime = Date()
        var results: [FuzzingResult] = []
        var crashes: [FuzzCrashReport] = []
        var invalidRoutes: [InvalidRoute] = []

        // Initialize random generator
        var generator = SeededRandomNumberGenerator(seed: seed ?? UInt64.random(in: 0...UInt64.max))
        
        for iteration in 0..<maxIterations {
            let result = await fuzzIteration(
                iteration: iteration,
                generator: &generator
            )
            
            results.append(result)
            
            if let crash = result.crash {
                crashes.append(crash)
            }
            
            invalidRoutes.append(contentsOf: result.invalidRoutes)
            
            // Early exit if critical crash
            if result.crash?.severity == .critical {
                break
            }
        }
        
        return FuzzingReport(
            timestamp: Date(),
            duration: Date().timeIntervalSince(startTime),
            iterations: results.count,
            results: results,
            crashes: crashes,
            invalidRoutes: invalidRoutes,
            coverage: calculateCoverage(results)
        )
    }
    
    private func fuzzIteration(
        iteration: Int,
        generator: inout some RandomNumberGenerator
    ) async -> FuzzingResult {
        var path: [NavigationNode] = []
        var currentNode = graph.root
        var invalidRoutes: [InvalidRoute] = []
        var crash: FuzzCrashReport?
        
        // Random walk through navigation graph
        for depth in 0..<maxDepth {
            // Get available actions from current node
            let actions = graph.availableActions(from: currentNode)
            
            guard !actions.isEmpty else {
                // Dead end
                break
            }
            
            // Choose random action
            let action = actions.randomElement(using: &generator)!
            
            // Try to perform action
            let result = await performAction(action, from: currentNode)
            
            switch result {
            case .success(let nextNode):
                path.append(nextNode)
                currentNode = nextNode
                
            case .invalid(let reason):
                invalidRoutes.append(InvalidRoute(
                    from: currentNode,
                    action: action,
                    reason: reason
                ))
                break
                
            case .crashed(let error):
                crash = FuzzCrashReport(
                    iteration: iteration,
                    path: path,
                    action: action,
                    error: error,
                    severity: categorizeCrash(error)
                )
                break
            }
            
            // Random backtrack
            if Bool.random(using: &generator) && path.count > 1 {
                path.removeLast()
                currentNode = path.last ?? graph.root
            }
        }
        
        return FuzzingResult(
            iteration: iteration,
            path: path,
            invalidRoutes: invalidRoutes,
            crash: crash
        )
    }
    
    private func performAction(
        _ action: NavigationAction,
        from node: NavigationNode
    ) async -> ActionResult {
        do {
            // Simulate navigation action
            let nextNode = try await graph.navigate(from: node, via: action)
            
            // Validate the transition
            if !graph.isValidTransition(from: node, to: nextNode, via: action) {
                return .invalid("Invalid state transition")
            }
            
            return .success(nextNode)
            
        } catch {
            return .crashed(error)
        }
    }
    
    // MARK: - Coverage Calculation
    
    private func calculateCoverage(_ results: [FuzzingResult]) -> NavigationCoverage {
        let allPaths = results.flatMap { $0.path }
        let uniqueNodes = Set(allPaths)
        let visitedTransitions = calculateTransitions(from: results)
        
        return NavigationCoverage(
            nodesCovered: uniqueNodes.count,
            totalNodes: graph.allNodes.count,
            transitionsCovered: visitedTransitions.count,
            totalTransitions: graph.allTransitions.count,
            percentageCovered: Double(uniqueNodes.count) / Double(max(graph.allNodes.count, 1))
        )
    }
    
    private func calculateTransitions(from results: [FuzzingResult]) -> Set<NavigationTransition> {
        var transitions = Set<NavigationTransition>()
        
        for result in results {
            for i in 0..<max(result.path.count - 1, 0) {
                transitions.insert(NavigationTransition(
                    from: result.path[i],
                    to: result.path[i + 1]
                ))
            }
        }
        
        return transitions
    }
    
    private func categorizeCrash(_ error: Error) -> CrashSeverity {
        // Categorize based on error type
        if error is FatalError {
            return .critical
        } else if error is RecoverableError {
            return .medium
        } else {
            return .low
        }
    }
}

// MARK: - Navigation Graph

public struct NavigationGraph {
    public let root: NavigationNode
    public let allNodes: Set<NavigationNode>
    public let allTransitions: Set<NavigationTransition>
    private let transitions: [NavigationNode: [NavigationAction: NavigationNode]]
    
    public init(
        root: NavigationNode,
        transitions: [NavigationNode: [NavigationAction: NavigationNode]]
    ) {
        self.root = root
        self.transitions = transitions
        
        // Calculate all nodes
        var nodes = Set<NavigationNode>()
        nodes.insert(root)
        for (node, destinations) in transitions {
            nodes.insert(node)
            nodes.formUnion(destinations.values)
        }
        self.allNodes = nodes
        
        // Calculate all transitions
        var allTrans = Set<NavigationTransition>()
        for (from, destinations) in transitions {
            for to in destinations.values {
                allTrans.insert(NavigationTransition(from: from, to: to))
            }
        }
        self.allTransitions = allTrans
    }
    
    func availableActions(from node: NavigationNode) -> [NavigationAction] {
        transitions[node].map { Array($0.keys) } ?? []
    }
    
    func navigate(from node: NavigationNode, via action: NavigationAction) async throws -> NavigationNode {
        guard let nextNode = transitions[node]?[action] else {
            throw NavigationError.invalidRoute
        }
        
        // Simulate navigation delay
        try await Task.sleep(nanoseconds: UInt64.random(in: 10_000...100_000))
        
        // Random crash for testing
        if Int.random(in: 0..<100) < 1 {
            throw NavigationError.randomCrash
        }
        
        return nextNode
    }
    
    func isValidTransition(from: NavigationNode, to: NavigationNode, via action: NavigationAction) -> Bool {
        transitions[from]?[action] == to
    }
}

// MARK: - Navigation Types

public struct NavigationNode: Hashable, CustomStringConvertible {
    public let id: String
    public let type: NodeType

    public enum NodeType: Hashable {
        case root
        case tab(String)
        case screen(String)
        case modal(String)
        case alert(String)
    }

    public init(id: String, type: NodeType = .screen("")) {
        self.id = id
        self.type = type
    }

    public var description: String { id }
}

public enum NavigationAction: Hashable {
    case tap(String)
    case swipe(Direction)
    case back
    case dismiss
    case deepLink(String)
    
    public enum Direction {
        case left, right, up, down
    }
}

public struct NavigationTransition: Hashable {
    public let from: NavigationNode
    public let to: NavigationNode
}

// MARK: - Result Types

enum ActionResult {
    case success(NavigationNode)
    case invalid(String)
    case crashed(Error)
}

public struct FuzzingResult {
    public let iteration: Int
    public let path: [NavigationNode]
    public let invalidRoutes: [InvalidRoute]
    public let crash: FuzzCrashReport?
}

public struct InvalidRoute {
    public let from: NavigationNode
    public let action: NavigationAction
    public let reason: String
}

public struct FuzzCrashReport {
    public let iteration: Int
    public let path: [NavigationNode]
    public let action: NavigationAction
    public let error: Error
    public let severity: CrashSeverity
}

public enum CrashSeverity {
    case low, medium, high, critical
}

public struct FuzzingReport {
    public let timestamp: Date
    public let duration: TimeInterval
    public let iterations: Int
    public let results: [FuzzingResult]
    public let crashes: [FuzzCrashReport]
    public let invalidRoutes: [InvalidRoute]
    public let coverage: NavigationCoverage
    
    public var summary: String {
        """
        Navigation Fuzzing Report
        =========================
        Duration: \(String(format: "%.2f", duration))s
        Iterations: \(iterations)
        Crashes: \(crashes.count)
        Invalid Routes: \(invalidRoutes.count)
        Coverage: \(String(format: "%.1f%%", coverage.percentageCovered * 100))
        
        Critical Issues: \(crashes.filter { $0.severity == .critical }.count)
        High Issues: \(crashes.filter { $0.severity == .high }.count)
        Medium Issues: \(crashes.filter { $0.severity == .medium }.count)
        Low Issues: \(crashes.filter { $0.severity == .low }.count)
        """
    }
}

public struct NavigationCoverage {
    public let nodesCovered: Int
    public let totalNodes: Int
    public let transitionsCovered: Int
    public let totalTransitions: Int
    public let percentageCovered: Double
}

// MARK: - Errors

enum NavigationError: Error {
    case invalidRoute
    case randomCrash
}

protocol FatalError: Error {}
protocol RecoverableError: Error {}

// MARK: - Random Generator

struct SeededRandomNumberGenerator: RandomNumberGenerator {
    private var state: UInt64
    
    init(seed: UInt64) {
        self.state = seed
    }
    
    mutating func next() -> UInt64 {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return state
    }
}

// MARK: - Graph Builder

public struct NavigationGraphBuilder {
    
    /// Build graph from route definitions
    public static func buildFromRoutes(_ routes: [Route]) -> NavigationGraph {
        var transitions: [NavigationNode: [NavigationAction: NavigationNode]] = [:]
        let root = NavigationNode(id: "root", type: .root)
        
        // Build transitions from routes
        for route in routes {
            let fromNode = NavigationNode(id: route.from)
            let toNode = NavigationNode(id: route.to)
            let action = route.action
            
            if transitions[fromNode] == nil {
                transitions[fromNode] = [:]
            }
            transitions[fromNode]?[action] = toNode
        }
        
        // Add root transitions
        transitions[root] = [:]
        for route in routes where route.from == "root" {
            let toNode = NavigationNode(id: route.to)
            transitions[root]?[route.action] = toNode
        }
        
        return NavigationGraph(root: root, transitions: transitions)
    }
}

public struct Route {
    public let from: String
    public let to: String
    public let action: NavigationAction
    
    public init(from: String, to: String, action: NavigationAction) {
        self.from = from
        self.to = to
        self.action = action
    }
}