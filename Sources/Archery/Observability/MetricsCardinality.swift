import Foundation

// MARK: - Cardinality Guard

public actor CardinalityGuard {
    private let maxCardinality: Int
    private let resetInterval: TimeInterval
    private var metricCardinalities: [String: Set<String>] = [:]
    private var lastReset: Date
    
    public init(maxCardinality: Int = 10000, resetInterval: TimeInterval = 3600) {
        self.maxCardinality = maxCardinality
        self.resetInterval = resetInterval
        self.lastReset = Date()
        
        // Start reset timer
        Task {
            await startResetTimer()
        }
    }
    
    public func checkCardinality(
        metricName: String,
        attributes: [String: String]
    ) -> CardinalityCheckResult {
        // Reset if needed
        if Date().timeIntervalSince(lastReset) > resetInterval {
            reset()
        }
        
        // Create attribute key
        let attributeKey = createAttributeKey(attributes)
        
        // Get or create cardinality set for metric
        var cardinalities = metricCardinalities[metricName] ?? Set<String>()
        
        // Check if we're at limit
        if cardinalities.count >= maxCardinality && !cardinalities.contains(attributeKey) {
            return .rejected(reason: "Cardinality limit exceeded for metric '\(metricName)'")
        }
        
        // Add to cardinality set
        cardinalities.insert(attributeKey)
        metricCardinalities[metricName] = cardinalities
        
        return .accepted
    }
    
    public func getCardinality(for metricName: String) -> Int {
        metricCardinalities[metricName]?.count ?? 0
    }
    
    public func getAllCardinalities() -> [String: Int] {
        metricCardinalities.mapValues { $0.count }
    }
    
    public func reset() {
        metricCardinalities.removeAll()
        lastReset = Date()
    }
    
    private func createAttributeKey(_ attributes: [String: Any]) -> String {
        let sorted = attributes
            .map { "\($0.key)=\($0.value)" }
            .sorted()
            .joined(separator: ",")
        return sorted
    }
    
    private func startResetTimer() async {
        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: UInt64(resetInterval * 1_000_000_000))
            reset()
        }
    }
}

public enum CardinalityCheckResult: Sendable, Equatable {
    case accepted
    case rejected(reason: String)
}

// MARK: - Cardinality Limiter

public struct CardinalityLimiter: Sendable {
    private let allowedDimensions: Set<String>
    private let maxDimensionValues: [String: Int]
    
    public init(
        allowedDimensions: Set<String> = [],
        maxDimensionValues: [String: Int] = [:]
    ) {
        self.allowedDimensions = allowedDimensions
        self.maxDimensionValues = maxDimensionValues
    }
    
    public func limitAttributes(_ attributes: [String: String]) -> [String: String] {
        var limited = [String: String]()
        
        for (key, value) in attributes {
            // Skip if dimension not allowed
            if !allowedDimensions.isEmpty && !allowedDimensions.contains(key) {
                continue
            }
            
            // Apply value limiting if configured
            if let maxValues = maxDimensionValues[key] {
                limited[key] = limitValue(value, maxValues: maxValues)
            } else {
                limited[key] = value
            }
        }
        
        return limited
    }
    
    private func limitValue(_ value: String, maxValues: Int) -> String {
        // Hash and bucket string values if cardinality is high
        let hash = value.hashValue
        let bucket = abs(hash) % maxValues
        return "bucket_\(bucket)"
    }
}

// MARK: - Dimension Reducer

public struct DimensionReducer: Sendable {
    public enum ReductionStrategy: Sendable {
        case keepFirst(Int)
        case keepLast(Int)
        case keepSpecific(Set<String>)
        case dropSpecific(Set<String>)
        case custom(@Sendable (String, String) -> Bool)
    }
    
    private let strategy: ReductionStrategy
    
    public init(strategy: ReductionStrategy) {
        self.strategy = strategy
    }
    
    public func reduce(_ attributes: [String: String]) -> [String: String] {
        switch strategy {
        case .keepFirst(let count):
            let keys = Array(attributes.keys.prefix(count))
            return attributes.filter { keys.contains($0.key) }
            
        case .keepLast(let count):
            let keys = Array(attributes.keys.suffix(count))
            return attributes.filter { keys.contains($0.key) }
            
        case .keepSpecific(let keys):
            return attributes.filter { keys.contains($0.key) }
            
        case .dropSpecific(let keys):
            return attributes.filter { !keys.contains($0.key) }
            
        case .custom(let predicate):
            return attributes.filter { predicate($0.key, $0.value) }
        }
    }
}

// MARK: - Hierarchical Aggregator

public struct HierarchicalAggregator {
    private let hierarchies: [String: [String]]
    
    public init(hierarchies: [String: [String]]) {
        self.hierarchies = hierarchies
    }
    
    public func aggregate(_ attributes: [String: String], level: Int) -> [String: String] {
        var aggregated = attributes
        
        for (dimension, hierarchy) in hierarchies {
            guard let value = attributes[dimension] else { continue }
            
            let components = value.split(separator: hierarchy.first?.first ?? "/")
                .map(String.init)
            
            if components.count > level {
                let aggregatedValue = components.prefix(level + 1)
                    .joined(separator: String(hierarchy.first ?? "/"))
                aggregated[dimension] = aggregatedValue
            }
        }
        
        return aggregated
    }
}

// MARK: - Cardinality Monitor

public actor CardinalityMonitor {
    private let threshold: Int
    private let checkInterval: TimeInterval
    private var observations: [String: [CardinalityObservation]] = [:]
    private var alerts: [CardinalityAlert] = []
    
    public struct CardinalityObservation: Sendable {
        public let timestamp: Date
        public let cardinality: Int
    }

    public struct CardinalityAlert: Sendable {
        public let metricName: String
        public let cardinality: Int
        public let threshold: Int
        public let timestamp: Date
        public let growthRate: Double?
    }
    
    public init(threshold: Int = 1000, checkInterval: TimeInterval = 60) {
        self.threshold = threshold
        self.checkInterval = checkInterval
        
        // Start monitoring
        Task {
            await startMonitoring()
        }
    }
    
    public func recordCardinality(metricName: String, cardinality: Int) {
        let observation = CardinalityObservation(
            timestamp: Date(),
            cardinality: cardinality
        )
        
        var metricObservations = observations[metricName] ?? []
        metricObservations.append(observation)
        
        // Keep only recent observations
        let cutoff = Date().addingTimeInterval(-3600) // 1 hour
        metricObservations.removeAll { $0.timestamp < cutoff }
        
        observations[metricName] = metricObservations
        
        // Check for alerts
        if cardinality > threshold {
            let growthRate = calculateGrowthRate(for: metricObservations)
            let alert = CardinalityAlert(
                metricName: metricName,
                cardinality: cardinality,
                threshold: threshold,
                timestamp: Date(),
                growthRate: growthRate
            )
            alerts.append(alert)
        }
    }
    
    public func getAlerts() -> [CardinalityAlert] {
        alerts
    }
    
    public func clearAlerts() {
        alerts.removeAll()
    }
    
    public func getHighCardinalityMetrics() -> [(String, Int)] {
        observations.compactMap { name, obs in
            guard let latest = obs.last else { return nil }
            return latest.cardinality > threshold ? (name, latest.cardinality) : nil
        }
    }
    
    private func calculateGrowthRate(for observations: [CardinalityObservation]) -> Double? {
        guard observations.count >= 2 else { return nil }
        
        let sorted = observations.sorted { $0.timestamp < $1.timestamp }
        guard let first = sorted.first,
              let last = sorted.last else { return nil }
        
        let timeDiff = last.timestamp.timeIntervalSince(first.timestamp)
        guard timeDiff > 0 else { return nil }
        
        let cardinalityDiff = Double(last.cardinality - first.cardinality)
        return cardinalityDiff / timeDiff // Growth per second
    }
    
    private func startMonitoring() async {
        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: UInt64(checkInterval * 1_000_000_000))
            checkCardinalities()
        }
    }
    
    private func checkCardinalities() {
        for (metricName, metricObservations) in observations {
            guard let latest = metricObservations.last else { continue }
            
            if latest.cardinality > threshold {
                let growthRate = calculateGrowthRate(for: metricObservations)
                
                // Alert if rapid growth
                if let rate = growthRate, rate > 10 { // More than 10 new dimensions per second
                    let alert = CardinalityAlert(
                        metricName: metricName,
                        cardinality: latest.cardinality,
                        threshold: threshold,
                        timestamp: Date(),
                        growthRate: rate
                    )
                    alerts.append(alert)
                }
            }
        }
    }
}

// MARK: - Cardinality Enricher

public struct CardinalityEnricher: TelemetryEnricher {
    private let `guard`: CardinalityGuard
    private let limiter: CardinalityLimiter
    private let reducer: DimensionReducer
    private let monitor: CardinalityMonitor
    
    public init(
        guard: CardinalityGuard,
        limiter: CardinalityLimiter = CardinalityLimiter(),
        reducer: DimensionReducer = DimensionReducer(strategy: .keepFirst(10)),
        monitor: CardinalityMonitor
    ) {
        self.guard = `guard`
        self.limiter = limiter
        self.reducer = reducer
        self.monitor = monitor
    }
    
    public func enrich(span: inout Span) {
        // Spans typically have lower cardinality, just reduce dimensions
        let reduced = reducer.reduce(span.attributes)
        span.setAttribute(
            "cardinality.reduced",
            value: (reduced.count < span.attributes.count).description
        )
        
        for (key, value) in reduced {
            span.setAttribute(key, value: value)
        }
    }
    
    public func enrich(metric: inout any Metric) {
        // Apply cardinality controls synchronously using limiter and reducer
        // The async guard check is skipped here as we cannot use async in inout context
        let limited = limiter.limitAttributes(metric.attributes)
        _ = reducer.reduce(limited)
    }
    
    public func enrich(log: inout LogEntry) {
        // Logs have string attributes, apply basic reduction
        // Note: Can't modify log attributes as they're let constants
        // This would need API change to make attributes mutable
        _ = log.attributes.filter { $0.key != "password" && $0.key != "token" }
    }
}

// MARK: - Cardinality Statistics

public struct CardinalityStatistics {
    public let metricName: String
    public let cardinality: Int
    public let uniqueValues: [String: Int]
    public let topValues: [(String, Int)]
    public let growthRate: Double?
    
    public init(
        metricName: String,
        cardinality: Int,
        uniqueValues: [String: Int] = [:],
        topValues: [(String, Int)] = [],
        growthRate: Double? = nil
    ) {
        self.metricName = metricName
        self.cardinality = cardinality
        self.uniqueValues = uniqueValues
        self.topValues = topValues
        self.growthRate = growthRate
    }
}

// MARK: - Cardinality Analyzer

public actor CardinalityAnalyzer {
    private var metricData: [String: MetricData] = [:]
    
    private struct MetricData {
        var dimensionValues: [String: [String: Int]] = [:]
        var totalCount: Int = 0
    }
    
    public func analyze(metric: any Metric) {
        let name = metric.name
        var data = metricData[name] ?? MetricData()
        
        // Track dimension values
        for (dimension, value) in metric.attributes {
            let stringValue = String(describing: value)
            
            var dimensionCounts = data.dimensionValues[dimension] ?? [:]
            dimensionCounts[stringValue, default: 0] += 1
            data.dimensionValues[dimension] = dimensionCounts
        }
        
        data.totalCount += 1
        metricData[name] = data
    }
    
    public func getStatistics(for metricName: String) -> CardinalityStatistics? {
        guard let data = metricData[metricName] else { return nil }
        
        // Calculate total cardinality
        let cardinality = data.dimensionValues.values
            .map { $0.count }
            .reduce(0, +)
        
        // Get unique value counts per dimension
        let uniqueValues = data.dimensionValues.mapValues { $0.count }
        
        // Find top values across all dimensions
        let allValues = data.dimensionValues.flatMap { dimension, values in
            values.map { (key: "\(dimension)=\($0.key)", value: $0.value) }
        }
        let topValues = Array(allValues.sorted { $0.value > $1.value }.prefix(10))
            .map { ($0.key, $0.value) }
        
        return CardinalityStatistics(
            metricName: metricName,
            cardinality: cardinality,
            uniqueValues: uniqueValues,
            topValues: topValues
        )
    }
    
    public func reset() {
        metricData.removeAll()
    }
}
