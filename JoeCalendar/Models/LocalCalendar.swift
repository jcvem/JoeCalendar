//
//  LocalCalendar.swift
//  JoeCalendar
//
//  Created for JoeCalendar Phase 0 Foundation.
//  Firestore collection: `localCalendars/{id}`
//

import Foundation
import SwiftUI

public struct LocalCalendar: Identifiable, Codable, Equatable, Hashable {
    public var id: String
    public var title: String
    public var description: String
    public var coverImageUrl: String?
    public var region: String
    public var category: String
    public var colorHex: String
    public var tags: [String]
    public var windowStartDate: Date
    public var windowEndDate: Date
    public var subscriberCount: Int
    public var isCurated: Bool
    public var createdAt: Date
    public var updatedAt: Date
    
    public init(
        id: String = UUID().uuidString,
        title: String,
        description: String,
        coverImageUrl: String? = nil,
        region: String = "Tokyo",
        category: String = "Culture",
        colorHex: String = AppColor.GroupPastel.sage.hexString,
        tags: [String] = [],
        windowStartDate: Date = Date(),
        windowEndDate: Date = Calendar.current.date(byAdding: .day, value: 14, to: Date()) ?? Date(),
        subscriberCount: Int = 0,
        isCurated: Bool = true,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.description = description
        self.coverImageUrl = coverImageUrl
        self.region = region
        self.category = category
        self.colorHex = colorHex
        self.tags = tags
        self.windowStartDate = windowStartDate
        self.windowEndDate = windowEndDate
        self.subscriberCount = subscriberCount
        self.isCurated = isCurated
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
    
    public var color: Color {
        Color(hexString: colorHex)
    }
}

