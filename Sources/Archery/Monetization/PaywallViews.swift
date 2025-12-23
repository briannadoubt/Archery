import SwiftUI
import StoreKit

// MARK: - Paywall View

/// Customizable paywall view with product offerings
public struct PaywallView: View {
    @State private var store = StoreKitManager.shared
    @State private var selectedProduct: Product?
    @State private var isPurchasing = false
    @State private var showingError = false

    let configuration: PaywallConfiguration
    let source: String
    let requiredEntitlement: EntitlementRequirement?
    let onDismiss: (() -> Void)?
    let onPurchaseComplete: ((StoreKit.Transaction) -> Void)?

    public init(
        configuration: PaywallConfiguration = .default,
        source: String = "unknown",
        requiredEntitlement: EntitlementRequirement? = nil,
        onDismiss: (() -> Void)? = nil,
        onPurchaseComplete: ((StoreKit.Transaction) -> Void)? = nil
    ) {
        self.configuration = configuration
        self.source = source
        self.requiredEntitlement = requiredEntitlement
        self.onDismiss = onDismiss
        self.onPurchaseComplete = onPurchaseComplete
    }
    
    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Header
                    headerView
                    
                    // Benefits
                    if !configuration.benefits.isEmpty {
                        benefitsSection
                    }
                    
                    // Products
                    productsSection
                    
                    // Purchase button
                    purchaseButton
                    
                    // Terms
                    termsView
                }
                .padding()
            }
            .navigationTitle(configuration.title)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.large)
            #endif
            .toolbar {
                if configuration.showCloseButton {
                    #if os(iOS)
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Close") {
                            onDismiss?()
                        }
                    }
                    #else
                    ToolbarItem(placement: .automatic) {
                        Button("Close") {
                            onDismiss?()
                        }
                    }
                    #endif
                }
            }
        }
        .task {
            // Auto-track paywall viewed
            ArcheryAnalyticsConfiguration.shared.track(
                .paywallViewed(
                    source: source,
                    requiredEntitlement: requiredEntitlement?.analyticsDescription
                )
            )

            await store.loadProducts()
            if let firstProduct = store.products.first {
                selectedProduct = firstProduct
            }
        }
        .alert("Purchase Failed", isPresented: $showingError) {
            Button("OK") { }
        } message: {
            if let error = store.error {
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
    
    private var headerView: some View {
        VStack(spacing: 16) {
            if let icon = configuration.icon {
                Image(systemName: icon)
                    .font(.system(size: 60))
                    .foregroundStyle(configuration.accentColor.gradient)
            }
            
            Text(configuration.headline)
                .font(.title2)
                .fontWeight(.bold)
                .multilineTextAlignment(.center)
            
            if let subtitle = configuration.subtitle {
                Text(subtitle)
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.vertical)
    }
    
    private var benefitsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(configuration.benefits, id: \.self) { benefit in
                HStack(spacing: 12) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(configuration.accentColor)
                    Text(benefit)
                        .font(.body)
                    Spacer()
                }
            }
        }
        .padding()
        .background(Color.gray.opacity(0.1))
        .cornerRadius(12)
    }
    
    private var productsSection: some View {
        VStack(spacing: 12) {
            ForEach(store.products, id: \.id) { product in
                ProductRowView(
                    product: product,
                    isSelected: selectedProduct?.id == product.id,
                    configuration: configuration
                ) {
                    selectedProduct = product
                }
            }
        }
    }
    
    private var purchaseButton: some View {
        Button(action: purchase) {
            HStack {
                Text(configuration.purchaseButtonTitle)
                if let product = selectedProduct {
                    Text("• \(product.displayPrice)")
                        .fontWeight(.bold)
                }
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(configuration.accentColor.gradient)
            .foregroundColor(.white)
            .cornerRadius(12)
        }
        .disabled(selectedProduct == nil || isPurchasing)
    }
    
    private var termsView: some View {
        VStack(spacing: 8) {
            Button("Restore Purchases") {
                Task {
                    isPurchasing = true
                    await store.restorePurchases()
                    isPurchasing = false
                }
            }
            .font(.footnote)
            
            HStack(spacing: 16) {
                Link("Terms of Use", destination: configuration.termsURL)
                Link("Privacy Policy", destination: configuration.privacyURL)
            }
            .font(.caption)
            .foregroundColor(.secondary)
        }
        .padding(.top)
    }
    
    private func purchase() {
        guard let product = selectedProduct else { return }

        // Auto-track purchase started
        ArcheryAnalyticsConfiguration.shared.track(
            .purchaseStarted(
                productId: product.id,
                price: NSDecimalNumber(decimal: product.price).doubleValue
            )
        )

        Task {
            isPurchasing = true
            defer { isPurchasing = false }

            if let transaction = await store.purchase(product) {
                // Auto-track purchase completed
                ArcheryAnalyticsConfiguration.shared.track(
                    .purchaseCompleted(
                        productId: product.id,
                        price: NSDecimalNumber(decimal: product.price).doubleValue,
                        transactionId: String(transaction.id)
                    )
                )

                onPurchaseComplete?(transaction)
                onDismiss?()
            } else if let error = store.error {
                // Auto-track purchase failed
                let nsError = error as NSError
                ArcheryAnalyticsConfiguration.shared.track(
                    .purchaseFailed(
                        productId: product.id,
                        errorCode: String(nsError.code),
                        errorMessage: error.localizedDescription
                    )
                )

                showingError = true
            }
        }
    }
}

// MARK: - Product Row View

struct ProductRowView: View {
    let product: Product
    let isSelected: Bool
    let configuration: PaywallConfiguration
    let onSelect: () -> Void
    
    var body: some View {
        Button(action: onSelect) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(product.displayName)
                            .font(.headline)
                        
                        if let badge = badge(for: product) {
                            Text(badge)
                                .font(.caption)
                                .fontWeight(.semibold)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2)
                                .background(configuration.accentColor)
                                .foregroundColor(.white)
                                .cornerRadius(4)
                        }
                    }
                    
                    if !product.description.isEmpty {
                        Text(product.description)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 2) {
                    Text(product.displayPrice)
                        .font(.headline)
                    
                    if let subscription = product.subscription {
                        Text(subscription.subscriptionPeriod.debugDescription)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? configuration.accentColor : Color.secondary)
            }
            .padding()
            .background(isSelected ? configuration.accentColor.opacity(0.1) : Color.gray.opacity(0.05))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? configuration.accentColor : Color.clear, lineWidth: 2)
            )
            .cornerRadius(12)
        }
        .buttonStyle(.plain)
    }
    
    private func badge(for product: Product) -> String? {
        // Add custom badges based on product
        if product.id.contains("yearly") {
            return "BEST VALUE"
        } else if product.id.contains("lifetime") {
            return "ONE TIME"
        }
        return nil
    }
}

// MARK: - Paywall Configuration

public struct PaywallConfiguration {
    public let title: String
    public let headline: String
    public let subtitle: String?
    public let icon: String?
    public let benefits: [String]
    public let accentColor: Color
    public let purchaseButtonTitle: String
    public let showCloseButton: Bool
    public let termsURL: URL
    public let privacyURL: URL
    
    public init(
        title: String = "Premium",
        headline: String = "Unlock Premium Features",
        subtitle: String? = nil,
        icon: String? = "crown.fill",
        benefits: [String] = [],
        accentColor: Color = .blue,
        purchaseButtonTitle: String = "Continue",
        showCloseButton: Bool = true,
        termsURL: URL = URL(string: "https://example.com/terms")!,
        privacyURL: URL = URL(string: "https://example.com/privacy")!
    ) {
        self.title = title
        self.headline = headline
        self.subtitle = subtitle
        self.icon = icon
        self.benefits = benefits
        self.accentColor = accentColor
        self.purchaseButtonTitle = purchaseButtonTitle
        self.showCloseButton = showCloseButton
        self.termsURL = termsURL
        self.privacyURL = privacyURL
    }
    
    nonisolated(unsafe) public static let `default` = PaywallConfiguration()

    nonisolated(unsafe) public static let premium = PaywallConfiguration(
        title: "Go Premium",
        headline: "Unlock All Features",
        subtitle: "Get unlimited access to all premium features",
        icon: "crown.fill",
        benefits: [
            "Unlimited projects",
            "Advanced analytics",
            "Priority support",
            "No advertisements",
            "Cloud sync",
            "Export to all formats"
        ],
        accentColor: .purple,
        purchaseButtonTitle: "Start Free Trial"
    )
}

// MARK: - Mini Upsell View

/// Compact upsell prompt for inline display
public struct MiniUpsellView: View {
    @State private var store = StoreKitManager.shared
    @State private var showingPaywall = false
    
    let configuration: MiniUpsellConfiguration
    
    public init(configuration: MiniUpsellConfiguration = .default) {
        self.configuration = configuration
    }
    
    public var body: some View {
        Button(action: { showingPaywall = true }) {
            HStack {
                Image(systemName: configuration.icon)
                    .font(.title3)
                    .foregroundStyle(configuration.accentColor)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(configuration.title)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    Text(configuration.subtitle)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding()
            .background(configuration.backgroundColor)
            .cornerRadius(12)
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showingPaywall) {
            PaywallView(
                configuration: configuration.paywallConfiguration,
                source: "mini_upsell"
            )
        }
    }
}

public struct MiniUpsellConfiguration {
    public let title: String
    public let subtitle: String
    public let icon: String
    public let accentColor: Color
    public let backgroundColor: Color
    public let paywallConfiguration: PaywallConfiguration
    
    public init(
        title: String = "Upgrade to Premium",
        subtitle: String = "Unlock all features",
        icon: String = "crown.fill",
        accentColor: Color = .blue,
        backgroundColor: Color = Color.blue.opacity(0.1),
        paywallConfiguration: PaywallConfiguration = .default
    ) {
        self.title = title
        self.subtitle = subtitle
        self.icon = icon
        self.accentColor = accentColor
        self.backgroundColor = backgroundColor
        self.paywallConfiguration = paywallConfiguration
    }
    
    nonisolated(unsafe) public static let `default` = MiniUpsellConfiguration()
}

// MARK: - Entitlement-Aware Views

/// View modifier that shows content based on entitlements
public struct EntitlementGated: ViewModifier {
    @State private var store = StoreKitManager.shared
    let entitlement: Entitlement
    let fallback: AnyView?
    
    public init(entitlement: Entitlement, fallback: AnyView? = nil) {
        self.entitlement = entitlement
        self.fallback = fallback
    }
    
    public func body(content: Content) -> some View {
        if store.hasEntitlement(entitlement) {
            content
        } else {
            if let fallback = fallback {
                fallback
            } else {
                EntitlementLockedView(entitlement: entitlement)
            }
        }
    }
}

/// Default locked content view
public struct EntitlementLockedView: View {
    @State private var showingPaywall = false
    let entitlement: Entitlement

    public var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "lock.fill")
                .font(.largeTitle)
                .foregroundColor(.secondary)

            Text("Premium Feature")
                .font(.headline)

            Text("Upgrade to \(entitlement.displayName) to unlock this feature")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            Button("Unlock Now") {
                showingPaywall = true
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
        .sheet(isPresented: $showingPaywall) {
            PaywallView(
                source: "entitlement_locked",
                requiredEntitlement: .required(entitlement)
            )
        }
    }
}

// MARK: - Subscription Status View

/// Shows current subscription status and management options
public struct SubscriptionStatusView: View {
    @State private var store = StoreKitManager.shared
    @State private var showingManageSubscription = false

    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Subscription", systemImage: "creditcard.fill")
                .font(.headline)
            
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Status")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(store.subscriptionStatus.description)
                        .font(.subheadline)
                }
                
                Spacer()
                
                if store.subscriptionStatus.isActive {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                }
            }
            
            if store.subscriptionStatus.isActive {
                Button("Manage Subscription") {
                    showingManageSubscription = true
                }
                .font(.footnote)
            } else {
                Button("Subscribe Now") {
                    // Show paywall
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .background(Color.gray.opacity(0.1))
        .cornerRadius(12)
        .sheet(isPresented: $showingManageSubscription) {
            ManageSubscriptionView()
        }
    }
}

// MARK: - Manage Subscription View

struct ManageSubscriptionView: View {
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button("View in App Store") {
                        Task {
                            await openAppStoreSubscriptionManagement()
                        }
                    }
                    
                    Button("Cancel Subscription") {
                        Task {
                            await openAppStoreSubscriptionManagement()
                        }
                    }
                    .foregroundColor(.red)
                }
                
                Section {
                    Link("Terms of Use", destination: URL(string: "https://example.com/terms")!)
                    Link("Privacy Policy", destination: URL(string: "https://example.com/privacy")!)
                }
            }
            .navigationTitle("Manage Subscription")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                #if os(iOS)
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
                #else
                ToolbarItem(placement: .automatic) {
                    Button("Done") {
                        dismiss()
                    }
                }
                #endif
            }
        }
    }

    private func openAppStoreSubscriptionManagement() async {
        #if os(iOS)
        if let scene = await UIApplication.shared.connectedScenes.first as? UIWindowScene {
            do {
                try await AppStore.showManageSubscriptions(in: scene)
            } catch {
                // Handle error
            }
        }
        #endif
    }
}

// MARK: - EntitlementRequirement-Aware Views

/// View modifier that shows content based on EntitlementRequirement
public struct RequirementGated: ViewModifier {
    @State private var store = StoreKitManager.shared
    let requirement: EntitlementRequirement
    let behavior: GatedTabBehavior
    let autoPaywall: Bool

    public init(
        requirement: EntitlementRequirement,
        behavior: GatedTabBehavior = .locked,
        autoPaywall: Bool = true
    ) {
        self.requirement = requirement
        self.behavior = behavior
        self.autoPaywall = autoPaywall
    }

    public func body(content: Content) -> some View {
        let hasAccess = requirement.isSatisfied(by: store.entitlements)

        switch (hasAccess, behavior) {
        case (true, _):
            content
        case (false, .hidden):
            EmptyView()
        case (false, .locked):
            RequirementLockedView(requirement: requirement, autoPaywall: autoPaywall)
        case (false, .disabled):
            content
                .disabled(true)
                .opacity(0.4)
                .overlay(
                    Image(systemName: "lock.fill")
                        .font(.title)
                        .foregroundStyle(.secondary)
                )
        case (false, .limited):
            content
                .environment(\.entitlementLimited, true)
        }
    }
}

/// Locked view for EntitlementRequirement (supports anyOf/allOf)
public struct RequirementLockedView: View {
    @State private var showingPaywall = false
    let requirement: EntitlementRequirement
    let autoPaywall: Bool
    let source: String

    public init(
        requirement: EntitlementRequirement,
        autoPaywall: Bool = true,
        source: String = "requirement_locked"
    ) {
        self.requirement = requirement
        self.autoPaywall = autoPaywall
        self.source = source
    }

    public var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "lock.fill")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            Text("Premium Feature")
                .font(.headline)

            Text(requirement.displayDescription)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            if autoPaywall {
                Button("Unlock Now") {
                    showingPaywall = true
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .sheet(isPresented: $showingPaywall) {
            PaywallView(
                source: source,
                requiredEntitlement: requirement
            )
        }
    }
}

/// Tab item view that handles gated behavior
public struct GatedTabItem<Content: View>: View {
    @State private var store = StoreKitManager.shared
    @State private var showingPaywall = false

    let requirement: EntitlementRequirement
    let behavior: GatedTabBehavior
    let label: String
    let icon: String
    let content: () -> Content

    public init(
        requirement: EntitlementRequirement,
        behavior: GatedTabBehavior = .locked,
        label: String,
        icon: String,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.requirement = requirement
        self.behavior = behavior
        self.label = label
        self.icon = icon
        self.content = content
    }

    public var body: some View {
        let hasAccess = requirement.isSatisfied(by: store.entitlements)

        Group {
            switch (hasAccess, behavior) {
            case (true, _):
                content()
            case (false, .hidden):
                EmptyView()
            case (false, .locked):
                RequirementLockedView(requirement: requirement, source: "gated_tab:\(label)")
            case (false, .disabled):
                content()
                    .disabled(true)
                    .opacity(0.4)
            case (false, .limited):
                content()
                    .environment(\.entitlementLimited, true)
            }
        }
        .tabItem {
            if hasAccess {
                Label(label, systemImage: icon)
            } else {
                Label(label, systemImage: behavior == .locked ? "lock.fill" : icon)
            }
        }
        .sheet(isPresented: $showingPaywall) {
            PaywallView(
                source: "gated_tab:\(label)",
                requiredEntitlement: requirement
            )
        }
    }
}

// MARK: - View Extensions

public extension View {
    /// Gate content behind an entitlement
    func requiresEntitlement(_ entitlement: Entitlement, fallback: AnyView? = nil) -> some View {
        modifier(EntitlementGated(entitlement: entitlement, fallback: fallback))
    }

    /// Gate content behind an EntitlementRequirement with configurable behavior
    func gated(
        by requirement: EntitlementRequirement,
        behavior: GatedTabBehavior = .locked,
        autoPaywall: Bool = true
    ) -> some View {
        modifier(RequirementGated(requirement: requirement, behavior: behavior, autoPaywall: autoPaywall))
    }

    /// Show paywall when triggered with source tracking
    func paywall(
        isPresented: Binding<Bool>,
        configuration: PaywallConfiguration = .default,
        source: String = "view_modifier",
        requiredEntitlement: EntitlementRequirement? = nil
    ) -> some View {
        sheet(isPresented: isPresented) {
            PaywallView(
                configuration: configuration,
                source: source,
                requiredEntitlement: requiredEntitlement
            )
        }
    }
}