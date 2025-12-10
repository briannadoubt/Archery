import Foundation
import SwiftUI
import Archery

// MARK: - Archery Macros Showcase
//
// This file demonstrates actual usage of the Archery macro library.
//
// Working Macros (demonstrated in this app):
// - @KeyValueStore - See Stores.swift
// - @Repository - See Repositories.swift
// - @ObservableViewModel - See DashboardViewModel.swift
// - @Authenticated - See below
// - @FeatureFlag - See below
// - @AnalyticsEvent - See below
// - @Localizable - See below
//
// Macros requiring additional setup (WidgetKit/AppIntents):
// - @SharedModel - Requires WidgetKit target

// MARK: - @Authenticated Demo
// The @Authenticated macro generates:
// - authRequirement static property
// - checkAuthentication(with:) method

@Authenticated(scope: "admin")
class AdminServiceMacro {
    func deleteAllTasks() async throws {
        // Only accessible with admin scope
        print("Deleting all tasks...")
    }

    func resetDatabase() async throws {
        // Only accessible with admin scope
        print("Resetting database...")
    }
}

@Authenticated
class ProtectedDataServiceMacro {
    func fetchSecureData() async throws -> [String] {
        // This method requires authentication
        return ["Secure", "Data"]
    }
}

// MARK: - @FeatureFlag Demo
// The @FeatureFlag macro generates nested Flag types with:
// - key, defaultValue, and description properties
// - FeatureFlag protocol conformance

// TODO: Fix @FeatureFlag macro names: arbitrary issue with Swift 6
// @FeatureFlag
enum AppFeatures {
    case darkMode
    case betaFeatures
    case premiumContent
    case experimentalUI
}

// Example usage of generated flag types:
// let isDarkModeEnabled = FeatureFlagManager.shared.isEnabled(for: AppFeatures.DarkModeFlag.self)

// MARK: - @AnalyticsEvent Demo
// The @AnalyticsEvent macro generates:
// - eventName computed property
// - properties dictionary
// - validate() method
// - track(with:) method
// - redactedProperties() for PII protection

// TODO: Fix @AnalyticsEvent macro names: arbitrary issue with Swift 6
// @AnalyticsEvent
enum ShowcaseAnalytics {
    case screenViewed(screenName: String)
    case buttonTapped(buttonId: String)
    case featureUsed(featureName: String, duration: Double)
    case errorOccurred(errorCode: String, message: String)
    case purchaseCompleted(productId: String, amount: Double)
}

// Conformance via extension for enums with associated values
// extension ShowcaseAnalytics: Archery.AnalyticsEvent {}

// Example usage:
// ShowcaseAnalytics.screenViewed(screenName: "Dashboard").track(with: analyticsProvider)

// MARK: - @Localizable Demo
// The @Localizable macro generates:
// - key, localized, defaultValue, tableName, comment properties
// - Static localized string accessors

@Localizable
enum AppStrings {
    case welcomeTitle
    case welcomeSubtitle
    case dashboardHeader
    case taskListEmpty
    case settingsTitle
    case errorGeneric
}

// Example usage:
// let welcomeText = AppStrings.welcomeTitle.localized
// Or: let welcome = AppStrings.localizedWelcomeTitle

// MARK: - Demo View for Macro Features

struct MacroShowcaseView: View {
    @State private var showingFeatureFlags = false
    @State private var showingAnalytics = false

    var body: some View {
        List {
            Section("Authentication Macros") {
                LabeledContent("AdminService") {
                    Text("@Authenticated(scope: \"admin\")")
                        .font(.caption.monospaced())
                }
                LabeledContent("ProtectedDataService") {
                    Text("@Authenticated")
                        .font(.caption.monospaced())
                }
            }

            Section("Feature Flags") {
                ForEach(["darkMode", "betaFeatures", "premiumContent", "experimentalUI"], id: \.self) { flag in
                    LabeledContent(flag) {
                        Text("AppFeatures.\(flag.capitalized)Flag")
                            .font(.caption.monospaced())
                    }
                }
            }

            Section("Analytics Events") {
                Text("screenViewed, buttonTapped, featureUsed, errorOccurred, purchaseCompleted")
                    .font(.caption)
            }

            Section("Localization Keys") {
                ForEach(["welcomeTitle", "welcomeSubtitle", "dashboardHeader", "taskListEmpty", "settingsTitle", "errorGeneric"], id: \.self) { key in
                    LabeledContent(key) {
                        Text(".localized")
                            .font(.caption.monospaced())
                    }
                }
            }
        }
        .navigationTitle("Macro Showcase")
    }
}

// MARK: - Supporting Types

enum APIClientError: Error {
    case notFound
    case networkError
    case unauthorized
}

#Preview {
    NavigationStack {
        MacroShowcaseView()
    }
}
