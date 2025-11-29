import Foundation
#if canImport(WidgetKit)
import WidgetKit
#endif
#if canImport(AppIntents)
import AppIntents
#endif
#if canImport(ActivityKit) && os(iOS)
import ActivityKit
#endif

#if canImport(WidgetKit)
@available(iOS 16.0, macOS 13.0, *)
public struct WidgetTestFixtures {
    
    public struct SampleEntry: TimelineEntry {
        public let date: Date
        public let title: String
        public let subtitle: String
        public let progress: Double
        
        public init(
            date: Date = Date(),
            title: String = "Sample",
            subtitle: String = "Subtitle",
            progress: Double = 0.5
        ) {
            self.date = date
            self.title = title
            self.subtitle = subtitle
            self.progress = progress
        }
    }
    
    public static func simpleTimeline(
        count: Int = 5,
        interval: TimeInterval = 3600
    ) -> [SampleEntry] {
        (0..<count).map { index in
            SampleEntry(
                date: Date().addingTimeInterval(TimeInterval(index) * interval),
                title: "Entry \(index + 1)",
                subtitle: "Updated \(index) hours ago",
                progress: Double(index) / Double(count - 1)
            )
        }
    }
    
    public static func dailyTimeline(
        days: Int = 7
    ) -> [SampleEntry] {
        (0..<days).map { day in
            let date = Calendar.current.date(
                byAdding: .day,
                value: day,
                to: Date()
            ) ?? Date()
            
            return SampleEntry(
                date: date,
                title: "Day \(day + 1)",
                subtitle: DateFormatter.localizedString(
                    from: date,
                    dateStyle: .medium,
                    timeStyle: .none
                ),
                progress: Double(day) / Double(days - 1)
            )
        }
    }
}
#endif

#if canImport(AppIntents)
@available(iOS 16.0, macOS 13.0, *)
public struct IntentTestFixtures {
    
    public struct SampleEntity: AppEntity {
        public let id: String
        public let name: String
        public let category: String
        
        public static var typeDisplayRepresentation: TypeDisplayRepresentation {
            TypeDisplayRepresentation(name: "Sample Entity")
        }
        
        public var displayRepresentation: DisplayRepresentation {
            DisplayRepresentation(title: "\(name)")
        }
        
        public static let defaultQuery = SampleEntityQuery()
        
        public init(id: String = UUID().uuidString, name: String, category: String = "default") {
            self.id = id
            self.name = name
            self.category = category
        }
    }
    
    public struct SampleEntityQuery: EntityQuery {
        public init() {}
        
        public func entities(for identifiers: [String]) async throws -> [SampleEntity] {
            identifiers.map { id in
                SampleEntity(id: id, name: "Entity \(id)")
            }
        }
        
        public func suggestedEntities() async throws -> [SampleEntity] {
            [
                SampleEntity(name: "Suggested 1"),
                SampleEntity(name: "Suggested 2"),
                SampleEntity(name: "Suggested 3")
            ]
        }
    }
    
    public static func createIntentFixtures() -> [IntentFixture] {
        [
            IntentFixture(
                name: "basic",
                parameters: ["input": "test"],
                expectedResult: "Success"
            ),
            IntentFixture(
                name: "withEntity",
                parameters: [
                    "entity": SampleEntity(name: "Test Entity")
                ],
                expectedResult: SampleEntity(name: "Result Entity")
            ),
            IntentFixture(
                name: "complex",
                parameters: [
                    "input": "complex test",
                    "count": 5,
                    "enabled": true
                ],
                expectedResult: ["status": "completed", "count": 5]
            )
        ]
    }
}
#endif

#if canImport(ActivityKit) && os(iOS)
@available(iOS 16.1, *)
public struct LiveActivityTestFixtures {
    
    public struct SampleAttributes: ActivityAttributes {
        public let id: String
        public let title: String
        
        public struct ContentState: Codable, Hashable {
            public let status: String
            public let progress: Double
            public let message: String
            
            public init(
                status: String = "active",
                progress: Double = 0.0,
                message: String = ""
            ) {
                self.status = status
                self.progress = progress
                self.message = message
            }
        }
        
        public init(id: String = UUID().uuidString, title: String = "Sample Activity") {
            self.id = id
            self.title = title
        }
    }
    
    public static func progressStates(
        steps: Int = 5
    ) -> [SampleAttributes.ContentState] {
        (0...steps).map { step in
            SampleAttributes.ContentState(
                status: step < steps ? "in_progress" : "completed",
                progress: Double(step) / Double(steps),
                message: "Step \(step)/\(steps)"
            )
        }
    }
    
    public static func statusTransitions() -> [SampleAttributes.ContentState] {
        [
            SampleAttributes.ContentState(status: "starting", progress: 0.0, message: "Initializing..."),
            SampleAttributes.ContentState(status: "processing", progress: 0.25, message: "Processing data..."),
            SampleAttributes.ContentState(status: "processing", progress: 0.5, message: "Halfway done..."),
            SampleAttributes.ContentState(status: "processing", progress: 0.75, message: "Almost there..."),
            SampleAttributes.ContentState(status: "completed", progress: 1.0, message: "Done!")
        ]
    }
    
    public static func createLiveActivityFixture(
        name: String = "default"
    ) -> LiveActivityFixture<SampleAttributes> {
        LiveActivityFixture(
            name: name,
            attributes: SampleAttributes(),
            contentStates: progressStates(),
            updateInterval: 30
        )
    }
}
#endif

public struct BackgroundTaskTestFixtures {
    
    public static func createTaskConfigurations() -> [BackgroundTaskConfiguration] {
        [
            BackgroundTaskConfiguration(
                identifier: "com.archery.sync",
                interval: 900,
                requiresNetworkConnectivity: true
            ),
            BackgroundTaskConfiguration(
                identifier: "com.archery.cleanup",
                interval: 3600,
                requiresNetworkConnectivity: false
            ),
            BackgroundTaskConfiguration(
                identifier: "com.archery.backup",
                interval: 86400,
                requiresExternalPower: true,
                allowsExpensiveNetworkAccess: true
            )
        ]
    }
    
    public struct MockTaskHandler: BackgroundTaskHandling {
        public let shouldSucceed: Bool
        public let executionTime: TimeInterval
        public let shouldRescheduleValue: Bool
        
        public init(
            shouldSucceed: Bool = true,
            executionTime: TimeInterval = 0.1,
            shouldReschedule: Bool = true
        ) {
            self.shouldSucceed = shouldSucceed
            self.executionTime = executionTime
            self.shouldRescheduleValue = shouldReschedule
        }
        
        public func performTask() async throws {
            try await Task.sleep(nanoseconds: UInt64(executionTime * 1_000_000_000))
            if !shouldSucceed {
                throw BackgroundTaskError.taskFailed("Mock failure")
            }
        }
        
        public func shouldReschedule() -> Bool {
            shouldRescheduleValue
        }
        
        public func nextScheduleDate() -> Date? {
            shouldRescheduleValue ? Date().addingTimeInterval(900) : nil
        }
    }
}