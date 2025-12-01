import SwiftUI
import StoreKit
@testable import Archery

// MARK: - Example App

@main
struct MonetizationExampleApp: App {
    @StateObject private var store = StoreKitManager.shared
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .task {
                    // Configure for testing
                    SandboxTestingManager.shared.configureForTesting()
                    
                    // Load products on app launch
                    await store.loadProducts(identifiers: [
                        "com.app.premium.monthly",
                        "com.app.premium.yearly",
                        "com.app.pro.lifetime",
                        "com.app.credits.100",
                        "com.app.remove_ads"
                    ])
                }
        }
    }
}

// MARK: - Content View

struct ContentView: View {
    @StateObject private var store = StoreKitManager.shared
    @State private var selectedTab = 0
    @State private var showingPaywall = false
    
    var body: some View {
        TabView(selection: $selectedTab) {
            HomeView()
                .tabItem {
                    Label("Home", systemImage: "house.fill")
                }
                .tag(0)
            
            StoreView()
                .tabItem {
                    Label("Store", systemImage: "cart.fill")
                }
                .tag(1)
            
            EntitlementsView()
                .tabItem {
                    Label("Premium", systemImage: "crown.fill")
                }
                .tag(2)
            
            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gear")
                }
                .tag(3)
        }
        .sheet(isPresented: $showingPaywall) {
            PaywallView(
                configuration: .premium,
                onDismiss: {
                    showingPaywall = false
                },
                onPurchaseComplete: { transaction in
                    print("✅ Purchase completed: \(transaction.productID)")
                }
            )
        }
    }
}

// MARK: - Home View

struct HomeView: View {
    @StateObject private var store = StoreKitManager.shared
    @State private var showingPaywall = false
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Welcome section
                    VStack(spacing: 12) {
                        Image(systemName: "app.fill")
                            .font(.system(size: 60))
                            .foregroundStyle(.blue.gradient)
                        
                        Text("Welcome to Monetization Example")
                            .font(.title2)
                            .fontWeight(.bold)
                        
                        Text("Explore StoreKit 2 integration with Archery")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 30)
                    
                    // Mini upsell
                    if !store.hasEntitlement(.premium) {
                        MiniUpsellView(
                            configuration: MiniUpsellConfiguration(
                                title: "Unlock Premium Features",
                                subtitle: "Get unlimited access to all features",
                                icon: "crown.fill",
                                accentColor: .purple,
                                backgroundColor: .purple.opacity(0.1)
                            )
                        )
                        .padding(.horizontal)
                    }
                    
                    // Feature sections
                    FeatureSection(
                        title: "Basic Features",
                        icon: "star.fill",
                        features: [
                            "Core functionality",
                            "Basic themes",
                            "Standard support"
                        ],
                        isLocked: false
                    )
                    
                    FeatureSection(
                        title: "Premium Features",
                        icon: "crown.fill",
                        features: [
                            "Advanced analytics",
                            "Custom themes",
                            "Priority support",
                            "Cloud sync",
                            "Export options"
                        ],
                        isLocked: !store.hasEntitlement(.premium)
                    )
                    
                    FeatureSection(
                        title: "Pro Features",
                        icon: "bolt.circle.fill",
                        features: [
                            "API access",
                            "Team collaboration",
                            "Advanced automation",
                            "White-label options",
                            "Dedicated support"
                        ],
                        isLocked: !store.hasEntitlement(.pro)
                    )
                }
                .padding()
            }
            .navigationTitle("Home")
        }
    }
}

struct FeatureSection: View {
    let title: String
    let icon: String
    let features: [String]
    let isLocked: Bool
    @State private var showingPaywall = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: icon)
                    .foregroundStyle(isLocked ? .secondary : .blue)
                Text(title)
                    .font(.headline)
                Spacer()
                if isLocked {
                    Image(systemName: "lock.fill")
                        .foregroundColor(.secondary)
                        .font(.caption)
                }
            }
            
            ForEach(features, id: \.self) { feature in
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(isLocked ? .secondary : .green)
                        .font(.caption)
                    Text(feature)
                        .font(.subheadline)
                        .foregroundColor(isLocked ? .secondary : .primary)
                    Spacer()
                }
            }
            
            if isLocked {
                Button("Unlock Now") {
                    showingPaywall = true
                }
                .font(.caption)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .background(Color.gray.opacity(isLocked ? 0.05 : 0.1))
        .cornerRadius(12)
        .sheet(isPresented: $showingPaywall) {
            PaywallView(configuration: .premium)
        }
    }
}

// MARK: - Store View

struct StoreView: View {
    @StateObject private var store = StoreKitManager.shared
    @State private var selectedCategory = 0
    @State private var isPurchasing = false
    @State private var purchaseError: Error?
    
    var body: some View {
        NavigationStack {
            List {
                // Subscription section
                Section("Subscriptions") {
                    ForEach(subscriptionProducts, id: \.id) { product in
                        ProductListRow(
                            product: product,
                            isPurchased: store.purchasedProductIDs.contains(product.id)
                        ) {
                            Task {
                                await purchase(product)
                            }
                        }
                    }
                }
                
                // One-time purchases
                Section("One-Time Purchases") {
                    ForEach(oneTimeProducts, id: \.id) { product in
                        ProductListRow(
                            product: product,
                            isPurchased: store.purchasedProductIDs.contains(product.id)
                        ) {
                            Task {
                                await purchase(product)
                            }
                        }
                    }
                }
                
                // Consumables
                Section("Consumables") {
                    ForEach(consumableProducts, id: \.id) { product in
                        ProductListRow(
                            product: product,
                            isPurchased: false
                        ) {
                            Task {
                                await purchase(product)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Store")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Restore") {
                        Task {
                            await store.restorePurchases()
                        }
                    }
                }
            }
            .refreshable {
                await store.loadProducts()
            }
            .alert("Purchase Error", isPresented: .constant(purchaseError != nil)) {
                Button("OK") {
                    purchaseError = nil
                }
            } message: {
                if let error = purchaseError {
                    Text(error.localizedDescription)
                }
            }
            .disabled(isPurchasing)
            .overlay {
                if isPurchasing {
                    ProgressView("Processing...")
                        .padding()
                        .background(.regularMaterial)
                        .cornerRadius(12)
                }
            }
        }
    }
    
    private var subscriptionProducts: [Product] {
        store.products.filter { $0.type == .autoRenewable }
    }
    
    private var oneTimeProducts: [Product] {
        store.products.filter { $0.type == .nonConsumable }
    }
    
    private var consumableProducts: [Product] {
        store.products.filter { $0.type == .consumable }
    }
    
    private func purchase(_ product: Product) async {
        isPurchasing = true
        defer { isPurchasing = false }
        
        if let _ = await store.purchase(product) {
            // Success - UI will update automatically
        } else if let error = store.error {
            purchaseError = error
        }
    }
}

struct ProductListRow: View {
    let product: Product
    let isPurchased: Bool
    let onPurchase: () -> Void
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(product.displayName)
                    .font(.headline)
                if let description = product.description {
                    Text(description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            if isPurchased {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
            } else {
                Button(product.displayPrice) {
                    onPurchase()
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Entitlements View

struct EntitlementsView: View {
    @StateObject private var store = StoreKitManager.shared
    
    var body: some View {
        NavigationStack {
            List {
                // Subscription status
                Section("Subscription") {
                    SubscriptionStatusView()
                }
                
                // Active entitlements
                Section("Active Entitlements") {
                    if store.entitlements.isEmpty {
                        Text("No active entitlements")
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(Array(store.entitlements), id: \.self) { entitlement in
                            HStack {
                                Image(systemName: entitlement.icon)
                                    .foregroundStyle(.green)
                                Text(entitlement.displayName)
                                Spacer()
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                                    .font(.caption)
                            }
                        }
                    }
                }
                
                // All available entitlements
                Section("All Entitlements") {
                    ForEach(Entitlement.allCases, id: \.self) { entitlement in
                        HStack {
                            Image(systemName: entitlement.icon)
                                .foregroundStyle(
                                    store.hasEntitlement(entitlement) ? Color.blue : Color.secondary
                                )
                            Text(entitlement.displayName)
                            Spacer()
                            if store.hasEntitlement(entitlement) {
                                Text("Active")
                                    .font(.caption)
                                    .foregroundColor(.green)
                            } else {
                                Text("Locked")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Premium Status")
        }
    }
}

// MARK: - Settings View

struct SettingsView: View {
    @StateObject private var store = StoreKitManager.shared
    @State private var showingDebugInfo = false
    
    var body: some View {
        NavigationStack {
            List {
                // Account section
                Section("Account") {
                    HStack {
                        Text("User ID")
                        Spacer()
                        Text("user_123456")
                            .foregroundColor(.secondary)
                    }
                    
                    Button("Manage Subscription") {
                        Task {
                            if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
                                try? await AppStore.showManageSubscriptions(in: scene)
                            }
                        }
                    }
                }
                
                // Sandbox testing
                Section("Testing") {
                    Toggle("Sandbox Mode", isOn: .constant(SandboxTestingManager.shared.isSandbox))
                        .disabled(true)
                    
                    Button("Clear Sandbox Purchases") {
                        Task {
                            await SandboxTestingManager.shared.clearSandboxPurchases()
                        }
                    }
                    .disabled(!SandboxTestingManager.shared.isSandbox)
                    
                    Button("Simulate Failed Purchase") {
                        Task {
                            await SandboxTestingManager.shared.simulateScenario(.failedPayment)
                        }
                    }
                    
                    Button("Show Debug Info") {
                        showingDebugInfo = true
                    }
                }
                
                // Support
                Section("Support") {
                    Link("Terms of Use", destination: URL(string: "https://example.com/terms")!)
                    Link("Privacy Policy", destination: URL(string: "https://example.com/privacy")!)
                    Link("Contact Support", destination: URL(string: "mailto:support@example.com")!)
                }
            }
            .navigationTitle("Settings")
            .sheet(isPresented: $showingDebugInfo) {
                DebugInfoView()
            }
        }
    }
}

// MARK: - Debug Info View

struct DebugInfoView: View {
    @StateObject private var store = StoreKitManager.shared
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            List {
                Section("Environment") {
                    DebugRow("Sandbox", SandboxTestingManager.shared.isSandbox ? "Yes" : "No")
                    DebugRow("TestFlight", SandboxTestingManager.shared.isTestFlight ? "Yes" : "No")
                    DebugRow("Xcode Build", SandboxTestingManager.shared.isXcodeBuild ? "Yes" : "No")
                }
                
                Section("Products") {
                    DebugRow("Loaded", "\(store.products.count)")
                    DebugRow("Purchased", "\(store.purchasedProductIDs.count)")
                }
                
                Section("Subscription") {
                    DebugRow("Status", store.subscriptionStatus.description)
                    DebugRow("Active", store.subscriptionStatus.isActive ? "Yes" : "No")
                }
                
                Section("Entitlements") {
                    ForEach(Array(store.entitlements), id: \.self) { entitlement in
                        DebugRow(entitlement.displayName, "✓")
                    }
                    if store.entitlements.isEmpty {
                        Text("No active entitlements")
                            .foregroundColor(.secondary)
                    }
                }
                
                Section("Product IDs") {
                    ForEach(store.purchasedProductIDs.sorted(), id: \.self) { productID in
                        Text(productID)
                            .font(.system(.caption, design: .monospaced))
                    }
                    if store.purchasedProductIDs.isEmpty {
                        Text("No purchased products")
                            .foregroundColor(.secondary)
                    }
                }
            }
            .navigationTitle("Debug Info")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

struct DebugRow: View {
    let label: String
    let value: String
    
    init(_ label: String, _ value: String) {
        self.label = label
        self.value = value
    }
    
    var body: some View {
        HStack {
            Text(label)
            Spacer()
            Text(value)
                .foregroundColor(.secondary)
                .font(.system(.body, design: .monospaced))
        }
    }
}

// MARK: - Preview

#Preview {
    ContentView()
}