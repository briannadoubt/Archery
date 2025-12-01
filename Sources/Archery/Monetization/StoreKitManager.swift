import Foundation
import StoreKit
import SwiftUI

// MARK: - StoreKit Manager

/// Manages StoreKit 2 products, purchases, and entitlements
@MainActor
public final class StoreKitManager: ObservableObject {
    public static let shared = StoreKitManager()
    
    @Published public private(set) var products: [Product] = []
    @Published public private(set) var purchasedProductIDs: Set<String> = []
    @Published public private(set) var subscriptionStatus: SubscriptionStatus = .none
    @Published public private(set) var entitlements: Set<Entitlement> = []
    @Published public private(set) var isLoading = false
    @Published public private(set) var error: StoreKitError?
    
    private var updateListenerTask: Task<Void, Never>?
    private let productIdentifiers: Set<String>
    
    public init(productIdentifiers: Set<String> = []) {
        self.productIdentifiers = productIdentifiers
        startListeningForTransactions()
    }
    
    deinit {
        updateListenerTask?.cancel()
    }
    
    // MARK: - Product Loading
    
    /// Load products from the App Store
    public func loadProducts() async {
        isLoading = true
        error = nil
        
        do {
            products = try await Product.products(for: productIdentifiers)
            await updatePurchasedProducts()
        } catch {
            self.error = .failedToLoadProducts(error)
        }
        
        isLoading = false
    }
    
    /// Load products with specific identifiers
    public func loadProducts(identifiers: Set<String>) async {
        isLoading = true
        error = nil
        
        do {
            products = try await Product.products(for: identifiers)
            await updatePurchasedProducts()
        } catch {
            self.error = .failedToLoadProducts(error)
        }
        
        isLoading = false
    }
    
    // MARK: - Purchase
    
    /// Purchase a product
    @discardableResult
    public func purchase(_ product: Product) async -> Transaction? {
        do {
            let result = try await product.purchase()
            
            switch result {
            case .success(let verification):
                let transaction = try checkVerified(verification)
                await updatePurchasedProducts()
                await transaction.finish()
                return transaction
                
            case .userCancelled:
                error = .purchaseCancelled
                return nil
                
            case .pending:
                error = .purchasePending
                return nil
                
            @unknown default:
                error = .unknownError
                return nil
            }
        } catch {
            self.error = .purchaseFailed(error)
            return nil
        }
    }
    
    /// Purchase a product with promotional offer
    @discardableResult
    public func purchase(_ product: Product, promotionalOffer: Product.SubscriptionOffer) async -> Transaction? {
        do {
            let result = try await product.purchase(options: [
                .promotionalOffer(promotionalOffer)
            ])
            
            switch result {
            case .success(let verification):
                let transaction = try checkVerified(verification)
                await updatePurchasedProducts()
                await transaction.finish()
                return transaction
                
            case .userCancelled:
                error = .purchaseCancelled
                return nil
                
            case .pending:
                error = .purchasePending
                return nil
                
            @unknown default:
                error = .unknownError
                return nil
            }
        } catch {
            self.error = .purchaseFailed(error)
            return nil
        }
    }
    
    // MARK: - Restore Purchases
    
    /// Restore previous purchases
    public func restorePurchases() async {
        do {
            try await AppStore.sync()
            await updatePurchasedProducts()
        } catch {
            self.error = .restoreFailed(error)
        }
    }
    
    // MARK: - Subscription Management
    
    /// Update subscription status
    public func updateSubscriptionStatus() async {
        var hasActiveSubscription = false
        var currentProduct: Product?
        var expirationDate: Date?
        
        for product in products where product.type == .autoRenewable {
            guard let status = try? await product.subscription?.status else { continue }
            
            for renewal in status {
                guard case .verified(let renewalInfo) = renewal.renewalInfo,
                      case .verified(let transaction) = renewal.transaction else {
                    continue
                }
                
                if renewalInfo.willAutoRenew || 
                   (renewalInfo.expirationDate ?? Date()) > Date() {
                    hasActiveSubscription = true
                    currentProduct = product
                    expirationDate = renewalInfo.expirationDate
                    break
                }
            }
        }
        
        if hasActiveSubscription {
            subscriptionStatus = .active(
                product: currentProduct,
                expirationDate: expirationDate
            )
        } else {
            subscriptionStatus = .none
        }
        
        updateEntitlements()
    }
    
    // MARK: - Entitlements
    
    /// Update entitlements based on purchases
    private func updateEntitlements() {
        var newEntitlements: Set<Entitlement> = []
        
        // Map products to entitlements
        for productID in purchasedProductIDs {
            if let entitlement = Entitlement.from(productID: productID) {
                newEntitlements.insert(entitlement)
            }
        }
        
        // Add subscription entitlements
        if case .active = subscriptionStatus {
            newEntitlements.insert(.premium)
        }
        
        entitlements = newEntitlements
    }
    
    /// Check if user has a specific entitlement
    public func hasEntitlement(_ entitlement: Entitlement) -> Bool {
        entitlements.contains(entitlement)
    }
    
    // MARK: - Transaction Updates
    
    private func startListeningForTransactions() {
        updateListenerTask = Task {
            for await result in Transaction.updates {
                do {
                    let transaction = try self.checkVerified(result)
                    await updatePurchasedProducts()
                    await transaction.finish()
                } catch {
                    self.error = .transactionVerificationFailed
                }
            }
        }
    }
    
    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified:
            throw StoreKitError.transactionVerificationFailed
        case .verified(let safe):
            return safe
        }
    }
    
    private func updatePurchasedProducts() async {
        var purchased: Set<String> = []
        
        for await result in Transaction.currentEntitlements {
            do {
                let transaction = try checkVerified(result)
                purchased.insert(transaction.productID)
            } catch {
                continue
            }
        }
        
        purchasedProductIDs = purchased
        await updateSubscriptionStatus()
    }
}

// MARK: - Product Extensions

public extension Product {
    /// Formatted price string
    var localizedPrice: String {
        displayPrice
    }
    
    /// Check if product is purchased
    func isPurchased(by manager: StoreKitManager) -> Bool {
        manager.purchasedProductIDs.contains(id)
    }
    
    /// Get promotional offers for eligible users
    func eligiblePromotionalOffers() async -> [SubscriptionOffer] {
        guard type == .autoRenewable,
              let subscription = subscription else {
            return []
        }
        
        var offers: [SubscriptionOffer] = []
        
        for offer in subscription.promotionalOffers {
            if await offer.isEligible {
                offers.append(offer)
            }
        }
        
        return offers
    }
}

// MARK: - Types

public enum SubscriptionStatus: Equatable {
    case none
    case active(product: Product?, expirationDate: Date?)
    case expired(product: Product?, expiredDate: Date?)
    case inGracePeriod(product: Product?, graceEndDate: Date?)
    
    public var isActive: Bool {
        switch self {
        case .active, .inGracePeriod:
            return true
        case .none, .expired:
            return false
        }
    }
    
    public var description: String {
        switch self {
        case .none:
            return "No active subscription"
        case .active(_, let date):
            if let date = date {
                return "Active until \(date.formatted())"
            }
            return "Active"
        case .expired(_, let date):
            if let date = date {
                return "Expired on \(date.formatted())"
            }
            return "Expired"
        case .inGracePeriod(_, let date):
            if let date = date {
                return "Grace period until \(date.formatted())"
            }
            return "In grace period"
        }
    }
}

public enum Entitlement: String, CaseIterable, Codable {
    case basic = "com.app.basic"
    case premium = "com.app.premium"
    case pro = "com.app.pro"
    case unlimitedAccess = "com.app.unlimited"
    case removeAds = "com.app.remove_ads"
    case additionalStorage = "com.app.storage"
    
    public var displayName: String {
        switch self {
        case .basic: return "Basic"
        case .premium: return "Premium"
        case .pro: return "Pro"
        case .unlimitedAccess: return "Unlimited Access"
        case .removeAds: return "Ad-Free Experience"
        case .additionalStorage: return "Extra Storage"
        }
    }
    
    public var icon: String {
        switch self {
        case .basic: return "star"
        case .premium: return "crown"
        case .pro: return "bolt.circle.fill"
        case .unlimitedAccess: return "infinity"
        case .removeAds: return "minus.circle"
        case .additionalStorage: return "internaldrive"
        }
    }
    
    static func from(productID: String) -> Entitlement? {
        // Map product IDs to entitlements
        switch productID {
        case "com.app.premium.monthly", "com.app.premium.yearly":
            return .premium
        case "com.app.pro.lifetime":
            return .pro
        case "com.app.remove_ads":
            return .removeAds
        case "com.app.storage.1tb":
            return .additionalStorage
        default:
            return nil
        }
    }
}

// MARK: - Errors

public enum StoreKitError: LocalizedError {
    case failedToLoadProducts(Error)
    case purchaseFailed(Error)
    case purchaseCancelled
    case purchasePending
    case restoreFailed(Error)
    case transactionVerificationFailed
    case unknownError
    
    public var errorDescription: String? {
        switch self {
        case .failedToLoadProducts:
            return "Failed to load products from the App Store"
        case .purchaseFailed:
            return "Purchase failed. Please try again."
        case .purchaseCancelled:
            return "Purchase was cancelled"
        case .purchasePending:
            return "Purchase is pending approval"
        case .restoreFailed:
            return "Failed to restore purchases"
        case .transactionVerificationFailed:
            return "Transaction verification failed"
        case .unknownError:
            return "An unknown error occurred"
        }
    }
    
    public var recoverySuggestion: String? {
        switch self {
        case .failedToLoadProducts:
            return "Check your internet connection and try again"
        case .purchaseFailed, .restoreFailed:
            return "Please check your payment method and try again"
        case .transactionVerificationFailed:
            return "Please contact support if this persists"
        default:
            return nil
        }
    }
}

// MARK: - Receipt Validation

public struct ReceiptValidator {
    /// Validate receipt with Apple's servers
    public static func validate(
        receipt: Data,
        sharedSecret: String? = nil,
        environment: ValidationEnvironment = .production
    ) async throws -> ReceiptValidationResult {
        let endpoint = environment.validationURL
        
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        var body: [String: Any] = [
            "receipt-data": receipt.base64EncodedString()
        ]
        
        if let secret = sharedSecret {
            body["password"] = secret
        }
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, _) = try await URLSession.shared.data(for: request)
        let result = try JSONDecoder().decode(ReceiptValidationResult.self, from: data)
        
        if result.status == 21007 {
            // Receipt is for sandbox, retry with sandbox URL
            return try await validate(
                receipt: receipt,
                sharedSecret: sharedSecret,
                environment: .sandbox
            )
        }
        
        guard result.status == 0 else {
            throw ReceiptValidationError.invalid(status: result.status)
        }
        
        return result
    }
    
    public enum ValidationEnvironment {
        case production
        case sandbox
        
        var validationURL: URL {
            switch self {
            case .production:
                return URL(string: "https://buy.itunes.apple.com/verifyReceipt")!
            case .sandbox:
                return URL(string: "https://sandbox.itunes.apple.com/verifyReceipt")!
            }
        }
    }
}

public struct ReceiptValidationResult: Codable {
    public let status: Int
    public let receipt: Receipt?
    public let latestReceiptInfo: [ReceiptInfo]?
    public let pendingRenewalInfo: [PendingRenewal]?
    
    public struct Receipt: Codable {
        public let bundleId: String
        public let applicationVersion: String
        public let originalApplicationVersion: String
        public let creationDate: String
        public let expirationDate: String?
        
        enum CodingKeys: String, CodingKey {
            case bundleId = "bundle_id"
            case applicationVersion = "application_version"
            case originalApplicationVersion = "original_application_version"
            case creationDate = "creation_date"
            case expirationDate = "expiration_date"
        }
    }
    
    public struct ReceiptInfo: Codable {
        public let productId: String
        public let transactionId: String
        public let originalTransactionId: String
        public let purchaseDate: String
        public let expiresDate: String?
        public let cancellationDate: String?
        public let isTrialPeriod: String?
        
        enum CodingKeys: String, CodingKey {
            case productId = "product_id"
            case transactionId = "transaction_id"
            case originalTransactionId = "original_transaction_id"
            case purchaseDate = "purchase_date"
            case expiresDate = "expires_date"
            case cancellationDate = "cancellation_date"
            case isTrialPeriod = "is_trial_period"
        }
    }
    
    public struct PendingRenewal: Codable {
        public let productId: String
        public let autoRenewStatus: String
        public let expirationIntent: String?
        
        enum CodingKeys: String, CodingKey {
            case productId = "product_id"
            case autoRenewStatus = "auto_renew_status"
            case expirationIntent = "expiration_intent"
        }
    }
    
    enum CodingKeys: String, CodingKey {
        case status
        case receipt
        case latestReceiptInfo = "latest_receipt_info"
        case pendingRenewalInfo = "pending_renewal_info"
    }
}

public enum ReceiptValidationError: LocalizedError {
    case invalid(status: Int)
    case networkError(Error)
    case decodingError(Error)
    
    public var errorDescription: String? {
        switch self {
        case .invalid(let status):
            return "Receipt validation failed with status: \(status)"
        case .networkError:
            return "Network error during receipt validation"
        case .decodingError:
            return "Failed to decode receipt validation response"
        }
    }
}