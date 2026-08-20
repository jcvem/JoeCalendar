//
//  FriendGroup.swift
//  JoeCalendar
//
//  Created for JoeCalendar Phase 0 Foundation.
//  Firestore collection: `groups/{groupId}`
//

import Foundation
import SwiftUI

public struct FriendGroup: Identifiable, Codable, Equatable, Hashable {
    public var id: String
    public var name: String
    public var ownerUid: String
    public var memberUids: [String]
    public var colorHex: String
    public var iconName: String
    public var defaultPrivacy: EventVisibilityType
    public var createdAt: Date
    public var updatedAt: Date
    
    public init(
        id: String = UUID().uuidString,
        name: String,
        ownerUid: String,
        memberUids: [String] = [],
        colorHex: String = AppColor.GroupPastel.sage.hexString,
        iconName: String = "person.2.fill",
        defaultPrivacy: EventVisibilityType = .group,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.ownerUid = ownerUid
        self.memberUids = memberUids
        self.colorHex = colorHex
        self.iconName = iconName
        self.defaultPrivacy = defaultPrivacy
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
    
    public var color: Color {
        Color(hexString: colorHex)
    }
}

public enum FriendshipStatus: String, Codable {
    case pending = "pending"
    case accepted = "accepted"
    case blocked = "blocked"
}

public struct Friendship: Identifiable, Codable, Equatable, Hashable {
    public var id: String
    public var uidA: String
    public var uidB: String
    public var status: FriendshipStatus
    public var createdAt: Date
    
    public init(
        id: String = UUID().uuidString,
        uidA: String,
        uidB: String,
        status: FriendshipStatus = .pending,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.uidA = uidA
        self.uidB = uidB
        self.status = status
        self.createdAt = createdAt
    }
}
