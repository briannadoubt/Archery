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

public struct RateLimitingSampler: TelemetrySampler {
    private let maxPerSecond: Int
    private let lock = NSLock()
    private var currentSecond: Date = Date()
    private var currentCount: Int = 0

    public init(maxPerSecond: Int) {
        self.maxPerSecond = maxPerSecond
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
        // Note: Rate limiting uses a simple threshold - actual rate limiting
        // would require mutable state which is incompatible with Sendable
        // For production, consider using an actor-based approach with async methods
        Double.random(in: 0...1) < (1.0 / Double(max(maxPerSecond, 1)))
    }
}

// MARK: - Adaptive Sampler

public struct AdaptiveSampler: TelemetrySampler {
    private let targetRate: Int

    public init(targetRate: Int, windowSize: TimeInterval = 60) {
        self.targetRate = targetRate
    }

    public func shouldSample(span: Span) -> Bool {
        // Simplified: use target rate as probability threshold
        Double.random(in: 0...1) < (Double(targetRate) / 100.0)
    }

    public func shouldSampleMetric(metric: any Metric) -> Bool {
        Double.random(in: 0...1) < (Double(targetRate) / 100.0)
    }

    public func shouldSampleLog(log: LogEntry) -> Bool {
        Double.random(in: 0...1) < (Double(targetRate) / 100.0)
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
    public enum Strategy: Sendable {
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
    public enum Priority: Int, Sendable {
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

public struct TailSampler: TelemetrySampler {
    private let baseProbability: Double

    public init(decisionTimeout: TimeInterval = 30, maxBufferSize: Int = 10000) {
        self.baseProbability = 0.1
    }

    public func shouldSample(span: Span) -> Bool {
        // Always keep traces with errors
        if case .error = span.status {
            return true
        }

        // Always keep high priority traces
        if let priority = span.attributes["priority"],
           priority == "high" || priority == "critical" {
            return true
        }

        // Sample others probabilistically
        return Double.random(in: 0...1) < baseProbability
    }

    public func shouldSampleMetric(metric: any Metric) -> Bool {
        // Metrics use simple probability sampling
        return Double.random(in: 0...1) < baseProbability
    }

    public func shouldSampleLog(log: LogEntry) -> Bool {
        // Sample all error logs, sample others probabilistically
        switch log.level {
        case .error, .critical:
            return true
        default:
            return Double.random(in: 0...1) < baseProbability
        }
    }
}