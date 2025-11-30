import SwiftUI
import Combine
import os.log

// MARK: - View Diff Tracker

public final class ViewDiffTracker: ObservableObject {
    public static let shared = ViewDiffTracker()
    
    @Published public private(set) var renderStats: RenderStatistics = .init()
    @Published public private(set) var isTracking: Bool = false
    
    private var renderEvents: [RenderEvent] = []
    private let queue = DispatchQueue(label: "com.archery.viewdiff")
    private let log = OSLog(subsystem: "com.archery.performance", category: "viewdiff")
    private let maxEvents = 1000
    
    public struct RenderStatistics {
        public var totalRenders: Int = 0
        public var unnecessaryRenders: Int = 0
        public var averageRenderTime: TimeInterval = 0
        public var slowestView: String?
        public var slowestRenderTime: TimeInterval = 0
        public var hotspots: [String: Int] = [:]
        
        public var unnecessaryRenderPercentage: Double {
            guard totalRenders > 0 else { return 0 }
            return Double(unnecessaryRenders) / Double(totalRenders) * 100
        }
    }
    
    public struct RenderEvent: Sendable {
        public let viewName: String
        public let timestamp: Date
        public let duration: TimeInterval
        public let trigger: RenderTrigger
        public let wasNecessary: Bool
        public let previousState: String?
        public let currentState: String?
        
        public enum RenderTrigger: String, Sendable {
            case stateChange = "state"
            case parentRender = "parent"
            case environmentChange = "environment"
            case binding = "binding"
            case gesture = "gesture"
            case animation = "animation"
            case unknown = "unknown"
        }
    }
    
    private init() {
        #if DEBUG
        self.isTracking = ProcessInfo.processInfo.environment["TRACK_VIEW_DIFFS"] == "1"
        #endif
    }
    
    public func startTracking() {
        isTracking = true
    }
    
    public func stopTracking() {
        isTracking = false
    }
    
    // MARK: - Recording
    
    public func recordRender(
        view: String,
        duration: TimeInterval,
        trigger: RenderEvent.RenderTrigger,
        previousState: String? = nil,
        currentState: String? = nil
    ) {
        guard isTracking else { return }
        
        let wasNecessary = previousState != currentState
        
        let event = RenderEvent(
            viewName: view,
            timestamp: Date(),
            duration: duration,
            trigger: trigger,
            wasNecessary: wasNecessary,
            previousState: previousState,
            currentState: currentState
        )
        
        queue.async { [weak self] in
            self?.processRenderEvent(event)
        }
    }
    
    private func processRenderEvent(_ event: RenderEvent) {
        renderEvents.append(event)
        if renderEvents.count > maxEvents {
            renderEvents.removeFirst(renderEvents.count - maxEvents)
        }
        
        updateStatistics(with: event)
        
        if !event.wasNecessary {
            os_log(
                .debug,
                log: log,
                "Unnecessary render detected: %{public}@ (trigger: %{public}@)",
                event.viewName,
                event.trigger.rawValue
            )
        }
        
        if event.duration > 0.016 { // More than 16ms (60fps threshold)
            os_log(
                .info,
                log: log,
                "Slow render detected: %{public}@ took %{public}.2fms",
                event.viewName,
                event.duration * 1000
            )
        }
    }
    
    private func updateStatistics(with event: RenderEvent) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            self.renderStats.totalRenders += 1
            if !event.wasNecessary {
                self.renderStats.unnecessaryRenders += 1
            }
            
            // Update average render time
            let currentAvg = self.renderStats.averageRenderTime
            let currentCount = self.renderStats.totalRenders - 1
            self.renderStats.averageRenderTime = (currentAvg * Double(currentCount) + event.duration) / Double(self.renderStats.totalRenders)
            
            // Track slowest render
            if event.duration > self.renderStats.slowestRenderTime {
                self.renderStats.slowestRenderTime = event.duration
                self.renderStats.slowestView = event.viewName
            }
            
            // Update hotspots
            self.renderStats.hotspots[event.viewName, default: 0] += 1
        }
    }
    
    // MARK: - Analysis
    
    public func analyzeRenderPatterns() -> RenderAnalysis {
        queue.sync {
            RenderAnalysis(
                events: renderEvents,
                statistics: renderStats,
                patterns: identifyPatterns(),
                recommendations: generateRecommendations()
            )
        }
    }
    
    private func identifyPatterns() -> [RenderPattern] {
        var patterns: [RenderPattern] = []
        
        // Identify render cascades
        let cascades = findRenderCascades()
        if !cascades.isEmpty {
            patterns.append(.renderCascade(views: cascades))
        }
        
        // Identify frequent re-renders
        let frequent = findFrequentRerenders()
        if !frequent.isEmpty {
            patterns.append(.frequentRerenders(views: frequent))
        }
        
        // Identify animation-triggered renders
        let animationRenders = renderEvents.filter { $0.trigger == .animation }
        if animationRenders.count > renderEvents.count / 3 {
            patterns.append(.excessiveAnimations(count: animationRenders.count))
        }
        
        return patterns
    }
    
    private func findRenderCascades() -> [String] {
        var cascades: [String] = []
        var lastTimestamp = Date.distantPast
        var cascade: [String] = []
        
        for event in renderEvents {
            if event.timestamp.timeIntervalSince(lastTimestamp) < 0.001 { // Within 1ms
                cascade.append(event.viewName)
            } else {
                if cascade.count > 3 {
                    cascades.append(contentsOf: cascade)
                }
                cascade = [event.viewName]
            }
            lastTimestamp = event.timestamp
        }
        
        return Array(Set(cascades))
    }
    
    private func findFrequentRerenders() -> [String] {
        renderStats.hotspots
            .filter { $0.value > 100 }
            .map { $0.key }
    }
    
    private func generateRecommendations() -> [String] {
        var recommendations: [String] = []
        
        if renderStats.unnecessaryRenderPercentage > 20 {
            recommendations.append("High unnecessary render rate (\(String(format: "%.1f%%", renderStats.unnecessaryRenderPercentage))). Consider using @StateObject or memoization.")
        }
        
        if renderStats.averageRenderTime > 0.008 {
            recommendations.append("Average render time exceeds 8ms. Profile with Instruments to identify bottlenecks.")
        }
        
        if let slowest = renderStats.slowestView, renderStats.slowestRenderTime > 0.016 {
            recommendations.append("\(slowest) has slow renders (\(String(format: "%.1fms", renderStats.slowestRenderTime * 1000))). Consider breaking into smaller views.")
        }
        
        return recommendations
    }
    
    public enum RenderPattern {
        case renderCascade(views: [String])
        case frequentRerenders(views: [String])
        case excessiveAnimations(count: Int)
        
        public var description: String {
            switch self {
            case .renderCascade(let views):
                return "Render cascade detected: \(views.joined(separator: " -> "))"
            case .frequentRerenders(let views):
                return "Frequent re-renders: \(views.joined(separator: ", "))"
            case .excessiveAnimations(let count):
                return "Excessive animation renders: \(count)"
            }
        }
    }
    
    public struct RenderAnalysis {
        public let events: [RenderEvent]
        public let statistics: RenderStatistics
        public let patterns: [RenderPattern]
        public let recommendations: [String]
        
        public var summary: String {
            """
            View Diff Analysis
            ==================
            Total Renders: \(statistics.totalRenders)
            Unnecessary: \(statistics.unnecessaryRenders) (\(String(format: "%.1f%%", statistics.unnecessaryRenderPercentage)))
            Average Time: \(String(format: "%.2fms", statistics.averageRenderTime * 1000))
            Slowest View: \(statistics.slowestView ?? "N/A") (\(String(format: "%.2fms", statistics.slowestRenderTime * 1000)))
            
            Patterns Detected:
            \(patterns.map { "  - \($0.description)" }.joined(separator: "\n"))
            
            Recommendations:
            \(recommendations.map { "  • \($0)" }.joined(separator: "\n"))
            """
        }
    }
    
    // MARK: - Export
    
    public func exportReport(to url: URL) throws {
        let analysis = analyzeRenderPatterns()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(analysis)
        try data.write(to: url)
    }
}

// MARK: - View Modifier for Diff Tracking

public struct DiffTracked: ViewModifier {
    let name: String
    @State private var previousState: String = ""
    @State private var renderStart: CFAbsoluteTime = 0
    
    public func body(content: Content) -> some View {
        content
            .onAppear {
                renderStart = CFAbsoluteTimeGetCurrent()
            }
            .onChange(of: previousState) { oldValue, newValue in
                let duration = CFAbsoluteTimeGetCurrent() - renderStart
                ViewDiffTracker.shared.recordRender(
                    view: name,
                    duration: duration,
                    trigger: .stateChange,
                    previousState: oldValue,
                    currentState: newValue
                )
                renderStart = CFAbsoluteTimeGetCurrent()
            }
    }
}

public extension View {
    func trackDiff(_ name: String) -> some View {
        modifier(DiffTracked(name: name))
    }
}

// MARK: - Debug View for Render Stats

public struct RenderStatsView: View {
    @ObservedObject private var tracker = ViewDiffTracker.shared
    
    public init() {}
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Render Statistics")
                .font(.headline)
            
            HStack {
                Label("Total", systemImage: "arrow.triangle.2.circlepath")
                Spacer()
                Text("\(tracker.renderStats.totalRenders)")
            }
            
            HStack {
                Label("Unnecessary", systemImage: "exclamationmark.triangle")
                Spacer()
                Text(String(format: "%.1f%%", tracker.renderStats.unnecessaryRenderPercentage))
                    .foregroundColor(tracker.renderStats.unnecessaryRenderPercentage > 20 ? .red : .primary)
            }
            
            HStack {
                Label("Avg Time", systemImage: "timer")
                Spacer()
                Text(String(format: "%.2fms", tracker.renderStats.averageRenderTime * 1000))
                    .foregroundColor(tracker.renderStats.averageRenderTime > 0.008 ? .orange : .primary)
            }
            
            if let slowest = tracker.renderStats.slowestView {
                HStack {
                    Label("Slowest", systemImage: "tortoise")
                    Spacer()
                    Text(slowest)
                        .font(.caption)
                }
            }
            
            Toggle("Track Renders", isOn: Binding(
                get: { tracker.isTracking },
                set: { _ in
                    if tracker.isTracking {
                        tracker.stopTracking()
                    } else {
                        tracker.startTracking()
                    }
                }
            ))
        }
        .padding()
        .background(Color.secondary.opacity(0.1))
        .cornerRadius(8)
    }
}

// MARK: - Codable Conformances

extension ViewDiffTracker.RenderEvent: Codable {}
extension ViewDiffTracker.RenderEvent.RenderTrigger: Codable {}
extension ViewDiffTracker.RenderStatistics: Codable {}
extension ViewDiffTracker.RenderAnalysis: Codable {
    enum CodingKeys: String, CodingKey {
        case events, statistics, recommendations
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        events = try container.decode([ViewDiffTracker.RenderEvent].self, forKey: .events)
        statistics = try container.decode(ViewDiffTracker.RenderStatistics.self, forKey: .statistics)
        recommendations = try container.decode([String].self, forKey: .recommendations)
        patterns = [] // Patterns are computed, not stored
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(events, forKey: .events)
        try container.encode(statistics, forKey: .statistics)
        try container.encode(recommendations, forKey: .recommendations)
    }
}