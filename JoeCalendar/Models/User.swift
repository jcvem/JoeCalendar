//
//  User.swift
//  JoeCalendar
//
//  Created for JoeCalendar Phase 0 Foundation.
//  Firestore collection: `users/{uid}`
//

import Foundation

public struct JoeUser: Identifiable, Codable, Equatable {
    public var id: String // uid
    public var displayName: String
    public var email: String?
    public var avatarUrl: String?
    public var joeId: String?
    public var locale: String
    public var isAdFree: Bool
    public var friendIds: [String]
    public var groupIds: [String]
    public var linkedCalendars: [String]
    public var createdAt: Date
    public var updatedAt: Date
    
    public init(
        id: String,
        displayName: String,
        email: String? = nil,
        avatarUrl: String? = nil,
        joeId: String? = nil,
        locale: String = "en",
        isAdFree: Bool = false,
        friendIds: [String] = [],
        groupIds: [String] = [],
        linkedCalendars: [String] = [],
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.displayName = displayName
        self.email = email
        self.avatarUrl = avatarUrl
        self.joeId = joeId
        self.locale = locale
        self.isAdFree = isAdFree
        self.friendIds = friendIds
        self.groupIds = groupIds
        self.linkedCalendars = linkedCalendars
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
