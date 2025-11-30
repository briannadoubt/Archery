import Foundation

// MARK: - Always Sample

public struct AlwaysSampleSampler: TelemetrySampler {
    public init() {}
    
    public func shouldSample(span: Span) -> Bool {
        true
    }
    
    public func shouldSampleMetric(metric: any Metric) -> Bool {
        true
    }
    
    public func shouldSampleLog(log: LogEntry) -> Bool {
        true
    }
}

// MARK: - Never Sample

public struct NeverSampleSampler: TelemetrySampler {
    public init() {}
    
    public func shouldSample(span: Span) -> Bool {
        false
    }
    
    public func shouldSampleMetric(metric: any Metric) -> Bool {
        false
    }
    
    public func shouldSampleLog(log: LogEntry) -> Bool {
        false
    }
}

// MARK: - Probability Sampler

public struct ProbabilitySampler: TelemetrySampler {
    private let probability: Double
    
    public init(probability: Double) {
        self.probability = min(1.0, max(0.0, probability))
    }
    
    public func shouldSample(span: Span) -> Bool {
        // Use trace ID for consistent sampling decisions
        let hashValue = span.context.traceId.hashValue
        let sample = Double(abs(hashValue)) / Double(Int.max)
        return sample < probability
    }
    
    public func shouldSampleMetric(metric: any Metric) -> Bool {
        Double.random(in: 0...1) < probability
    }
    
    public func shouldSampleLog(log: LogEntry) -> Bool {
        Double.random(in: 0...1) < probability
    }
}

// MARK: - Rate Limiting Sampler

public actor RateLimitingSampler: TelemetrySampler {
    private let maxPerSecond: Int
    private var currentSecond: Date
    private var currentCount: Int
    
    public init(maxPerSecond: Int) {
        self.maxPerSecond = maxPerSecond
        self.currentSecond = Date()
        self.currentCount = 0
    }
    
    public func shouldSample(span: Span) -> Bool {
        checkRate()
    }
    
    public func shouldSampleMetric(metric: any Metric) -> Bool {
        checkRate()
    }
    
    public func shouldSampleLog(log: LogEntry) -> Bool {
        checkRate()
    }
    
    private func checkRate() -> Bool {
        let now = Date()
        
        // Reset counter if we're in a new second
        if now.timeIntervalSince(currentSecond) >= 1.0 {
            currentSecond = now
            currentCount = 0
        }
        
        // Check if we're under the limit
        if currentCount < maxPerSecond {
            currentCount += 1
            return true
        }
        
        return false
    }
}

// MARK: - Adaptive Sampler

public actor AdaptiveSampler: TelemetrySampler {
    private let targetRate: Int
    private let windowSize: TimeInterval
    private var window: SlidingWindow
    private var currentProbability: Double
    
    public init(targetRate: Int, windowSize: TimeInterval = 60) {
        self.targetRate = targetRate
        self.windowSize = windowSize
        self.window = SlidingWindow(windowSize: windowSize)
        self.currentProbability = 1.0
    }
    
    public func shouldSample(span: Span) -> Bool {
        updateProbability()
        let hashValue = span.context.traceId.hashValue
        let sample = Double(abs(hashValue)) / Double(Int.max)
        return sample < currentProbability
    }
    
    public func shouldSampleMetric(metric: any Metric) -> Bool {
        updateProbability()
        return Double.random(in: 0...1) < currentProbability
    }
    
    public func shouldSampleLog(log: LogEntry) -> Bool {
        updateProbability()
        return Double.random(in: 0...1) < currentProbability
    }
    
    private func updateProbability() {
        window.add(Date())
        let currentRate = window.rate
        
        if currentRate > Double(targetRate) {
            // Decrease probability if we're over target
            currentProbability *= 0.9
        } else if currentRate < Double(targetRate) * 0.8 {
            // Increase probability if we're well under target
            currentProbability = min(1.0, currentProbability * 1.1)
        }
    }
    
    private struct SlidingWindow {
        private let windowSize: TimeInterval
        private var events: [Date] = []
        
        init(windowSize: TimeInterval) {
            self.windowSize = windowSize
        }
        
        mutating func add(_ date: Date) {
            events.append(date)
            
            // Remove events outside window
            let cutoff = date.addingTimeInterval(-windowSize)
            events.removeAll { $0 < cutoff }
        }
        
        var rate: Double {
            guard !events.isEmpty else { return 0 }
            return Double(events.count) / windowSize
        }
    }
}

// MARK: - Parent-Based Sampler

public struct ParentBasedSampler: TelemetrySampler {
    private let rootSampler: any TelemetrySampler
    
    public init(rootSampler: any TelemetrySampler = ProbabilitySampler(probability: 0.1)) {
        self.rootSampler = rootSampler
    }
    
    public func shouldSample(span: Span) -> Bool {
        // If there's a parent span, inherit its sampling decision
        if span.context.parentSpanId != nil {
            return span.context.sampled
        }
        
        // Otherwise, use root sampler
        return rootSampler.shouldSample(span: span)
    }
    
    public func shouldSampleMetric(metric: any Metric) -> Bool {
        rootSampler.shouldSampleMetric(metric: metric)
    }
    
    public func shouldSampleLog(log: LogEntry) -> Bool {
        rootSampler.shouldSampleLog(log: log)
    }
}

// MARK: - Composite Sampler

public struct CompositeSampler: TelemetrySampler {
    public enum Strategy {
        case all  // All samplers must agree
        case any  // At least one sampler must agree
    }
    
    private let samplers: [any TelemetrySampler]
    private let strategy: Strategy
    
    public init(samplers: [any TelemetrySampler], strategy: Strategy = .all) {
        self.samplers = samplers
        self.strategy = strategy
    }
    
    public func shouldSample(span: Span) -> Bool {
        switch strategy {
        case .all:
            return samplers.allSatisfy { $0.shouldSample(span: span) }
        case .any:
            return samplers.contains { $0.shouldSample(span: span) }
        }
    }
    
    public func shouldSampleMetric(metric: any Metric) -> Bool {
        switch strategy {
        case .all:
            return samplers.allSatisfy { $0.shouldSampleMetric(metric: metric) }
        case .any:
            return samplers.contains { $0.shouldSampleMetric(metric: metric) }
        }
    }
    
    public func shouldSampleLog(log: LogEntry) -> Bool {
        switch strategy {
        case .all:
            return samplers.allSatisfy { $0.shouldSampleLog(log: log) }
        case .any:
            return samplers.contains { $0.shouldSampleLog(log: log) }
        }
    }
}

// MARK: - Priority Sampler

public struct PrioritySampler: TelemetrySampler {
    public enum Priority: Int {
        case low = 0
        case normal = 1
        case high = 2
        case critical = 3
    }
    
    private let thresholds: [Priority: Double]
    
    public init(thresholds: [Priority: Double] = [
        .low: 0.01,
        .normal: 0.1,
        .high: 0.5,
        .critical: 1.0
    ]) {
        self.thresholds = thresholds
    }
    
    public func shouldSample(span: Span) -> Bool {
        let priority = extractPriority(from: span.attributes)
        let threshold = thresholds[priority] ?? thresholds[.normal] ?? 0.1
        
        let hashValue = span.context.traceId.hashValue
        let sample = Double(abs(hashValue)) / Double(Int.max)
        return sample < threshold
    }
    
    public func shouldSampleMetric(metric: any Metric) -> Bool {
        let priority = extractPriority(from: metric.attributes)
        let threshold = thresholds[priority] ?? thresholds[.normal] ?? 0.1
        return Double.random(in: 0...1) < threshold
    }
    
    public func shouldSampleLog(log: LogEntry) -> Bool {
        let priority = logPriority(for: log.level)
        let threshold = thresholds[priority] ?? thresholds[.normal] ?? 0.1
        return Double.random(in: 0...1) < threshold
    }
    
    private func extractPriority(from attributes: [String: String]) -> Priority {
        guard let priorityValue = attributes["priority"] else {
            return .normal
        }
        
        switch priorityValue.lowercased() {
        case "low": return .low
        case "high": return .high
        case "critical": return .critical
        default: return .normal
        }
    }
    
    private func logPriority(for level: LogEntry.Level) -> Priority {
        switch level {
        case .trace, .debug:
            return .low
        case .info:
            return .normal
        case .warning:
            return .high
        case .error, .critical:
            return .critical
        }
    }
}

// MARK: - Error-Based Sampler

public struct ErrorBasedSampler: TelemetrySampler {
    private let baselineProbability: Double
    private let errorProbability: Double
    
    public init(baselineProbability: Double = 0.1, errorProbability: Double = 1.0) {
        self.baselineProbability = baselineProbability
        self.errorProbability = errorProbability
    }
    
    public func shouldSample(span: Span) -> Bool {
        let probability: Double
        
        switch span.status {
        case .error:
            probability = errorProbability
        default:
            probability = baselineProbability
        }
        
        let hashValue = span.context.traceId.hashValue
        let sample = Double(abs(hashValue)) / Double(Int.max)
        return sample < probability
    }
    
    public func shouldSampleMetric(metric: any Metric) -> Bool {
        // Check if metric indicates an error
        let isError = metric.attributes["error"] == "true"
        let probability = isError ? errorProbability : baselineProbability
        return Double.random(in: 0...1) < probability
    }
    
    public func shouldSampleLog(log: LogEntry) -> Bool {
        let probability: Double
        
        switch log.level {
        case .error, .critical:
            probability = errorProbability
        default:
            probability = baselineProbability
        }
        
        return Double.random(in: 0...1) < probability
    }
}

// MARK: - Tail Sampler

public actor TailSampler: TelemetrySampler {
    private let decisionTimeout: TimeInterval
    private let maxBufferSize: Int
    private var pendingDecisions: [String: PendingDecision] = [:]
    
    private struct PendingDecision {
        let traceId: String
        let startTime: Date
        var hasError: Bool = false
        var isHighPriority: Bool = false
        var spanCount: Int = 0
    }
    
    public init(decisionTimeout: TimeInterval = 30, maxBufferSize: Int = 10000) {
        self.decisionTimeout = decisionTimeout
        self.maxBufferSize = maxBufferSize
        
        // Start cleanup task
        Task {
            await startCleanupTimer()
        }
    }
    
    public func shouldSample(span: Span) -> Bool {
        let traceId = span.context.traceId
        
        // Get or create pending decision
        var decision = pendingDecisions[traceId] ?? PendingDecision(
            traceId: traceId,
            startTime: Date()
        )
        
        // Update decision factors
        decision.spanCount += 1
        
        if case .error = span.status {
            decision.hasError = true
        }
        
        if let priority = span.attributes["priority"],
           priority == "high" || priority == "critical" {
            decision.isHighPriority = true
        }
        
        pendingDecisions[traceId] = decision
        
        // Make sampling decision
        return shouldKeepTrace(decision)
    }
    
    public func shouldSampleMetric(metric: any Metric) -> Bool {
        // Metrics use simple probability sampling
        return Double.random(in: 0...1) < 0.1
    }
    
    public func shouldSampleLog(log: LogEntry) -> Bool {
        // Sample all error logs, sample others probabilistically
        switch log.level {
        case .error, .critical:
            return true
        default:
            return Double.random(in: 0...1) < 0.1
        }
    }
    
    private func shouldKeepTrace(_ decision: PendingDecision) -> Bool {
        // Always keep traces with errors
        if decision.hasError {
            return true
        }
        
        // Always keep high priority traces
        if decision.isHighPriority {
            return true
        }
        
        // Keep traces with many spans (likely important)
        if decision.spanCount > 10 {
            return true
        }
        
        // Sample others probabilistically
        return Double.random(in: 0...1) < 0.1
    }
    
    private func startCleanupTimer() async {
        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: UInt64(10 * 1_000_000_000)) // 10 seconds
            await cleanup()
        }
    }
    
    private func cleanup() {
        let cutoff = Date().addingTimeInterval(-decisionTimeout)
        pendingDecisions = pendingDecisions.filter { $0.value.startTime > cutoff }
        
        // Enforce max buffer size
        if pendingDecisions.count > maxBufferSize {
            let sorted = pendingDecisions.sorted { $0.value.startTime < $1.value.startTime }
            let toRemove = sorted.prefix(pendingDecisions.count - maxBufferSize)
            for (key, _) in toRemove {
                pendingDecisions.removeValue(forKey: key)
            }
        }
    }
}