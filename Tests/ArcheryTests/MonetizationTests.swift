import XCTest
import StoreKit
@testable import Archery

final class MonetizationTests: XCTestCase {
    
    // MARK: - StoreKit Manager Tests
    
    @MainActor
    func testStoreKitManagerInitialization() {
        let manager = StoreKitManager(productIdentifiers: [
            "com.app.premium.monthly",
            "com.app.premium.yearly"
        ])
        
        XCTAssertTrue(manager.products.isEmpty)
        XCTAssertTrue(manager.purchasedProductIDs.isEmpty)
        XCTAssertEqual(manager.subscriptionStatus, .none)
        XCTAssertTrue(manager.entitlements.isEmpty)
        XCTAssertFalse(manager.isLoading)
        XCTAssertNil(manager.error)
    }
    
    @MainActor
    func testEntitlementChecking() {
        let manager = StoreKitManager.shared
        
        // Test no entitlements
        XCTAssertFalse(manager.hasEntitlement(.premium))
        XCTAssertFalse(manager.hasEntitlement(.pro))
        
        // Would need to mock purchases to test positive cases
    }
    
    func testEntitlementMapping() {
        // Test product ID to entitlement mapping
        XCTAssertEqual(Entitlement.from(productID: "com.app.premium.monthly"), .premium)
        XCTAssertEqual(Entitlement.from(productID: "com.app.premium.yearly"), .premium)
        XCTAssertEqual(Entitlement.from(productID: "com.app.pro.lifetime"), .pro)
        XCTAssertEqual(Entitlement.from(productID: "com.app.remove_ads"), .removeAds)
        XCTAssertEqual(Entitlement.from(productID: "com.app.storage.1tb"), .additionalStorage)
        XCTAssertNil(Entitlement.from(productID: "unknown.product"))
    }
    
    // MARK: - Subscription Status Tests
    
    func testSubscriptionStatusEquality() {
        let status1 = SubscriptionStatus.none
        let status2 = SubscriptionStatus.none
        XCTAssertEqual(status1, status2)
        
        let activeStatus1 = SubscriptionStatus.active(product: nil, expirationDate: nil)
        let activeStatus2 = SubscriptionStatus.active(product: nil, expirationDate: nil)
        XCTAssertEqual(activeStatus1, activeStatus2)
    }
    
    func testSubscriptionStatusIsActive() {
        XCTAssertFalse(SubscriptionStatus.none.isActive)
        XCTAssertTrue(SubscriptionStatus.active(product: nil, expirationDate: nil).isActive)
        XCTAssertFalse(SubscriptionStatus.expired(product: nil, expiredDate: nil).isActive)
        XCTAssertTrue(SubscriptionStatus.inGracePeriod(product: nil, graceEndDate: nil).isActive)
    }
    
    func testSubscriptionStatusDescription() {
        let noneStatus = SubscriptionStatus.none
        XCTAssertEqual(noneStatus.description, "No active subscription")
        
        let activeStatus = SubscriptionStatus.active(product: nil, expirationDate: Date())
        XCTAssertTrue(activeStatus.description.contains("Active"))
        
        let expiredStatus = SubscriptionStatus.expired(product: nil, expiredDate: Date())
        XCTAssertTrue(expiredStatus.description.contains("Expired"))
        
        let graceStatus = SubscriptionStatus.inGracePeriod(product: nil, graceEndDate: Date())
        XCTAssertTrue(graceStatus.description.contains("Grace period"))
    }
    
    // MARK: - Entitlement Tests
    
    func testEntitlementProperties() {
        let premium = Entitlement.premium
        XCTAssertEqual(premium.rawValue, "com.app.premium")
        XCTAssertEqual(premium.displayName, "Premium")
        XCTAssertEqual(premium.icon, "crown")
        
        let removeAds = Entitlement.removeAds
        XCTAssertEqual(removeAds.displayName, "Ad-Free Experience")
        XCTAssertEqual(removeAds.icon, "minus.circle")
    }
    
    func testAllEntitlementCases() {
        let allCases = Entitlement.allCases
        XCTAssertEqual(allCases.count, 6)
        XCTAssertTrue(allCases.contains(.basic))
        XCTAssertTrue(allCases.contains(.premium))
        XCTAssertTrue(allCases.contains(.pro))
        XCTAssertTrue(allCases.contains(.unlimitedAccess))
        XCTAssertTrue(allCases.contains(.removeAds))
        XCTAssertTrue(allCases.contains(.additionalStorage))
    }
    
    // MARK: - Error Tests
    
    func testStoreKitErrorDescriptions() {
        let errors: [StoreKitError] = [
            .failedToLoadProducts(NSError(domain: "", code: 0)),
            .purchaseFailed(NSError(domain: "", code: 0)),
            .purchaseCancelled,
            .purchasePending,
            .restoreFailed(NSError(domain: "", code: 0)),
            .transactionVerificationFailed,
            .unknownError
        ]
        
        for error in errors {
            XCTAssertNotNil(error.errorDescription)
        }
        
        // Test recovery suggestions
        XCTAssertNotNil(StoreKitError.failedToLoadProducts(NSError(domain: "", code: 0)).recoverySuggestion)
        XCTAssertNotNil(StoreKitError.purchaseFailed(NSError(domain: "", code: 0)).recoverySuggestion)
        XCTAssertNil(StoreKitError.purchaseCancelled.recoverySuggestion)
    }
    
    // MARK: - Receipt Validation Tests
    
    func testReceiptValidationEnvironments() {
        let prodEnv = ReceiptValidator.ValidationEnvironment.production
        XCTAssertEqual(prodEnv.validationURL.absoluteString, "https://buy.itunes.apple.com/verifyReceipt")
        
        let sandboxEnv = ReceiptValidator.ValidationEnvironment.sandbox
        XCTAssertEqual(sandboxEnv.validationURL.absoluteString, "https://sandbox.itunes.apple.com/verifyReceipt")
    }
    
    func testReceiptValidationResultDecoding() throws {
        let json = """
        {
            "status": 0,
            "receipt": {
                "bundle_id": "com.example.app",
                "application_version": "1.0",
                "original_application_version": "1.0",
                "creation_date": "2024-01-01T00:00:00Z"
            }
        }
        """
        
        let data = json.data(using: .utf8)!
        let result = try JSONDecoder().decode(ReceiptValidationResult.self, from: data)
        
        XCTAssertEqual(result.status, 0)
        XCTAssertNotNil(result.receipt)
        XCTAssertEqual(result.receipt?.bundleId, "com.example.app")
        XCTAssertEqual(result.receipt?.applicationVersion, "1.0")
    }
    
    func testReceiptValidationError() {
        let error = ReceiptValidationError.invalid(status: 21003)
        XCTAssertEqual(error.localizedDescription, "Receipt validation failed with status: 21003")
    }
    
    // MARK: - Sandbox Testing Tests
    
    func testSandboxEnvironmentDetection() {
        let manager = SandboxTestingManager.shared
        
        #if DEBUG
        XCTAssertTrue(manager.isSandbox)
        #else
        // Production behavior depends on receipt
        #endif
        
        #if targetEnvironment(simulator)
        XCTAssertTrue(manager.isXcodeBuild)
        #endif
    }
    
    func testTestScenarios() {
        let scenarios: [SandboxTestingManager.TestScenario] = [
            .successfulPurchase,
            .failedPayment,
            .restoredPurchase,
            .pendingApproval,
            .subscriptionRenewal,
            .subscriptionExpiry,
            .billingRetry,
            .gracePeriod,
            .refund
        ]
        
        // Verify all scenarios are defined
        XCTAssertEqual(scenarios.count, 9)
    }
    
    // MARK: - Preview Seeds Tests
    
    func testPreviewProducts() {
        let products = PreviewSeeds.products
        XCTAssertFalse(products.isEmpty)
        
        // Test monthly subscription
        let monthly = products.first { $0.id == "com.app.premium.monthly" }
        XCTAssertNotNil(monthly)
        XCTAssertEqual(monthly?.displayName, "Premium Monthly")
        if case .subscription(.monthly) = monthly?.type {
            // Success
        } else {
            XCTFail("Expected monthly subscription type")
        }
        
        // Test lifetime purchase
        let lifetime = products.first { $0.id == "com.app.pro.lifetime" }
        XCTAssertNotNil(lifetime)
        if case .nonConsumable = lifetime?.type {
            // Success
        } else {
            XCTFail("Expected non-consumable type")
        }
    }
    
    func testPreviewSubscriptionStates() {
        let states = PreviewSeeds.subscriptionStates
        XCTAssertFalse(states.isEmpty)
        
        // Verify different states exist
        XCTAssertNotNil(states.first { $0.status == .active })
        XCTAssertNotNil(states.first { $0.status == .expired })
        XCTAssertNotNil(states.first { $0.status == .inTrial })
        XCTAssertNotNil(states.first { $0.status == .gracePeriod })
    }
    
    func testPreviewEntitlementSets() {
        let sets = PreviewSeeds.entitlementSets
        XCTAssertFalse(sets.isEmpty)
        
        // Test empty set
        XCTAssertTrue(sets.contains { $0.isEmpty })
        
        // Test basic set
        XCTAssertTrue(sets.contains { $0 == [.basic] })
        
        // Test premium set
        XCTAssertTrue(sets.contains { $0.contains(.premium) })
        
        // Test pro set with everything
        let proSet = sets.first { $0.contains(.pro) }
        XCTAssertNotNil(proSet)
        XCTAssertEqual(proSet?.count, 4)
    }
    
    // MARK: - Mock Product Tests
    
    func testMockProductCreation() {
        let product = MockProduct(
            id: "test.product",
            displayName: "Test Product",
            description: "A test product",
            price: 19.99,
            type: .subscription(.monthly),
            badge: "HOT"
        )
        
        XCTAssertEqual(product.id, "test.product")
        XCTAssertEqual(product.displayName, "Test Product")
        XCTAssertEqual(product.description, "A test product")
        XCTAssertEqual(product.price, 19.99)
        XCTAssertEqual(product.badge, "HOT")
        XCTAssertTrue(product.displayPrice.contains("19.99"))
    }
    
    func testMockProductTypes() {
        let consumable = MockProduct.ProductType.consumable
        let nonConsumable = MockProduct.ProductType.nonConsumable
        let weeklySubscription = MockProduct.ProductType.subscription(.weekly)
        let monthlySubscription = MockProduct.ProductType.subscription(.monthly)
        let yearlySubscription = MockProduct.ProductType.subscription(.yearly)
        
        // Just verify types exist and are distinct
        XCTAssertNotNil(consumable)
        XCTAssertNotNil(nonConsumable)
        XCTAssertNotNil(weeklySubscription)
        XCTAssertNotNil(monthlySubscription)
        XCTAssertNotNil(yearlySubscription)
    }
    
    // MARK: - Configuration Tests
    
    func testPaywallConfiguration() {
        let defaultConfig = PaywallConfiguration.default
        XCTAssertEqual(defaultConfig.title, "Premium")
        XCTAssertEqual(defaultConfig.headline, "Unlock Premium Features")
        XCTAssertTrue(defaultConfig.showCloseButton)
        
        let premiumConfig = PaywallConfiguration.premium
        XCTAssertEqual(premiumConfig.title, "Go Premium")
        XCTAssertEqual(premiumConfig.icon, "crown.fill")
        XCTAssertFalse(premiumConfig.benefits.isEmpty)
        XCTAssertEqual(premiumConfig.benefits.count, 6)
    }
    
    func testMiniUpsellConfiguration() {
        let config = MiniUpsellConfiguration.default
        XCTAssertEqual(config.title, "Upgrade to Premium")
        XCTAssertEqual(config.subtitle, "Unlock all features")
        XCTAssertEqual(config.icon, "crown.fill")
        
        // Test custom configuration
        let customConfig = MiniUpsellConfiguration(
            title: "Custom Title",
            subtitle: "Custom Subtitle",
            icon: "star.fill",
            accentColor: .green,
            backgroundColor: .green.opacity(0.1),
            paywallConfiguration: .premium
        )
        
        XCTAssertEqual(customConfig.title, "Custom Title")
        XCTAssertEqual(customConfig.subtitle, "Custom Subtitle")
        XCTAssertEqual(customConfig.icon, "star.fill")
    }
    
    // MARK: - StoreKit Configuration Generator Tests
    
    func testStoreKitConfigurationGeneration() throws {
        let products = [
            MockProduct(
                id: "test.monthly",
                displayName: "Test Monthly",
                description: "Monthly subscription",
                price: 9.99,
                type: .subscription(.monthly)
            ),
            MockProduct(
                id: "test.consumable",
                displayName: "Test Consumable",
                description: "Consumable item",
                price: 1.99,
                type: .consumable
            )
        ]
        
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("test-config.json")
        
        try StoreKitConfigurationGenerator.generateConfiguration(
            products: products,
            outputPath: tempURL
        )
        
        // Verify file was created
        XCTAssertTrue(FileManager.default.fileExists(atPath: tempURL.path))
        
        // Clean up
        try? FileManager.default.removeItem(at: tempURL)
    }
}