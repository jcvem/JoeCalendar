//
//  SubscriptionService.swift
//  JoeCalendar
//
//  Created for JoeCalendar Phase 3 Monetization.
//  StoreKit 2 integration managing freemium ad-removal subscriptions,
//  App Store product querying, transaction verification, restore purchases,
//  and Firestore subscription mirror sync (subscriptions/{uid} & users/{uid}.isAdFree).
//

import Foundation
import StoreKit
import Combine
import SwiftUI

public enum SubscriptionPlanType: String, CaseIterable, Identifiable {
    case monthly = "joecalendar_pro_monthly"
    case yearly = "joecalendar_pro_yearly"
    
    public var id: String { rawValue }
    
    public var titleKey: String {
        switch self {
        case .monthly: return "paywall_plan_monthly"
        case .yearly: return "paywall_plan_yearly"
        }
    }
    
    public var defaultPriceDisplay: String {
        switch self {
        case .monthly: return "$2.99"
        case .yearly: return "$29.99"
        }
    }
    
    public var defaultPeriodDisplayKey: String {
        switch self {
        case .monthly: return "paywall_period_month"
        case .yearly: return "paywall_period_year"
        }
    }
}

@MainActor
public final class SubscriptionService: ObservableObject {
    public static let shared = SubscriptionService()
    
    // Product identifiers
    public static let monthlyProductId = "joecalendar_pro_monthly"
    public static let yearlyProductId = "joecalendar_pro_yearly"
    public static let productIds: Set<String> = [monthlyProductId, yearlyProductId]
    
    // MARK: - Published State
    @Published public private(set) var isAdFree: Bool = false
    @Published public private(set) var currentSubscription: Subscription?
    @Published public private(set) var products: [Product] = []
    @Published public private(set) var hasStoreKitProducts: Bool = false
    @Published public var isLoading: Bool = false
    @Published public var isPurchasing: Bool = false
    @Published public var isRestoring: Bool = false
    @Published public var errorMessage: String? = nil
    @Published public var purchaseSuccessAlert: Bool = false
    
    // Persistence Keys
    private let isAdFreeKey = "joecalendar_is_ad_free_v1"
    private let subscriptionDataKey = "joecalendar_subscription_data_v1"
    
    // Firestore REST configuration (joecalendar-e8327)
    private let projectId = "joecalendar-e8327"
    private var firestoreBaseURL: String {
        "https://firestore.googleapis.com/v1/projects/\(projectId)/databases/(default)/documents"
    }
    
    private var transactionListenerTask: Task<Void, Never>? = nil
    
    private init() {
        loadPersistedState()
        
        // Start listening to StoreKit 2 transaction updates
        transactionListenerTask = listenForTransactions()
        
        Task {
            await fetchProducts()
            await checkCurrentEntitlements()
        }
    }
    
    deinit {
        transactionListenerTask?.cancel()
    }
    
    // MARK: - StoreKit 2 Product Loading
    
    public func fetchProducts() async {
        self.isLoading = true
        defer { self.isLoading = false }
        
        do {
            let fetchedProducts = try await Product.products(for: Self.productIds)
            self.products = fetchedProducts.sorted { $0.price < $1.price }
            self.hasStoreKitProducts = !fetchedProducts.isEmpty
        } catch {
            print("StoreKit: Failed to load products from App Store Connect: \(error.localizedDescription)")
            self.products = []
            self.hasStoreKitProducts = false
        }
    }
    
    // MARK: - Transaction Updates Listener
    
    private func listenForTransactions() -> Task<Void, Never> {
        return Task.detached {
            for await result in StoreKit.Transaction.updates {
                do {
                    let transaction = try self.checkVerified(result)
                    await self.handleSuccessfulTransaction(transaction)
                    await transaction.finish()
                } catch {
                    print("StoreKit: Transaction verification failed: \(error.localizedDescription)")
                }
            }
        }
    }
    
    // MARK: - Entitlements Check
    
    public func checkCurrentEntitlements() async {
        var foundActivePro = false
        var activePlan = "free"
        var expirationDate = Date()
        
        for await result in StoreKit.Transaction.currentEntitlements {
            do {
                let transaction = try checkVerified(result)
                if Self.productIds.contains(transaction.productID) {
                    if let expDate = transaction.expirationDate {
                        if expDate > Date() {
                            foundActivePro = true
                            activePlan = transaction.productID
                            expirationDate = expDate
                        }
                    } else {
                        // Lifetime or non-expiring
                        foundActivePro = true
                        activePlan = transaction.productID
                        expirationDate = Calendar.current.date(byAdding: .year, value: 1, to: Date()) ?? Date()
                    }
                }
            } catch {
                print("StoreKit: Error verifying current entitlement: \(error.localizedDescription)")
            }
        }
        
        if foundActivePro {
            await applyAdFreeEntitlement(planId: activePlan, expiryDate: expirationDate)
        }
    }
    
    // MARK: - Purchase Actions
    
    /// Purchases a StoreKit product
    public func purchase(_ product: Product) async throws -> Bool {
        self.isPurchasing = true
        self.errorMessage = nil
        defer { self.isPurchasing = false }
        
        do {
            let result = try await product.purchase()
            
            switch result {
            case .success(let verification):
                let transaction = try checkVerified(verification)
                await handleSuccessfulTransaction(transaction)
                await transaction.finish()
                self.purchaseSuccessAlert = true
                return true
                
            case .userCancelled:
                return false
                
            case .pending:
                self.errorMessage = "Purchase is pending approval."
                return false
                
            @unknown default:
                return false
            }
        } catch {
            self.errorMessage = error.localizedDescription
            throw error
        }
    }
    
    /// Fallback / Simulated purchase mode for sandbox / offline testing before App Store Connect configuration is live
    public func simulateSandboxPurchase(plan: SubscriptionPlanType) async {
        self.isPurchasing = true
        defer { self.isPurchasing = false }
        
        try? await Task.sleep(nanoseconds: 500_000_000) // 0.5s calm feedback
        let expiry = plan == .monthly
            ? (Calendar.current.date(byAdding: .month, value: 1, to: Date()) ?? Date())
            : (Calendar.current.date(byAdding: .year, value: 1, to: Date()) ?? Date())
        
        await applyAdFreeEntitlement(planId: plan.rawValue, expiryDate: expiry)
        self.purchaseSuccessAlert = true
    }
    
    // MARK: - Restore Purchases
    
    public func restorePurchases() async throws {
        self.isRestoring = true
        self.errorMessage = nil
        defer { self.isRestoring = false }
        
        do {
            try await AppStore.sync()
            await checkCurrentEntitlements()
        } catch {
            self.errorMessage = error.localizedDescription
            throw error
        }
    }
    
    // MARK: - Helper Methods
    
    nonisolated private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified(_, let error):
            throw error
        case .verified(let safe):
            return safe
        }
    }
    
    private func handleSuccessfulTransaction(_ transaction: StoreKit.Transaction) async {
        let planId = transaction.productID
        let expiryDate = transaction.expirationDate ?? (Calendar.current.date(byAdding: .year, value: 1, to: Date()) ?? Date())
        await applyAdFreeEntitlement(planId: planId, expiryDate: expiryDate)
    }
    
    private func applyAdFreeEntitlement(planId: String, expiryDate: Date) async {
        let currentUid = FriendService.shared.currentUser.id
        
        let updatedSub = Subscription(
            id: currentUid,
            isAdFree: true,
            planId: planId,
            status: .active,
            currentPeriodStart: Date(),
            currentPeriodEnd: expiryDate,
            cancelAtPeriodEnd: false,
            updatedAt: Date()
        )
        
        self.isAdFree = true
        self.currentSubscription = updatedSub
        
        // Update FriendService current user
        var user = FriendService.shared.currentUser
        user.isAdFree = true
        
        persistState()
        
        // Asynchronously mirror to Firestore `subscriptions/{uid}` and `users/{uid}`
        Task {
            try? await pushSubscriptionToFirestore(updatedSub)
            try? await updateFirestoreUserAdFree(uid: currentUid, isAdFree: true)
        }
    }
    
    // MARK: - Local Persistence
    
    private func persistState() {
        UserDefaults.standard.set(isAdFree, forKey: isAdFreeKey)
        if let sub = currentSubscription, let data = try? JSONEncoder().encode(sub) {
            UserDefaults.standard.set(data, forKey: subscriptionDataKey)
        }
    }
    
    private func loadPersistedState() {
        self.isAdFree = UserDefaults.standard.bool(forKey: isAdFreeKey)
        if let data = UserDefaults.standard.data(forKey: subscriptionDataKey),
           let sub = try? JSONDecoder().decode(Subscription.self, from: data) {
            self.currentSubscription = sub
            if sub.currentPeriodEnd < Date() {
                self.isAdFree = false
            }
        }
    }
    
    // MARK: - Firestore REST Sync
    
    private func pushSubscriptionToFirestore(_ subscription: Subscription) async throws {
        guard let url = URL(string: "\(firestoreBaseURL)/subscriptions/\(subscription.id)") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let isoFormatter = ISO8601DateFormatter()
        let fields: [String: Any] = [
            "isAdFree": ["booleanValue": subscription.isAdFree],
            "planId": ["stringValue": subscription.planId],
            "status": ["stringValue": subscription.status.rawValue],
            "currentPeriodStart": ["timestampValue": isoFormatter.string(from: subscription.currentPeriodStart)],
            "currentPeriodEnd": ["timestampValue": isoFormatter.string(from: subscription.currentPeriodEnd)],
            "cancelAtPeriodEnd": ["booleanValue": subscription.cancelAtPeriodEnd],
            "updatedAt": ["timestampValue": isoFormatter.string(from: subscription.updatedAt)]
        ]
        
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["fields": fields])
        _ = try? await URLSession.shared.data(for: request)
    }
    
    private func updateFirestoreUserAdFree(uid: String, isAdFree: Bool) async throws {
        guard let url = URL(string: "\(firestoreBaseURL)/users/\(uid)?updateMask.fieldPaths=isAdFree") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let fields: [String: Any] = [
            "isAdFree": ["booleanValue": isAdFree]
        ]
        
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["fields": fields])
        _ = try? await URLSession.shared.data(for: request)
    }
}
