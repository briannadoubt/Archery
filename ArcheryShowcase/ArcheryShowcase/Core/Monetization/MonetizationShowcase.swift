import Foundation
import SwiftUI
import Archery
import StoreKit

// MARK: - StoreKit Monetization Showcase
//
// This demonstrates Archery's complete monetization system:
// - PaywallView for full-screen purchase flows
// - MiniUpsellView for inline upsell prompts
// - SubscriptionStatusView for subscription management
// - Entitlement gating with .requiresEntitlement() modifier
// - Sandbox testing and environment detection

struct MonetizationShowcaseView: View {
    @StateObject private var store = StoreKitManager.shared
    @Environment(\.navigationHandle) private var nav
    @State private var selectedEntitlement: Entitlement = .premium

    var body: some View {
        List {
            // Overview
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Archery includes a complete StoreKit 2 monetization system with paywalls, subscriptions, entitlements, and sandbox testing.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    HStack {
                        StatusBadge(
                            icon: "bag",
                            label: "Products",
                            value: "\(store.products.count)"
                        )
                        StatusBadge(
                            icon: "checkmark.seal",
                            label: "Entitlements",
                            value: "\(store.entitlements.count)"
                        )
                    }
                }
            }

            // Paywall Section
            Section("Paywall Views") {
                Button {
                    nav?.navigate(to: SettingsRoute.paywall, style: .sheet())
                } label: {
                    Label("Show Default Paywall", systemImage: "rectangle.portrait.badge.plus")
                }

                Button {
                    nav?.navigate(to: SettingsRoute.premiumPaywall, style: .sheet())
                } label: {
                    Label("Show Premium Paywall", systemImage: "crown")
                }

                Text("PaywallView displays products, handles purchases, and shows loading/error states automatically.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // Mini Upsell Section
            Section("Inline Upsell") {
                MiniUpsellView(configuration: .default)

                Text("MiniUpsellView is a compact prompt that opens PaywallView in a sheet when tapped.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // Subscription Status
            Section("Subscription Status") {
                SubscriptionStatusView()

                VStack(alignment: .leading, spacing: 4) {
                    Text("Current Status: \(store.subscriptionStatus.description)")
                        .font(.caption.monospaced())
                    Text("Is Active: \(store.subscriptionStatus.isActive ? "Yes" : "No")")
                        .font(.caption.monospaced())
                }
                .foregroundStyle(.secondary)
            }

            // Entitlement Gating Demo
            Section("Entitlement Gating") {
                VStack(alignment: .leading, spacing: 12) {
                    Text("The .requiresEntitlement() modifier gates content behind purchases:")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Picker("Test Entitlement", selection: $selectedEntitlement) {
                        ForEach(Entitlement.allCases, id: \.self) { entitlement in
                            Text(entitlement.displayName).tag(entitlement)
                        }
                    }
                    .pickerStyle(.menu)
                }

                EntitlementDemoRow(entitlement: selectedEntitlement)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Usage:")
                        .font(.caption.bold())
                    Text("Text(\"Premium\").requiresEntitlement(.premium)")
                        .font(.system(size: 11, design: .monospaced))
                }
                .foregroundStyle(.secondary)
            }

            // EntitlementRequirement Demo (new!)
            Section("EntitlementRequirement System") {
                VStack(alignment: .leading, spacing: 12) {
                    Text("The new EntitlementRequirement system supports:")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    VStack(alignment: .leading, spacing: 4) {
                        Label(".required(.premium)", systemImage: "1.circle")
                        Label(".anyOf([.premium, .pro])", systemImage: "circle.grid.2x1")
                        Label(".allOf([.premium, .unlimitedAccess])", systemImage: "circle.grid.2x2")
                    }
                    .font(.caption.monospaced())
                }

                // Demo of different gating behaviors
                RequirementBehaviorDemo()

                VStack(alignment: .leading, spacing: 4) {
                    Text("Usage:")
                        .font(.caption.bold())
                    Text("content.gated(by: .required(.premium), behavior: .locked)")
                        .font(.system(size: 10, design: .monospaced))
                }
                .foregroundStyle(.secondary)
            }

            // Available Entitlements
            Section("Entitlement Types") {
                ForEach(Entitlement.allCases, id: \.self) { entitlement in
                    HStack {
                        Image(systemName: entitlement.icon)
                            .foregroundStyle(.tint)
                            .frame(width: 24)

                        VStack(alignment: .leading) {
                            Text(entitlement.displayName)
                                .font(.subheadline.weight(.medium))
                            Text(entitlement.rawValue)
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        if store.hasEntitlement(entitlement) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        }
                    }
                }
            }

            // Sandbox Testing
            Section("Sandbox Testing") {
                SandboxInfoView()
            }

            // Mock Product Catalog
            Section("Mock Product Catalog") {
                ProductCatalogView()
            }

            // Code Examples
            Section("Usage Examples") {
                CodeExampleView()
            }
        }
        .navigationTitle("Monetization")
        .task {
            await store.loadProducts()
        }
    }
}

// MARK: - Status Badge

private struct StatusBadge: View {
    let icon: String
    let label: String
    let value: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption)
            Text(value)
                .font(.caption.bold())
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.accentColor.opacity(0.1))
        .clipShape(Capsule())
    }
}

// MARK: - Entitlement Demo Row

private struct EntitlementDemoRow: View {
    let entitlement: Entitlement
    @StateObject private var store = StoreKitManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: entitlement.icon)
                    .font(.title2)
                    .foregroundStyle(.tint)

                VStack(alignment: .leading) {
                    Text("\(entitlement.displayName) Content")
                        .font(.subheadline.weight(.medium))
                    Text(store.hasEntitlement(entitlement) ? "Unlocked" : "Locked")
                        .font(.caption)
                        .foregroundStyle(store.hasEntitlement(entitlement) ? .green : .red)
                }

                Spacer()

                if store.hasEntitlement(entitlement) {
                    Image(systemName: "lock.open.fill")
                        .foregroundStyle(.green)
                } else {
                    Image(systemName: "lock.fill")
                        .foregroundStyle(.red)
                }
            }
            .padding()
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }
}

// MARK: - Sandbox Info View

private struct SandboxInfoView: View {
    let sandbox = SandboxTestingManager.shared

    var body: some View {
        LabeledContent("Is Sandbox") {
            Text(sandbox.isSandbox ? "Yes" : "No")
                .foregroundStyle(sandbox.isSandbox ? .green : .secondary)
        }

        LabeledContent("Is TestFlight") {
            Text(sandbox.isTestFlight ? "Yes" : "No")
                .foregroundStyle(sandbox.isTestFlight ? .orange : .secondary)
        }

        LabeledContent("Is Xcode Build") {
            Text(sandbox.isXcodeBuild ? "Yes" : "No")
                .foregroundStyle(sandbox.isXcodeBuild ? .blue : .secondary)
        }

        VStack(alignment: .leading, spacing: 4) {
            Text("SandboxTestingManager provides:")
                .font(.caption.bold())
            Text("• Environment detection")
                .font(.caption)
            Text("• Test scenario simulation")
                .font(.caption)
            Text("• StoreKit config generation")
                .font(.caption)
        }
        .foregroundStyle(.secondary)
        .padding(.top, 4)
    }
}

// MARK: - Product Catalog View

private struct ProductCatalogView: View {
    var body: some View {
        ForEach(PreviewSeeds.products, id: \.id) { product in
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(product.displayName)
                            .font(.subheadline.weight(.medium))

                        if let badge = product.badge {
                            Text(badge)
                                .font(.system(size: 9, weight: .bold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.orange)
                                .foregroundStyle(.white)
                                .clipShape(Capsule())
                        }
                    }

                    Text(product.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                VStack(alignment: .trailing) {
                    Text(product.formattedPrice)
                        .font(.subheadline.weight(.semibold))

                    Text(product.type.description)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)
        }

        Text("These are mock products from PreviewSeeds. In production, products come from App Store Connect.")
            .font(.caption)
            .foregroundStyle(.secondary)
    }
}

// MARK: - Code Example View

private struct CodeExampleView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            CodeSnippet(
                title: "Show Paywall",
                code: """
                @State var showPaywall = false

                Button("Upgrade") { showPaywall = true }
                    .paywall(isPresented: $showPaywall)
                """
            )

            CodeSnippet(
                title: "Gate Content",
                code: """
                Text("Premium Feature")
                    .requiresEntitlement(.premium)
                """
            )

            CodeSnippet(
                title: "Check Entitlement",
                code: """
                if StoreKitManager.shared.hasEntitlement(.pro) {
                    // Show pro content
                }
                """
            )

            CodeSnippet(
                title: "Purchase Product",
                code: """
                let transaction = await store.purchase(product)
                if transaction != nil {
                    // Success!
                }
                """
            )
        }
    }
}

// MARK: - Requirement Behavior Demo

private struct RequirementBehaviorDemo: View {
    @State private var selectedBehavior: GatedTabBehavior = .locked

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("GatedTabBehavior:")
                .font(.caption.bold())

            Picker("Behavior", selection: $selectedBehavior) {
                Text("Hidden").tag(GatedTabBehavior.hidden)
                Text("Locked").tag(GatedTabBehavior.locked)
                Text("Disabled").tag(GatedTabBehavior.disabled)
                Text("Limited").tag(GatedTabBehavior.limited)
            }
            .pickerStyle(.segmented)

            // Preview of the selected behavior
            VStack(spacing: 8) {
                Text("Preview (user lacks entitlement):")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Group {
                    switch selectedBehavior {
                    case .hidden:
                        Text("Content is completely hidden")
                            .foregroundStyle(.secondary)
                            .italic()
                    case .locked:
                        HStack {
                            Image(systemName: "lock.fill")
                            Text("Tap to unlock")
                        }
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(Color(.secondarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    case .disabled:
                        Text("Premium Content")
                            .padding()
                            .frame(maxWidth: .infinity)
                            .background(Color(.secondarySystemBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .opacity(0.4)
                            .overlay(
                                Image(systemName: "lock.fill")
                                    .foregroundStyle(.secondary)
                            )
                    case .limited:
                        VStack {
                            Text("Limited Access Mode")
                            Text("Some features restricted")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(Color(.secondarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }
            }
        }
    }
}

private struct CodeSnippet: View {
    let title: String
    let code: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.bold())

            Text(code)
                .font(.system(size: 10, design: .monospaced))
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
    }
}

// MARK: - Preview Seeds Extension

extension PreviewSeeds {
    static let products: [MockProduct] = [
        MockProduct(
            id: "com.app.premium.monthly",
            displayName: "Premium Monthly",
            description: "Full access, billed monthly",
            price: 9.99,
            type: .subscription(.monthly),
            badge: nil
        ),
        MockProduct(
            id: "com.app.premium.yearly",
            displayName: "Premium Yearly",
            description: "Save 20% with annual billing",
            price: 95.99,
            type: .subscription(.yearly),
            badge: "BEST VALUE"
        ),
        MockProduct(
            id: "com.app.pro.lifetime",
            displayName: "Pro Lifetime",
            description: "One-time purchase, forever access",
            price: 199.99,
            type: .nonConsumable,
            badge: "ONE TIME"
        ),
        MockProduct(
            id: "com.app.remove_ads",
            displayName: "Remove Ads",
            description: "Enjoy an ad-free experience",
            price: 4.99,
            type: .nonConsumable,
            badge: nil
        )
    ]
}

struct MockProduct {
    let id: String
    let displayName: String
    let description: String
    let price: Decimal
    let type: ProductType
    let badge: String?

    var formattedPrice: String {
        "$\(price)"
    }

    enum ProductType {
        case consumable
        case nonConsumable
        case subscription(SubscriptionPeriod)

        var description: String {
            switch self {
            case .consumable: return "Consumable"
            case .nonConsumable: return "One-time"
            case .subscription(let period): return period.rawValue
            }
        }
    }

    enum SubscriptionPeriod: String {
        case weekly = "Weekly"
        case monthly = "Monthly"
        case yearly = "Yearly"
    }
}

#Preview {
    NavigationStack {
        MonetizationShowcaseView()
    }
}
