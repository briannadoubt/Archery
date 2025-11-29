#if canImport(WidgetKit)
@preconcurrency import WidgetKit
#endif
import SwiftUI

#if canImport(WidgetKit)
public protocol ArcheryTimelineProvider: TimelineProvider where Entry: TimelineEntry {
    associatedtype Configuration
    
    func placeholder(in context: Context) -> Entry
    func getSnapshot(for configuration: Configuration, in context: Context, completion: @escaping (Entry) -> Void)
    func getTimeline(for configuration: Configuration, in context: Context, completion: @escaping (Timeline<Entry>) -> Void)
}

@available(iOS 16.0, macOS 13.0, *)
public struct TimelineBuilder<Entry: TimelineEntry> {
    private var entries: [Entry] = []
    private var policy: TimelineReloadPolicy = .atEnd
    
    public init() {}
    
    public func add(_ entry: Entry) -> Self {
        var builder = self
        builder.entries.append(entry)
        return builder
    }
    
    public func add(contentsOf entries: [Entry]) -> Self {
        var builder = self
        builder.entries.append(contentsOf: entries)
        return builder
    }
    
    public func policy(_ policy: TimelineReloadPolicy) -> Self {
        var builder = self
        builder.policy = policy
        return builder
    }
    
    public func build() -> Timeline<Entry> {
        Timeline(entries: entries, policy: policy)
    }
}

public struct TimelineFixture<Entry: TimelineEntry> {
    public let name: String
    public let entries: [Entry]
    public let policy: TimelineReloadPolicy
    
    public init(
        name: String,
        entries: [Entry],
        policy: TimelineReloadPolicy = .atEnd
    ) {
        self.name = name
        self.entries = entries
        self.policy = policy
    }
    
    public func timeline() -> Timeline<Entry> {
        Timeline(entries: entries, policy: policy)
    }
}

#if DEBUG
public struct MockTimelineProvider<Entry: TimelineEntry>: TimelineProvider {
    
    private let fixture: TimelineFixture<Entry>
    
    public init(fixture: TimelineFixture<Entry>) {
        self.fixture = fixture
    }
    
    public func placeholder(in context: Context) -> Entry {
        fixture.entries.first ?? fixture.entries[0]
    }
    
    public func getSnapshot(in context: Context, completion: @escaping (Entry) -> Void) {
        completion(fixture.entries.first ?? fixture.entries[0])
    }
    
    public func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> Void) {
        completion(fixture.timeline())
    }
}
#endif
#endif