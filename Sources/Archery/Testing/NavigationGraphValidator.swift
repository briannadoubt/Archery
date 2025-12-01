import Foundation

// MARK: - Navigation Graph Validation

public struct NavValidationNode: Hashable {
    public let id: String
    public let type: NavigationType
    public let destinations: Set<String>
    public let requiredAuth: Bool
    public let deepLinkable: Bool
    
    public init(
        id: String,
        type: NavigationType,
        destinations: Set<String> = [],
        requiredAuth: Bool = false,
        deepLinkable: Bool = false
    ) {
        self.id = id
        self.type = type
        self.destinations = destinations
        self.requiredAuth = requiredAuth
        self.deepLinkable = deepLinkable
    }
}

public enum NavigationType {
    case root
    case tab
    case screen
    case modal
    case sheet
    case alert
}

public struct NavValidationGraph {
    public let nodes: [String: NavValidationNode]
    public let rootId: String
    
    public init(nodes: [NavValidationNode], rootId: String) {
        self.nodes = Dictionary(uniqueKeysWithValues: nodes.map { ($0.id, $0) })
        self.rootId = rootId
    }
    
    public func validate() -> [NavigationValidationError] {
        var errors: [NavigationValidationError] = []
        
        // Check root exists
        guard nodes[rootId] != nil else {
            errors.append(.missingRoot(rootId))
            return errors
        }
        
        // Check for orphaned nodes
        let reachable = findReachableNodes(from: rootId)
        let orphaned = Set(nodes.keys).subtracting(reachable)
        for nodeId in orphaned {
            errors.append(.orphanedNode(nodeId))
        }
        
        // Check for cycles
        if let cycle = findCycle() {
            errors.append(.cycle(cycle))
        }
        
        // Check for missing destinations
        for node in nodes.values {
            for destination in node.destinations {
                if nodes[destination] == nil {
                    errors.append(.missingDestination(from: node.id, to: destination))
                }
            }
        }
        
        // Check auth requirements
        for node in nodes.values where node.requiredAuth {
            if !hasPathToAuth(from: rootId, to: node.id) {
                errors.append(.inaccessibleAuthRequired(node.id))
            }
        }
        
        // Check deep link accessibility
        for node in nodes.values where node.deepLinkable {
            if !reachable.contains(node.id) {
                errors.append(.deepLinkToUnreachable(node.id))
            }
        }
        
        return errors
    }
    
    private func findReachableNodes(from startId: String) -> Set<String> {
        var visited = Set<String>()
        var queue = [startId]
        
        while !queue.isEmpty {
            let current = queue.removeFirst()
            if visited.contains(current) { continue }
            visited.insert(current)
            
            if let node = nodes[current] {
                queue.append(contentsOf: node.destinations)
            }
        }
        
        return visited
    }
    
    private func findCycle() -> [String]? {
        var visited = Set<String>()
        var recursionStack = Set<String>()
        var path: [String] = []
        
        for nodeId in nodes.keys {
            if !visited.contains(nodeId) {
                if let cycle = dfs(nodeId: nodeId, visited: &visited, recursionStack: &recursionStack, path: &path) {
                    return cycle
                }
            }
        }
        
        return nil
    }
    
    private func dfs(
        nodeId: String,
        visited: inout Set<String>,
        recursionStack: inout Set<String>,
        path: inout [String]
    ) -> [String]? {
        visited.insert(nodeId)
        recursionStack.insert(nodeId)
        path.append(nodeId)
        
        if let node = nodes[nodeId] {
            for destination in node.destinations {
                if !visited.contains(destination) {
                    if let cycle = dfs(nodeId: destination, visited: &visited, recursionStack: &recursionStack, path: &path) {
                        return cycle
                    }
                } else if recursionStack.contains(destination) {
                    // Found cycle
                    if let startIndex = path.firstIndex(of: destination) {
                        return Array(path[startIndex...])
                    }
                }
            }
        }
        
        recursionStack.remove(nodeId)
        path.removeLast()
        return nil
    }
    
    private func hasPathToAuth(from: String, to: String) -> Bool {
        // Simplified - check if there's a path that doesn't require auth
        // In practice, this would be more sophisticated
        return findReachableNodes(from: from).contains(to)
    }
}

public enum NavigationValidationError: Error, Equatable {
    case missingRoot(String)
    case orphanedNode(String)
    case cycle([String])
    case missingDestination(from: String, to: String)
    case inaccessibleAuthRequired(String)
    case deepLinkToUnreachable(String)
}

// MARK: - Navigation Test Builder

public struct NavigationTestBuilder {
    private var nodes: [NavValidationNode] = []
    private var currentNode: NavValidationNode?
    
    public init() {}
    
    public func root(_ id: String) -> Self {
        var builder = self
        let node = NavValidationNode(id: id, type: .root)
        builder.nodes.append(node)
        builder.currentNode = node
        return builder
    }
    
    public func tab(_ id: String, destinations: Set<String> = []) -> Self {
        var builder = self
        let node = NavValidationNode(id: id, type: .tab, destinations: destinations)
        builder.nodes.append(node)
        
        // Add to current node's destinations if it exists
        if let current = builder.currentNode,
           let index = builder.nodes.firstIndex(where: { $0.id == current.id }) {
            var updated = current
            var newDestinations = updated.destinations
            newDestinations.insert(id)
            updated = NavValidationNode(
                id: updated.id,
                type: updated.type,
                destinations: newDestinations,
                requiredAuth: updated.requiredAuth,
                deepLinkable: updated.deepLinkable
            )
            builder.nodes[index] = updated
        }
        
        return builder
    }
    
    public func screen(_ id: String, destinations: Set<String> = [], requiredAuth: Bool = false, deepLinkable: Bool = false) -> Self {
        var builder = self
        let node = NavValidationNode(
            id: id,
            type: .screen,
            destinations: destinations,
            requiredAuth: requiredAuth,
            deepLinkable: deepLinkable
        )
        builder.nodes.append(node)
        return builder
    }
    
    public func modal(_ id: String, destinations: Set<String> = []) -> Self {
        var builder = self
        let node = NavValidationNode(id: id, type: .modal, destinations: destinations)
        builder.nodes.append(node)
        return builder
    }
    
    public func build(rootId: String = "root") -> NavValidationGraph {
        NavValidationGraph(nodes: nodes, rootId: rootId)
    }
}

// MARK: - Navigation Coverage

public struct NavValidationCoverage {
    public let graph: NavValidationGraph
    public let visitedNodes: Set<String>
    public let visitedTransitions: Set<Transition>
    
    public struct Transition: Hashable {
        public let from: String
        public let to: String
    }
    
    public init(graph: NavValidationGraph) {
        self.graph = graph
        self.visitedNodes = []
        self.visitedTransitions = []
    }
    
    public var nodeCoverage: Double {
        Double(visitedNodes.count) / Double(graph.nodes.count)
    }
    
    public var transitionCoverage: Double {
        let totalTransitions = graph.nodes.values.reduce(0) { $0 + $1.destinations.count }
        guard totalTransitions > 0 else { return 1.0 }
        return Double(visitedTransitions.count) / Double(totalTransitions)
    }
    
    public var uncoveredNodes: Set<String> {
        Set(graph.nodes.keys).subtracting(visitedNodes)
    }
    
    public func generateReport() -> String {
        """
        Navigation Coverage Report:
        
        Node Coverage: \(String(format: "%.1f%%", nodeCoverage * 100))
        Transition Coverage: \(String(format: "%.1f%%", transitionCoverage * 100))
        
        Visited Nodes: \(visitedNodes.count)/\(graph.nodes.count)
        Visited Transitions: \(visitedTransitions.count)
        
        Uncovered Nodes:
        \(uncoveredNodes.sorted().map { "  - \($0)" }.joined(separator: "\n"))
        """
    }
}