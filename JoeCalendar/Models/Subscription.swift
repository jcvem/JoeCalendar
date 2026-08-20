//
//  Subscription.swift
//  JoeCalendar
//
//  Created for JoeCalendar Phase 0 Foundation.
//  Firestore collection: `subscriptions/{uid}`
//

import Foundation

public enum SubscriptionStatus: String, Codable {
    case active = "active"
    case trialing = "trialing"
    case pastDue = "past_due"
    case canceled = "canceled"
    case expired = "expired"
}

public struct Subscription: Identifiable, Codable, Equatable {
    public var id: String // uid
    public var isAdFree: Bool
    public var planId: String
    public var status: SubscriptionStatus
    public var currentPeriodStart: Date
    public var currentPeriodEnd: Date
    public var cancelAtPeriodEnd: Bool
    public var updatedAt: Date
    
    public init(
        id: String,
        isAdFree: Bool = false,
        planId: String = "free",
        status: SubscriptionStatus = .active,
        currentPeriodStart: Date = Date(),
        currentPeriodEnd: Date = Calendar.current.date(byAdding: .year, value: 100, to: Date()) ?? Date(),
        cancelAtPeriodEnd: Bool = false,
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.isAdFree = isAdFree
        self.planId = planId
        self.status = status
        self.currentPeriodStart = currentPeriodStart
        self.currentPeriodEnd = currentPeriodEnd
        self.cancelAtPeriodEnd = cancelAtPeriodEnd
        self.updatedAt = updatedAt
    }
    
    public var isPro: Bool {
        isAdFree && (status == .active || status == .trialing)
    }
    
    public var isMonthly: Bool {
        planId.contains("monthly")
    }
    
    public var isYearly: Bool {
        planId.contains("yearly")
    }
}

