import Foundation

// MARK: - Property-Based Testing

public protocol Arbitrary {
    static func arbitrary() -> Self
    static func arbitrary(size: Int) -> Self
    func shrink() -> [Self]
}

// MARK: - Generators

public struct Gen<T> {
    public let generate: (Int) -> T
    
    public init(generate: @escaping (Int) -> T) {
        self.generate = generate
    }
    
    public func map<U>(_ transform: @escaping (T) -> U) -> Gen<U> {
        Gen<U> { size in
            transform(self.generate(size))
        }
    }
    
    public func flatMap<U>(_ transform: @escaping (T) -> Gen<U>) -> Gen<U> {
        Gen<U> { size in
            transform(self.generate(size)).generate(size)
        }
    }
    
    public func filter(_ predicate: @escaping (T) -> Bool) -> Gen<T> {
        Gen { size in
            var value = self.generate(size)
            var attempts = 0
            while !predicate(value) && attempts < 100 {
                value = self.generate(size)
                attempts += 1
            }
            return value
        }
    }
}

// MARK: - Built-in Generators

public extension Gen where T == Int {
    static func int(in range: ClosedRange<Int> = Int.min...Int.max) -> Gen<Int> {
        Gen { _ in
            Int.random(in: range)
        }
    }
    
    static func positive(max: Int = Int.max) -> Gen<Int> {
        Gen { _ in
            Int.random(in: 1...max)
        }
    }
}

public extension Gen where T == String {
    static func string(length: Int? = nil, characters: String = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789") -> Gen<String> {
        Gen { size in
            let len = length ?? Int.random(in: 0...size)
            return String((0..<len).map { _ in characters.randomElement()! })
        }
    }
    
    static func alphanumeric(length: Int? = nil) -> Gen<String> {
        string(length: length)
    }
    
    static func email() -> Gen<String> {
        Gen { _ in
            let user = String((0..<10).map { _ in "abcdefghijklmnopqrstuvwxyz".randomElement()! })
            let domain = String((0..<8).map { _ in "abcdefghijklmnopqrstuvwxyz".randomElement()! })
            return "\(user)@\(domain).com"
        }
    }
}

public extension Gen where T == Bool {
    static func bool() -> Gen<Bool> {
        Gen { _ in Bool.random() }
    }
}

public extension Gen where T == [Any] {
    static func array<Element>(of elementGen: Gen<Element>, count: Int? = nil) -> Gen<[Element]> {
        Gen<[Element]> { size in
            let len = count ?? Int.random(in: 0...size)
            return (0..<len).map { _ in elementGen.generate(size) }
        }
    }
}

// MARK: - Property Testing

public struct Property<T> {
    public let name: String
    public let generator: Gen<T>
    public let test: (T) throws -> Bool
    
    public init(
        _ name: String,
        generator: Gen<T>,
        test: @escaping (T) throws -> Bool
    ) {
        self.name = name
        self.generator = generator
        self.test = test
    }
    
    public func check(iterations: Int = 100, maxSize: Int = 100) -> PropertyResult {
        var failures: [(input: T, error: Error?)] = []
        var successCount = 0
        
        for i in 0..<iterations {
            let size = min(i, maxSize)
            let input = generator.generate(size)
            
            do {
                if try test(input) {
                    successCount += 1
                } else {
                    failures.append((input: input, error: nil))
                    if failures.count >= 10 { break }
                }
            } catch {
                failures.append((input: input, error: error))
                if failures.count >= 10 { break }
            }
        }
        
        return PropertyResult(
            name: name,
            passed: failures.isEmpty,
            iterations: successCount + failures.count,
            failures: failures.map { "\($0.input)" + ($0.error != nil ? " - Error: \($0.error!)" : "") }
        )
    }
}

public struct PropertyResult {
    public let name: String
    public let passed: Bool
    public let iterations: Int
    public let failures: [String]
    
    public var summary: String {
        if passed {
            return "✅ \(name): Passed (\(iterations) iterations)"
        } else {
            return """
            ❌ \(name): Failed
            Iterations: \(iterations)
            Failures:
            \(failures.prefix(5).enumerated().map { "  \($0.offset + 1). \($0.element)" }.joined(separator: "\n"))
            """
        }
    }
}

// MARK: - State Machine Testing

public protocol StateMachine {
    associatedtype State: Equatable
    associatedtype Action
    
    var initialState: State { get }
    func transition(from state: State, action: Action) -> State
    func invariant(state: State) -> Bool
}

public struct StateMachineProperty<Machine: StateMachine> {
    public let machine: Machine
    public let actionGenerator: Gen<Machine.Action>
    
    public init(machine: Machine, actionGenerator: Gen<Machine.Action>) {
        self.machine = machine
        self.actionGenerator = actionGenerator
    }
    
    public func checkInvariants(steps: Int = 100, iterations: Int = 100) -> PropertyResult {
        let property = Property("State machine invariants", generator: Gen<[Machine.Action]>.array(of: actionGenerator, count: steps)) { actions in
            var state = machine.initialState
            
            // Check initial state invariant
            guard machine.invariant(state: state) else { return false }
            
            // Apply actions and check invariants
            for action in actions {
                state = machine.transition(from: state, action: action)
                guard machine.invariant(state: state) else { return false }
            }
            
            return true
        }
        
        return property.check(iterations: iterations)
    }
}

// MARK: - Fuzzing

public struct Fuzzer<Input> {
    public let name: String
    public let generator: Gen<Input>
    public let target: (Input) throws -> Void
    
    public init(
        name: String,
        generator: Gen<Input>,
        target: @escaping (Input) throws -> Void
    ) {
        self.name = name
        self.generator = generator
        self.target = target
    }
    
    public func fuzz(iterations: Int = 1000, maxSize: Int = 100) -> FuzzResult {
        var crashes: [(input: Input, error: Error)] = []
        var successCount = 0
        
        for i in 0..<iterations {
            let size = min(i, maxSize)
            let input = generator.generate(size)
            
            do {
                try target(input)
                successCount += 1
            } catch {
                crashes.append((input: input, error: error))
                if crashes.count >= 10 { break }
            }
        }
        
        return FuzzResult(
            name: name,
            iterations: successCount + crashes.count,
            crashes: crashes.map { FuzzResult.Crash(input: "\($0.input)", error: $0.error) }
        )
    }
}

public struct FuzzResult {
    public struct Crash {
        public let input: String
        public let error: Error
    }
    
    public let name: String
    public let iterations: Int
    public let crashes: [Crash]
    
    public var summary: String {
        if crashes.isEmpty {
            return "✅ \(name): No crashes found (\(iterations) iterations)"
        } else {
            return """
            ❌ \(name): Found \(crashes.count) crash(es)
            Iterations: \(iterations)
            Crashes:
            \(crashes.prefix(5).enumerated().map { 
                "  \($0.offset + 1). Input: \($0.element.input)\n     Error: \($0.element.error)"
            }.joined(separator: "\n"))
            """
        }
    }
}