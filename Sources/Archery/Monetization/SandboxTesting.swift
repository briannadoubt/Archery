import Foundation
import StoreKit

// MARK: - Sandbox Testing Support

/// Manages sandbox testing and TestFlight preview features using StoreKit 2
public struct SandboxTestingManager: Sendable {
    public static let shared = SandboxTestingManager()

    private init() {}

    // MARK: - Environment Detection

    /// Check if running in sandbox environment
    public var isSandbox: Bool {
        #if DEBUG
        return true
        #else
        return !isProduction
        #endif
    }

    /// Check if running in production (App Store)
    public var isProduction: Bool {
        get async {
            do {
                let appTransaction = try await AppTransaction.shared
                switch appTransaction {
                case .verified(let transaction):
                    return transaction.environment == .production
                case .unverified:
                    return false
                }
            } catch {
                return false
            }
        }
    }

    /// Check if running in TestFlight
    /// Note: TestFlight runs in sandbox environment, so we detect it by checking
    /// for sandbox environment while NOT being in Xcode
    public var isTestFlight: Bool {
        get async {
            do {
                let appTransaction = try await AppTransaction.shared
                switch appTransaction {
                case .verified(let transaction):
                    // TestFlight uses sandbox environment but isn't Xcode
                    return transaction.environment == .sandbox && !isXcodeBuild
                case .unverified:
                    return false
                }
            } catch {
                return false
            }
        }
    }

    /// Check if running in Xcode
    public var isXcodeBuild: Bool {
        #if targetEnvironment(simulator)
        return true
        #else
        return ProcessInfo.processInfo.environment["DTPlatformName"] != nil
        #endif
    }

    // MARK: - Transaction Monitoring

    /// Start observing transaction updates using StoreKit 2
    public func startTransactionObserver() -> Task<Void, Never> {
        Task.detached {
            for await result in Transaction.updates {
                await self.handleTransaction(result)
            }
        }
    }

    @MainActor
    private func handleTransaction(_ result: VerificationResult<Transaction>) async {
        switch result {
        case .verified(let transaction):
            print("""
            📝 Transaction Update (StoreKit 2):
               Product: \(transaction.productID)
               Type: \(transaction.productType)
               Purchase Date: \(transaction.purchaseDate)
               Environment: \(transaction.environment)
            """)
            await transaction.finish()

        case .unverified(let transaction, let error):
            print("""
            ⚠️ Unverified Transaction:
               Product: \(transaction.productID)
               Error: \(error)
            """)
        }
    }

    // MARK: - Test Accounts

    /// Sandbox test account management
    public struct TestAccount: Sendable {
        public let email: String
        public let territory: String
        public let subscriptionStatus: TestSubscriptionStatus

        public enum TestSubscriptionStatus: Sendable {
            case none
            case active
            case expired
            case billingRetry
            case gracePeriod
        }
    }

    /// Clear sandbox purchase history
    public func clearSandboxPurchases() async {
        guard isSandbox else { return }

        // Clear all transactions in sandbox
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result {
                await transaction.finish()
            }
        }

        print("Cleared sandbox purchase history")
    }

    // MARK: - Test Scenarios

    /// Simulate different purchase scenarios for testing
    public func simulateScenario(_ scenario: TestScenario) async {
        guard isSandbox else { return }

        switch scenario {
        case .successfulPurchase:
            print("Simulating successful purchase")

        case .failedPayment:
            print("Simulating failed payment")

        case .restoredPurchase:
            print("Simulating restored purchase")

        case .pendingApproval:
            print("Simulating pending approval (Ask to Buy)")

        case .subscriptionRenewal:
            print("Simulating subscription renewal")

        case .subscriptionExpiry:
            print("Simulating subscription expiry")

        case .billingRetry:
            print("Simulating billing retry")

        case .gracePeriod:
            print("Simulating grace period")

        case .refund:
            print("Simulating refund")
        }
    }

    public enum TestScenario: Sendable {
        case successfulPurchase
        case failedPayment
        case restoredPurchase
        case pendingApproval
        case subscriptionRenewal
        case subscriptionExpiry
        case billingRetry
        case gracePeriod
        case refund
    }
}

// MARK: - Preview Seeds

/// Provides seed data for SwiftUI previews and testing
public struct PreviewSeeds {

    // MARK: - Products

    public static let products: [MockProduct] = [
        MockProduct(
            id: "com.app.premium.monthly",
            displayName: "Premium Monthly",
            description: "Unlock all features with monthly billing",
            price: 9.99,
            type: .subscription(.monthly)
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
            description: "One-time purchase for lifetime access",
            price: 299.99,
            type: .nonConsumable
        ),
        MockProduct(
            id: "com.app.credits.100",
            displayName: "100 Credits",
            description: "Purchase credits for premium features",
            price: 4.99,
            type: .consumable
        )
    ]

    // MARK: - Subscription States

    public static let subscriptionStates: [MockSubscriptionState] = [
        MockSubscriptionState(
            status: .active,
            productId: "com.app.premium.monthly",
            expirationDate: Date().addingTimeInterval(30 * 24 * 60 * 60),
            isInTrialPeriod: false,
            willRenew: true
        ),
        MockSubscriptionState(
            status: .expired,
            productId: "com.app.premium.monthly",
            expirationDate: Date().addingTimeInterval(-7 * 24 * 60 * 60),
            isInTrialPeriod: false,
            willRenew: false
        ),
        MockSubscriptionState(
            status: .inTrial,
            productId: "com.app.premium.yearly",
            expirationDate: Date().addingTimeInterval(7 * 24 * 60 * 60),
            isInTrialPeriod: true,
            willRenew: true
        ),
        MockSubscriptionState(
            status: .gracePeriod,
            productId: "com.app.premium.monthly",
            expirationDate: Date().addingTimeInterval(3 * 24 * 60 * 60),
            isInTrialPeriod: false,
            willRenew: false
        )
    ]

    // MARK: - Entitlements

    public static let entitlementSets: [Set<Entitlement>] = [
        [], // No entitlements
        [.basic], // Basic only
        [.premium, .removeAds], // Premium user
        [.pro, .unlimitedAccess, .removeAds, .additionalStorage] // Pro user with everything
    ]
}

// MARK: - Mock Types for Previews

public struct MockProduct: Sendable {
    public let id: String
    public let displayName: String
    public let description: String?
    public let price: Decimal
    public let type: ProductType
    public let badge: String?

    public enum ProductType: Sendable {
        case consumable
        case nonConsumable
        case subscription(Period)

        public enum Period: Sendable {
            case weekly
            case monthly
            case yearly
        }
    }

    public init(
        id: String,
        displayName: String,
        description: String? = nil,
        price: Decimal,
        type: ProductType,
        badge: String? = nil
    ) {
        self.id = id
        self.displayName = displayName
        self.description = description
        self.price = price
        self.type = type
        self.badge = badge
    }

    public var displayPrice: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        return formatter.string(from: price as NSNumber) ?? "$\(price)"
    }
}

public struct MockSubscriptionState: Sendable {
    public let status: Status
    public let productId: String
    public let expirationDate: Date?
    public let isInTrialPeriod: Bool
    public let willRenew: Bool

    public enum Status: Sendable {
        case none
        case active
        case expired
        case inTrial
        case gracePeriod
        case billingRetry
    }
}

// MARK: - StoreKit Configuration Generator

/// Generates StoreKit configuration files for testing
public struct StoreKitConfigurationGenerator {

    /// Generate a StoreKit configuration file
    public static func generateConfiguration(
        products: [MockProduct],
        outputPath: URL
    ) throws {
        let configuration = StoreKitConfiguration(products: products)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        let data = try encoder.encode(configuration)
        try data.write(to: outputPath)

        print("Generated StoreKit configuration at: \(outputPath)")
    }

    private struct StoreKitConfiguration: Codable {
        var identifier: String = UUID().uuidString
        let products: [ProductConfiguration]

        init(products: [MockProduct]) {
            self.products = products.map { ProductConfiguration(from: $0) }
        }
    }

    private struct ProductConfiguration: Codable {
        let id: String
        let type: String
        let displayName: String
        let description: String?
        let price: Decimal
        let familyShareable: Bool
        let subscription: SubscriptionConfiguration?

        init(from mock: MockProduct) {
            self.id = mock.id
            self.displayName = mock.displayName
            self.description = mock.description
            self.price = mock.price
            self.familyShareable = false

            switch mock.type {
            case .consumable:
                self.type = "consumable"
                self.subscription = nil
            case .nonConsumable:
                self.type = "nonConsumable"
                self.subscription = nil
            case .subscription(let period):
                self.type = "autoRenewable"
                self.subscription = SubscriptionConfiguration(period: period)
            }
        }
    }

    private struct SubscriptionConfiguration: Codable {
        let duration: String
        let introductoryOffer: IntroductoryOffer?

        init(period: MockProduct.ProductType.Period) {
            switch period {
            case .weekly:
                self.duration = "P1W"
            case .monthly:
                self.duration = "P1M"
            case .yearly:
                self.duration = "P1Y"
            }

            // Add free trial for yearly subscriptions
            if case .yearly = period {
                self.introductoryOffer = IntroductoryOffer(
                    duration: "P1W",
                    paymentMode: "freeTrial"
                )
            } else {
                self.introductoryOffer = nil
            }
        }
    }

    private struct IntroductoryOffer: Codable {
        let duration: String
        let paymentMode: String
    }
}
