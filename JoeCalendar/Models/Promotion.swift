//
//  Promotion.swift
//  JoeCalendar
//
//  Created for JoeCalendar Phase 0 Foundation.
//  Firestore collection: `promotions/{id}`
//

import Foundation

public struct PromotionTargeting: Codable, Equatable, Hashable {
    public var regions: [String]
    public var interests: [String]
    
    public init(regions: [String] = [], interests: [String] = []) {
        self.regions = regions
        self.interests = interests
    }
}

public struct Promotion: Identifiable, Codable, Equatable, Hashable {
    public var id: String
    public var sponsorName: String
    public var title: String
    public var subtitle: String?
    public var description: String
    public var bannerImageUrl: String?
    public var actionUrl: String?
    public var targeting: PromotionTargeting
    public var startDate: Date
    public var endDate: Date
    public var isPaid: Bool
    public var clickCount: Int
    public var impressionCount: Int
    public var createdAt: Date
    
    public init(
        id: String = UUID().uuidString,
        sponsorName: String,
        title: String,
        subtitle: String? = nil,
        description: String,
        bannerImageUrl: String? = nil,
        actionUrl: String? = nil,
        targeting: PromotionTargeting = PromotionTargeting(),
        startDate: Date = Date(),
        endDate: Date = Calendar.current.date(byAdding: .day, value: 30, to: Date()) ?? Date(),
        isPaid: Bool = true,
        clickCount: Int = 0,
        impressionCount: Int = 0,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.sponsorName = sponsorName
        self.title = title
        self.subtitle = subtitle
        self.description = description
        self.bannerImageUrl = bannerImageUrl
        self.actionUrl = actionUrl
        self.targeting = targeting
        self.startDate = startDate
        self.endDate = endDate
        self.isPaid = isPaid
        self.clickCount = clickCount
        self.impressionCount = impressionCount
        self.createdAt = createdAt
    }
}
