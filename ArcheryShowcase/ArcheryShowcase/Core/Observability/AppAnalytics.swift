import Foundation
import SwiftUI
import Archery

// MARK: - App Analytics Events
//
// App-specific events only. Most events are now auto-tracked by Archery:
//
// AUTO-TRACKED BY FRAMEWORK (don't define here):
// - screen_viewed, flow_started/completed/abandoned → NavigationCoordinator
// - entity_created/updated/deleted/fetched → @DatabaseRepository macro
// - paywall_viewed, purchase_started/completed/failed → PaywallView
// - auth_started/completed/failed, auth_signed_out → AuthenticationManager
// - error_occurred → ArcheryErrorTracker
//
// Define only app-specific events that aren't covered by framework auto-tracking.

@AnalyticsEvent
enum AppAnalytics {
    // MARK: - Feature Usage (app-specific business metrics)
    case featureUsed(featureName: String, duration: Double)
    case onboardingCompleted(stepCount: Int)
    case settingsChanged(setting: String, value: String)

    // MARK: - Granular Task Events (beyond entity_updated)
    case taskFieldEdited(taskId: String, field: String)
    case taskShared(taskId: String, method: String)
    case taskDueDateChanged(taskId: String, daysDelta: Int)
}

// MARK: - Analytics Manager Extension

extension AnalyticsManager {
    /// Track an app analytics event with the shared manager
    func track(_ event: AppAnalytics) {
        track(event)
    }
}

// MARK: - View Extension for Screen Tracking

extension View {
    /// Track screen view when this view appears
    ///
    /// Note: If using Archery's NavigationCoordinator, screen views are auto-tracked.
    /// This modifier is for views outside the navigation system or for custom tracking.
    func trackScreen(_ screenName: String) -> some View {
        self.onAppear {
            // Screen tracking is now automatic via NavigationCoordinator.
            // This provides manual tracking for views outside the nav system.
            ArcheryAnalyticsConfiguration.shared.track(
                .screenViewed(route: screenName, style: "manual", tab: nil)
            )
        }
    }
}

// MARK: - Analytics Demo View

struct AnalyticsShowcaseView: View {
    @StateObject private var analytics = AnalyticsManager.shared
    @State private var trackedEvents: [(name: String, properties: String, timestamp: Date)] = []
    @State private var debugProvider = ShowcaseDebugProvider()

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("The @AnalyticsEvent macro generates type-safe analytics with automatic PII redaction, validation, and provider abstraction.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    HStack {
                        StatusBadge(
                            icon: "antenna.radiowaves.left.and.right",
                            label: "Events",
                            value: "\(trackedEvents.count)"
                        )
                        StatusBadge(
                            icon: analytics.isEnabled ? "checkmark.circle.fill" : "xmark.circle.fill",
                            label: "Status",
                            value: analytics.isEnabled ? "Active" : "Disabled"
                        )
                    }
                }
            }

            Section("App-Specific Events") {
                Button {
                    trackEvent(AppAnalytics.featureUsed(featureName: "analytics_demo", duration: 5.5))
                } label: {
                    Label("Feature Used", systemImage: "star")
                }

                Button {
                    trackEvent(AppAnalytics.onboardingCompleted(stepCount: 5))
                } label: {
                    Label("Onboarding Completed", systemImage: "checkmark.seal")
                }

                Button {
                    trackEvent(AppAnalytics.settingsChanged(setting: "notifications", value: "enabled"))
                } label: {
                    Label("Settings Changed", systemImage: "gearshape")
                }

                Button {
                    trackEvent(AppAnalytics.taskFieldEdited(taskId: UUID().uuidString, field: "title"))
                } label: {
                    Label("Task Field Edited", systemImage: "pencil")
                }

                Button {
                    trackEvent(AppAnalytics.taskShared(taskId: UUID().uuidString, method: "copy_link"))
                } label: {
                    Label("Task Shared", systemImage: "square.and.arrow.up")
                }
            }

            Section("Framework Auto-Tracked Events") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("These events are automatically tracked by Archery:")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    AutoTrackedEventRow(icon: "rectangle.portrait", name: "screen_viewed", source: "NavigationCoordinator")
                    AutoTrackedEventRow(icon: "arrow.triangle.branch", name: "flow_started/completed", source: "NavigationCoordinator")
                    AutoTrackedEventRow(icon: "tray.full", name: "entity_created/updated/deleted", source: "@DatabaseRepository")
                    AutoTrackedEventRow(icon: "creditcard", name: "purchase_started/completed/failed", source: "PaywallView")
                    AutoTrackedEventRow(icon: "person.badge.key", name: "auth_started/completed/failed", source: "AuthenticationManager")
                    AutoTrackedEventRow(icon: "exclamationmark.triangle", name: "error_occurred", source: "ArcheryErrorTracker")
                }
            }

            Section("Tracked Events (\(trackedEvents.count))") {
                if trackedEvents.isEmpty {
                    Text("No events tracked yet")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(trackedEvents.reversed(), id: \.timestamp) { event in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(event.name)
                                    .font(.subheadline.weight(.medium))
                                Spacer()
                                Text(event.timestamp, style: .time)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Text(event.properties)
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                        .padding(.vertical, 2)
                    }
                }
            }

            Section("Macro Features") {
                MacroFeatureRow(
                    title: "Auto Event Names",
                    description: "Case names converted to snake_case",
                    example: "taskCreated → task_created"
                )
                MacroFeatureRow(
                    title: "Type-Safe Properties",
                    description: "Associated values become typed properties",
                    example: "taskId: String, title: String"
                )
                MacroFeatureRow(
                    title: "Validation",
                    description: "Strings must be non-empty, numbers non-negative",
                    example: "validate() throws"
                )
                MacroFeatureRow(
                    title: "PII Redaction",
                    description: "Email, phone numbers auto-redacted",
                    example: "redactedProperties()"
                )
            }

            Section("Code Example") {
                Text("""
                // App-specific events (framework tracks the rest!)
                @AnalyticsEvent
                enum AppAnalytics {
                    case featureUsed(featureName: String, duration: Double)
                    case settingsChanged(setting: String, value: String)
                }

                // Usage:
                AnalyticsManager.shared.track(
                    AppAnalytics.featureUsed(
                        featureName: "search",
                        duration: 3.5
                    )
                )

                // Auto-tracked by framework:
                // - Navigation: screen_viewed, flow_started/completed
                // - Repository: entity_created/updated/deleted
                // - Monetization: purchase_started/completed/failed
                // - Auth: auth_started/completed/failed
                """)
                .font(.system(size: 11, design: .monospaced))
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
        .navigationTitle("Analytics")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    trackedEvents.removeAll()
                } label: {
                    Image(systemName: "trash")
                }
                .disabled(trackedEvents.isEmpty)
            }
        }
        .onAppear {
            setupDebugProvider()
        }
    }

    private func setupDebugProvider() {
        // Configure with debug provider if not already configured
        if debugProvider.trackedEvents.isEmpty {
            analytics.configure(
                providers: [debugProvider],
                enabled: true,
                debugMode: true
            )
        }
    }

    private func trackEvent(_ event: AppAnalytics) {
        analytics.track(event)

        // Add to local display list
        let propsString = event.properties.map { "\($0.key): \($0.value)" }.joined(separator: ", ")
        trackedEvents.append((
            name: event.eventName,
            properties: propsString.isEmpty ? "(no properties)" : propsString,
            timestamp: Date()
        ))
    }
}

// MARK: - Supporting Views

private struct StatusBadge: View {
    let icon: String
    let label: String
    let value: String

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption.bold())
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.accentColor.opacity(0.1))
        .clipShape(Capsule())
    }
}

private struct MacroFeatureRow: View {
    let title: String
    let description: String
    let example: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.subheadline.weight(.medium))
            Text(description)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(example)
                .font(.caption.monospaced())
                .padding(4)
                .background(Color(.tertiarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 4))
        }
        .padding(.vertical, 2)
    }
}

private struct AutoTrackedEventRow: View {
    let icon: String
    let name: String
    let source: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.caption.monospaced())
                Text(source)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }
}

// Debug provider that captures events for display
private class ShowcaseDebugProvider: AnalyticsProvider, @unchecked Sendable {
    var trackedEvents: [(name: String, properties: [String: Any])] = []

    func track(eventName: String, properties: [String: Any]) {
        trackedEvents.append((name: eventName, properties: properties))
        print("[Analytics] \(eventName): \(properties)")
    }

    func identify(userId: String, traits: [String: Any]) {
        print("[Analytics] Identify: \(userId)")
    }

    func screen(name: String, properties: [String: Any]) {
        print("[Analytics] Screen: \(name)")
    }

    func flush() {
        print("[Analytics] Flush: \(trackedEvents.count) events")
    }
}

#Preview {
    NavigationStack {
        AnalyticsShowcaseView()
    }
}
