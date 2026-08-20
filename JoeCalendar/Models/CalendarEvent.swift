//
//  CalendarEvent.swift
//  JoeCalendar
//
//  Created for JoeCalendar Phase 0 Foundation.
//  Firestore collection: `events/{eventId}`
//

import Foundation
import SwiftUI

public enum CalendarType: String, Codable, CaseIterable {
    case joe = "joe"
    case device = "device"
    case google = "google"
    case local = "local"
    case promo = "promo"
    
    public var displayNameKey: String {
        switch self {
        case .joe: return "calendar_type_joe"
        case .device: return "calendar_type_device"
        case .google: return "calendar_type_google"
        case .local: return "calendar_type_local"
        case .promo: return "calendar_type_promo"
        }
    }
}

public enum EventVisibilityType: String, Codable, CaseIterable {
    case `public` = "public"
    case group = "group"
    case `private` = "private"
    
    public var displayNameKey: String {
        switch self {
        case .public: return "visibility_public"
        case .group: return "visibility_group"
        case .private: return "visibility_private"
        }
    }
}

public struct EventVisibility: Codable, Equatable, Hashable {
    public var type: EventVisibilityType
    public var groupIds: [String]
    
    public init(type: EventVisibilityType = .private, groupIds: [String] = []) {
        self.type = type
        self.groupIds = groupIds
    }
}

public struct CalendarEvent: Identifiable, Codable, Equatable, Hashable {
    public var id: String
    public var title: String
    public var startDate: Date
    public var endDate: Date
    public var isAllDay: Bool
    public var location: String?
    public var notes: String?
    public var calendarType: CalendarType
    public var visibility: EventVisibility
    public var createdBy: String
    public var colorHex: String
    public var source: String?
    public var createdAt: Date
    public var updatedAt: Date
    
    public init(
        id: String = UUID().uuidString,
        title: String,
        startDate: Date,
        endDate: Date,
        isAllDay: Bool = false,
        location: String? = nil,
        notes: String? = nil,
        calendarType: CalendarType = .joe,
        visibility: EventVisibility = EventVisibility(type: .private),
        createdBy: String = "",
        colorHex: String = AppColor.GroupPastel.sage.hexString,
        source: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.startDate = startDate
        self.endDate = endDate
        self.isAllDay = isAllDay
        self.location = location
        self.notes = notes
        self.calendarType = calendarType
        self.visibility = visibility
        self.createdBy = createdBy
        self.colorHex = colorHex
        self.source = source
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
    
    public var color: Color {
        Color(hexString: colorHex)
    }
}
