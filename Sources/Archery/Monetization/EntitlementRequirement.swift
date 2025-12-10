import Foundation

// MARK: - Entitlement Requirement

/// Represents an entitlement requirement for accessing gated content.
/// Used by @requires, @requiresAny, @requiresAll macros to declare
/// what entitlements are needed for routes, tabs, and ViewModels.
public enum EntitlementRequirement: Sendable, Equatable, Hashable {
    /// No entitlement required - content is freely accessible
    case none

    /// A single specific entitlement is required
    case required(Entitlement)

    /// Any one of the listed entitlements grants access (OR logic)
    case anyOf([Entitlement])

    /// All of the listed entitlements are required (AND logic)
    case allOf([Entitlement])

    // MARK: - Satisfaction Checks

    /// Check if this requirement is satisfied by the given set of owned entitlements
    public func isSatisfied(by owned: Set<Entitlement>) -> Bool {
        switch self {
        case .none:
            return true
        case .required(let entitlement):
            return owned.contains(entitlement)
        case .anyOf(let entitlements):
            return entitlements.contains { owned.contains($0) }
        case .allOf(let entitlements):
            return entitlements.allSatisfy { owned.contains($0) }
        }
    }

    /// Check if this requirement is satisfied using the StoreKitManager
    @MainActor
    public func isSatisfied(by store: StoreKitManager) -> Bool {
        isSatisfied(by: store.entitlements)
    }

    // MARK: - Display Helpers

    /// Returns a user-friendly description of what's required
    public var displayDescription: String {
        switch self {
        case .none:
            return "No subscription required"
        case .required(let entitlement):
            return "\(entitlement.displayName) required"
        case .anyOf(let entitlements):
            let names = entitlements.map(\.displayName).joined(separator: " or ")
            return "\(names) required"
        case .allOf(let entitlements):
            let names = entitlements.map(\.displayName).joined(separator: " and ")
            return "\(names) required"
        }
    }

    /// Returns the primary entitlement for display purposes (first in list)
    public var primaryEntitlement: Entitlement? {
        switch self {
        case .none:
            return nil
        case .required(let entitlement):
            return entitlement
        case .anyOf(let entitlements), .allOf(let entitlements):
            return entitlements.first
        }
    }

    /// Returns all entitlements involved in this requirement
    public var entitlements: [Entitlement] {
        switch self {
        case .none:
            return []
        case .required(let entitlement):
            return [entitlement]
        case .anyOf(let entitlements), .allOf(let entitlements):
            return entitlements
        }
    }

    /// Analytics-friendly description for tracking events
    public var analyticsDescription: String {
        switch self {
        case .none:
            return "none"
        case .required(let entitlement):
            return entitlement.rawValue
        case .anyOf(let entitlements):
            return "any_of:\(entitlements.map(\.rawValue).joined(separator: ","))"
        case .allOf(let entitlements):
            return "all_of:\(entitlements.map(\.rawValue).joined(separator: ","))"
        }
    }
}

// MARK: - Gated Tab Behavior

/// Defines how a tab behaves when the user doesn't have the required entitlement.
/// Used with @requires on AppShell Tab enum cases.
public enum GatedTabBehavior: String, Sendable, CaseIterable {
    /// Tab is completely hidden from the tab bar
    case hidden

    /// Tab shows with a lock icon; tapping presents a paywall
    case locked

    /// Tab is visible but grayed out and not tappable
    case disabled

    /// Tab shows and is tappable but with limited/restricted functionality
    case limited
}

// MARK: - Entitlement Gating Configuration

/// Configuration for how entitlement gating should behave
public struct EntitlementGatingConfig: Sendable {
    /// Whether to automatically present a paywall when gated content is accessed
    public let autoPaywall: Bool

    /// The behavior for gated tabs
    public let tabBehavior: GatedTabBehavior

    /// Default configuration with auto-paywall enabled
    public static let `default` = EntitlementGatingConfig(
        autoPaywall: true,
        tabBehavior: .locked
    )

    public init(autoPaywall: Bool = true, tabBehavior: GatedTabBehavior = .locked) {
        self.autoPaywall = autoPaywall
        self.tabBehavior = tabBehavior
    }
}

// MARK: - Protocol for Entitlement-Gated Types

/// Protocol for types that can declare entitlement requirements.
/// Implemented by routes, ViewModels, and other gated types.
public protocol EntitlementRequiring {
    /// The entitlement requirement for this type
    static var requiredEntitlement: EntitlementRequirement { get }
}

/// Default implementation for types without requirements
public extension EntitlementRequiring {
    static var requiredEntitlement: EntitlementRequirement { .none }
}

// MARK: - Environment Key for Limited Mode

import SwiftUI

private struct EntitlementLimitedKey: EnvironmentKey {
    static let defaultValue: Bool = false
}

public extension EnvironmentValues {
    /// Indicates whether the current view is in entitlement-limited mode.
    /// Set to true when a view is shown with `.limited` tab behavior.
    var entitlementLimited: Bool {
        get { self[EntitlementLimitedKey.self] }
        set { self[EntitlementLimitedKey.self] = newValue }
    }
}
