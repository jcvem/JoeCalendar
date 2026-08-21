//
//  FriendService.swift
//  JoeCalendar
//
//  Created for JoeCalendar Phase 2 Social Groups.
//  Encapsulates Firestore-backed friendship lifecycle (search, request, accept, decline),
//  group management (create, edit, delete, member add/remove), and local persistence.
//

import Foundation
import Combine
import SwiftUI

#if canImport(FirebaseFirestore)
import FirebaseFirestore
#endif

#if canImport(FirebaseAuth)
import FirebaseAuth
#endif

public struct FriendRequestItem: Identifiable, Equatable {
    public var id: String { friendship.id }
    public var friendship: Friendship
    public var otherUser: JoeUser
    public var isIncoming: Bool
    
    public init(friendship: Friendship, otherUser: JoeUser, isIncoming: Bool) {
        self.friendship = friendship
        self.otherUser = otherUser
        self.isIncoming = isIncoming
    }
}

@MainActor
public final class FriendService: ObservableObject {
    public static let shared = FriendService()
    
    // MARK: - Published State
    @Published public private(set) var currentUser: JoeUser
    @Published public private(set) var friends: [JoeUser] = []
    @Published public private(set) var pendingIncomingRequests: [FriendRequestItem] = []
    @Published public private(set) var pendingOutgoingRequests: [FriendRequestItem] = []
    @Published public private(set) var userGroups: [FriendGroup] = []
    @Published public private(set) var searchResults: [JoeUser] = []
    @Published public var isSearching: Bool = false
    @Published public var isLoading: Bool = false
    @Published public var errorMessage: String? = nil
    
    // Directory of searchable users for offline/demo & fast lookup
    @Published private var userDirectory: [JoeUser] = []
    @Published private var allFriendships: [Friendship] = []
    
    // Persistence Keys
    private let currentUserKey = "joecalendar_current_user_v2"
    private let userDirectoryKey = "joecalendar_user_directory_v2"
    private let friendshipsKey = "joecalendar_friendships_v2"
    private let groupsKey = "joecalendar_groups_v2"
    
    // Firestore REST configuration (joecalendar-e8327)
    private let projectId = "joecalendar-e8327"
    private var firestoreBaseURL: String {
        "https://firestore.googleapis.com/v1/projects/\(projectId)/databases/(default)/documents"
    }
    
    private init() {
        // 1. Initialize default user
        let defaultUser = JoeUser(
            id: "user_me_001",
            displayName: "Joe Tanaka",
            email: "joe@joecalendar.app",
            avatarUrl: nil,
            joeId: "joe_tanaka",
            locale: LocaleManager.shared.effectiveLanguageCode,
            isAdFree: false,
            friendIds: ["user_kenji_002", "user_sarah_003", "user_daiki_004", "user_mei_005"],
            groupIds: ["workout_friends", "family_circle", "design_guild"]
        )
        self.currentUser = defaultUser
        
        // 2. Load stored data or seed defaults
        loadPersistedData()
        if userDirectory.isEmpty {
            seedDefaultData()
        } else {
            refreshDerivedLists()
        }
    }
    
    // MARK: - Current User Synchronization
    
    public var currentAuthUid: String {
        #if canImport(FirebaseAuth)
        if let authUid = Auth.auth().currentUser?.uid {
            return authUid
        }
        #endif
        return currentUser.id
    }
    
    public func updateCurrentUser(_ user: JoeUser) {
        let oldId = self.currentUser.id
        self.currentUser = user
        
        // If transitioning from default stub "user_me_001" to real Firebase Auth UID, migrate local records
        if oldId != user.id {
            for i in 0..<userGroups.count {
                if userGroups[i].ownerUid == oldId {
                    userGroups[i].ownerUid = user.id
                }
                if let idx = userGroups[i].memberUids.firstIndex(of: oldId) {
                    userGroups[i].memberUids[idx] = user.id
                }
            }
            for i in 0..<allFriendships.count {
                if allFriendships[i].uidA == oldId {
                    allFriendships[i].uidA = user.id
                }
                if allFriendships[i].uidB == oldId {
                    allFriendships[i].uidB = user.id
                }
            }
        }
        
        refreshDerivedLists()
        persistData()
        Task {
            try? await pushUserToFirestore(user)
        }
    }
    
    // MARK: - User Search
    
    /// Searches users by JoeCalendar ID (@username), display name, or email address
    public func searchUsers(query: String) async -> [JoeUser] {
        let cleanQuery = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !cleanQuery.isEmpty else {
            self.searchResults = []
            return []
        }
        
        self.isSearching = true
        defer { self.isSearching = false }
        
        let queryNormalized = cleanQuery.hasPrefix("@") ? String(cleanQuery.dropFirst()) : cleanQuery
        
        // 1. Search in local directory
        let localMatches = userDirectory.filter { user in
            guard user.id != currentUser.id else { return false }
            let matchJoeId = user.joeId?.lowercased().contains(queryNormalized) ?? false
            let matchName = user.displayName.lowercased().contains(queryNormalized)
            let matchEmail = user.email?.lowercased().contains(queryNormalized) ?? false
            return matchJoeId || matchName || matchEmail
        }
        
        self.searchResults = localMatches
        
        // 2. Optionally query Firestore REST API
        Task {
            if let remoteMatches = try? await queryUsersFromFirestore(query: queryNormalized) {
                let merged = Array(Set(localMatches + remoteMatches))
                self.searchResults = merged.filter { $0.id != self.currentUser.id }
            }
        }
        
        return localMatches
    }
    
    // MARK: - Friendship Lifecycle (Send, Accept, Decline, Remove)
    
    /// Sends a friend request to a target user
    public func sendFriendRequest(to targetUser: JoeUser) async throws {
        let myUid = currentAuthUid
        guard targetUser.id != myUid else { return }
        
        // Check if already friends or request already exists
        if currentUser.friendIds.contains(targetUser.id) {
            return
        }
        if allFriendships.contains(where: {
            ($0.uidA == myUid && $0.uidB == targetUser.id) ||
            ($0.uidA == targetUser.id && $0.uidB == myUid)
        }) {
            return
        }
        
        let newFriendship = Friendship(
            id: "friendship_\(UUID().uuidString)",
            uidA: myUid,
            uidB: targetUser.id,
            status: .pending,
            createdAt: Date()
        )
        
        allFriendships.append(newFriendship)
        refreshDerivedLists()
        persistData()
        
        // Sync to Firestore
        Task {
            do {
                try await pushFriendshipToFirestore(newFriendship)
            } catch {
                print("FriendService: Failed to push friendship: \(error.localizedDescription)")
            }
        }
    }
    
    /// Accepts an incoming friend request
    public func acceptFriendRequest(friendshipId: String) async throws {
        guard let index = allFriendships.firstIndex(where: { $0.id == friendshipId }) else { return }
        var friendship = allFriendships[index]
        friendship.status = .accepted
        allFriendships[index] = friendship
        
        let friendUid = friendship.uidA == currentUser.id ? friendship.uidB : friendship.uidA
        if !currentUser.friendIds.contains(friendUid) {
            currentUser.friendIds.append(friendUid)
        }
        
        // Also update other user in directory
        if let friendIndex = userDirectory.firstIndex(where: { $0.id == friendUid }) {
            var friendUser = userDirectory[friendIndex]
            if !friendUser.friendIds.contains(currentUser.id) {
                friendUser.friendIds.append(currentUser.id)
                userDirectory[friendIndex] = friendUser
            }
        }
        
        refreshDerivedLists()
        persistData()
        
        // Sync to Firestore
        Task {
            try? await pushFriendshipToFirestore(friendship)
            try? await pushUserToFirestore(currentUser)
        }
    }
    
    /// Declines or cancels a friend request
    public func declineFriendRequest(friendshipId: String) async throws {
        allFriendships.removeAll { $0.id == friendshipId }
        refreshDerivedLists()
        persistData()
        
        // Sync to Firestore
        Task {
            try? await deleteFriendshipFromFirestore(friendshipId: friendshipId)
        }
    }
    
    /// Removes an existing friend
    public func removeFriend(friendUid: String) async throws {
        currentUser.friendIds.removeAll { $0 == friendUid }
        allFriendships.removeAll {
            ($0.uidA == currentUser.id && $0.uidB == friendUid) ||
            ($0.uidA == friendUid && $0.uidB == currentUser.id)
        }
        
        if let friendIndex = userDirectory.firstIndex(where: { $0.id == friendUid }) {
            var friendUser = userDirectory[friendIndex]
            friendUser.friendIds.removeAll { $0 == currentUser.id }
            userDirectory[friendIndex] = friendUser
        }
        
        refreshDerivedLists()
        persistData()
        
        Task {
            try? await pushUserToFirestore(currentUser)
        }
    }
    
    public func friendshipStatus(with userId: String) -> FriendshipStatus? {
        if currentUser.friendIds.contains(userId) {
            return .accepted
        }
        if let friendship = allFriendships.first(where: {
            ($0.uidA == currentUser.id && $0.uidB == userId) ||
            ($0.uidA == userId && $0.uidB == currentUser.id)
        }) {
            return friendship.status
        }
        return nil
    }
    
    // MARK: - Group Management (Create, Edit, Delete, Members)
    
    /// Creates a new privacy group
    @discardableResult
    public func createGroup(
        name: String,
        colorHex: String = AppColor.GroupPastel.sage.hexString,
        iconName: String = "person.2.fill",
        memberUids: [String] = []
    ) async throws -> FriendGroup {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalName = trimmedName.isEmpty ? "New Group" : trimmedName
        
        let myUid = currentAuthUid
        // Ensure owner is included in group members
        var members = memberUids
        if !members.contains(myUid) {
            members.append(myUid)
        }
        
        let newGroup = FriendGroup(
            id: "group_\(UUID().uuidString)",
            name: finalName,
            ownerUid: myUid,
            memberUids: members,
            colorHex: colorHex,
            iconName: iconName,
            defaultPrivacy: .group,
            createdAt: Date(),
            updatedAt: Date()
        )
        
        userGroups.append(newGroup)
        if !currentUser.groupIds.contains(newGroup.id) {
            currentUser.groupIds.append(newGroup.id)
        }
        
        // Update groupIds on members in local directory
        for memberUid in members {
            if let idx = userDirectory.firstIndex(where: { $0.id == memberUid }) {
                if !userDirectory[idx].groupIds.contains(newGroup.id) {
                    userDirectory[idx].groupIds.append(newGroup.id)
                }
            }
        }
        
        persistData()
        
        // Sync to Firestore
        Task {
            try? await pushGroupToFirestore(newGroup)
            try? await pushUserToFirestore(currentUser)
        }
        
        return newGroup
    }
    
    /// Updates an existing group's details
    public func updateGroup(_ group: FriendGroup) async throws {
        var mutableGroup = group
        mutableGroup.updatedAt = Date()
        
        if let index = userGroups.firstIndex(where: { $0.id == group.id }) {
            userGroups[index] = mutableGroup
            persistData()
            
            Task {
                try? await pushGroupToFirestore(mutableGroup)
            }
        }
    }
    
    /// Deletes a group (Owner only)
    public func deleteGroup(groupId: String) async throws {
        userGroups.removeAll { $0.id == groupId }
        currentUser.groupIds.removeAll { $0 == groupId }
        
        // Remove from members
        for idx in 0..<userDirectory.count {
            userDirectory[idx].groupIds.removeAll { $0 == groupId }
        }
        
        persistData()
        
        Task {
            try? await deleteGroupFromFirestore(groupId: groupId)
            try? await pushUserToFirestore(currentUser)
        }
    }
    
    /// Adds member UIDs to a group
    public func addMembers(_ uids: [String], to groupId: String) async throws {
        guard let index = userGroups.firstIndex(where: { $0.id == groupId }) else { return }
        var group = userGroups[index]
        for uid in uids {
            if !group.memberUids.contains(uid) {
                group.memberUids.append(uid)
            }
            if let uIdx = userDirectory.firstIndex(where: { $0.id == uid }) {
                if !userDirectory[uIdx].groupIds.contains(groupId) {
                    userDirectory[uIdx].groupIds.append(groupId)
                }
            }
        }
        group.updatedAt = Date()
        userGroups[index] = group
        persistData()
        
        Task {
            try? await pushGroupToFirestore(group)
        }
    }
    
    /// Removes a member UID from a group
    public func removeMember(_ uid: String, from groupId: String) async throws {
        guard let index = userGroups.firstIndex(where: { $0.id == groupId }) else { return }
        var group = userGroups[index]
        group.memberUids.removeAll { $0 == uid }
        group.updatedAt = Date()
        userGroups[index] = group
        
        if uid == currentUser.id {
            currentUser.groupIds.removeAll { $0 == groupId }
            userGroups.removeAll { $0.id == groupId }
        }
        
        if let uIdx = userDirectory.firstIndex(where: { $0.id == uid }) {
            userDirectory[uIdx].groupIds.removeAll { $0 == groupId }
        }
        
        persistData()
        
        Task {
            try? await pushGroupToFirestore(group)
            try? await pushUserToFirestore(currentUser)
        }
    }
    
    public func user(for uid: String) -> JoeUser? {
        if uid == currentUser.id {
            return currentUser
        }
        return userDirectory.first(where: { $0.id == uid })
    }
    
    // MARK: - Internal Refresh Helpers
    
    private func refreshDerivedLists() {
        // Friends
        self.friends = currentUser.friendIds.compactMap { friendId in
            userDirectory.first(where: { $0.id == friendId })
        }
        
        // Incoming Requests: uidB is currentUser, status is pending
        self.pendingIncomingRequests = allFriendships
            .filter { $0.uidB == currentUser.id && $0.status == .pending }
            .compactMap { friendship in
                guard let sender = userDirectory.first(where: { $0.id == friendship.uidA }) else { return nil }
                return FriendRequestItem(friendship: friendship, otherUser: sender, isIncoming: true)
            }
        
        // Outgoing Requests: uidA is currentUser, status is pending
        self.pendingOutgoingRequests = allFriendships
            .filter { $0.uidA == currentUser.id && $0.status == .pending }
            .compactMap { friendship in
                guard let recipient = userDirectory.first(where: { $0.id == friendship.uidB }) else { return nil }
                return FriendRequestItem(friendship: friendship, otherUser: recipient, isIncoming: false)
            }
    }
    
    // MARK: - Persistence
    
    private func persistData() {
        if let userData = try? JSONEncoder().encode(currentUser) {
            UserDefaults.standard.set(userData, forKey: currentUserKey)
        }
        if let dirData = try? JSONEncoder().encode(userDirectory) {
            UserDefaults.standard.set(dirData, forKey: userDirectoryKey)
        }
        if let fData = try? JSONEncoder().encode(allFriendships) {
            UserDefaults.standard.set(fData, forKey: friendshipsKey)
        }
        if let gData = try? JSONEncoder().encode(userGroups) {
            UserDefaults.standard.set(gData, forKey: groupsKey)
        }
    }
    
    private func loadPersistedData() {
        if let userData = UserDefaults.standard.data(forKey: currentUserKey),
           let user = try? JSONDecoder().decode(JoeUser.self, from: userData) {
            self.currentUser = user
        }
        if let dirData = UserDefaults.standard.data(forKey: userDirectoryKey),
           let dir = try? JSONDecoder().decode([JoeUser].self, from: dirData) {
            self.userDirectory = dir
        }
        if let fData = UserDefaults.standard.data(forKey: friendshipsKey),
           let friendships = try? JSONDecoder().decode([Friendship].self, from: fData) {
            self.allFriendships = friendships
        }
        if let gData = UserDefaults.standard.data(forKey: groupsKey),
           let groups = try? JSONDecoder().decode([FriendGroup].self, from: gData) {
            self.userGroups = groups
        }
    }
    
    // MARK: - Demo Seeding (Japanese-Calm Pre-populated Data)
    
    private func seedDefaultData() {
        let friend1 = JoeUser(
            id: "user_kenji_002",
            displayName: "Kenji Sato",
            email: "kenji@runner.jp",
            joeId: "kenji_runner",
            locale: "ja",
            friendIds: [currentUser.id],
            groupIds: ["workout_friends"]
        )
        
        let friend2 = JoeUser(
            id: "user_sarah_003",
            displayName: "Sarah Williams",
            email: "sarah@design.io",
            joeId: "sarah_w",
            locale: "en",
            friendIds: [currentUser.id],
            groupIds: ["family_circle", "design_guild"]
        )
        
        let friend3 = JoeUser(
            id: "user_daiki_004",
            displayName: "Daiki Takahashi",
            email: "daiki@pickleball.jp",
            joeId: "daiki_t",
            locale: "ja",
            friendIds: [currentUser.id],
            groupIds: ["workout_friends"]
        )
        
        let friend4 = JoeUser(
            id: "user_mei_005",
            displayName: "Mei Chen",
            email: "mei@studio.tw",
            joeId: "mei_chen",
            locale: "zh-Hant",
            friendIds: [currentUser.id],
            groupIds: ["family_circle"]
        )
        
        let incomingRequester = JoeUser(
            id: "user_yuto_006",
            displayName: "Yuto Suzuki",
            email: "yuto@dev.jp",
            joeId: "yuto_s",
            locale: "ja",
            friendIds: [],
            groupIds: ["design_guild"]
        )
        
        let searchable1 = JoeUser(
            id: "user_emily_007",
            displayName: "Emily Zhang",
            email: "emily@tokyo.io",
            joeId: "emily_z",
            locale: "en",
            friendIds: [],
            groupIds: []
        )
        
        let searchable2 = JoeUser(
            id: "user_ren_008",
            displayName: "Ren Kobayashi",
            email: "ren@tech.jp",
            joeId: "ren_k",
            locale: "ja",
            friendIds: [],
            groupIds: []
        )
        
        self.userDirectory = [friend1, friend2, friend3, friend4, incomingRequester, searchable1, searchable2]
        
        // Friendships
        let fs1 = Friendship(id: "fs_1", uidA: currentUser.id, uidB: friend1.id, status: .accepted)
        let fs2 = Friendship(id: "fs_2", uidA: currentUser.id, uidB: friend2.id, status: .accepted)
        let fs3 = Friendship(id: "fs_3", uidA: currentUser.id, uidB: friend3.id, status: .accepted)
        let fs4 = Friendship(id: "fs_4", uidA: currentUser.id, uidB: friend4.id, status: .accepted)
        let fsPending = Friendship(id: "fs_pending_1", uidA: incomingRequester.id, uidB: currentUser.id, status: .pending)
        
        self.allFriendships = [fs1, fs2, fs3, fs4, fsPending]
        
        // Groups
        let group1 = FriendGroup(
            id: "workout_friends",
            name: "Pickleball & Workout",
            ownerUid: currentUser.id,
            memberUids: [currentUser.id, friend1.id, friend3.id],
            colorHex: AppColor.GroupPastel.sage.hexString,
            iconName: "figure.run",
            defaultPrivacy: .group
        )
        
        let group2 = FriendGroup(
            id: "family_circle",
            name: "Family Circle",
            ownerUid: currentUser.id,
            memberUids: [currentUser.id, friend2.id, friend4.id],
            colorHex: AppColor.GroupPastel.sakura.hexString,
            iconName: "house.fill",
            defaultPrivacy: .group
        )
        
        let group3 = FriendGroup(
            id: "design_guild",
            name: "Design & Dev Guild",
            ownerUid: currentUser.id,
            memberUids: [currentUser.id, friend2.id, incomingRequester.id],
            colorHex: AppColor.GroupPastel.mist.hexString,
            iconName: "briefcase.fill",
            defaultPrivacy: .group
        )
        
        self.userGroups = [group1, group2, group3]
        
        refreshDerivedLists()
        persistData()
    }
    
    // MARK: - Firestore Integration (Real SDK + REST Mirror)
    
    public func pushUserToFirestore(_ user: JoeUser) async throws {
        #if canImport(FirebaseFirestore)
        if let firestore = FirebaseService.shared.db {
            let docRef = firestore.collection("users").document(user.id)
            let data: [String: Any] = [
                "id": user.id,
                "displayName": user.displayName,
                "email": user.email ?? "",
                "avatarUrl": user.avatarUrl ?? "",
                "joeId": user.joeId ?? "",
                "locale": user.locale,
                "isAdFree": user.isAdFree,
                "friendIds": user.friendIds,
                "groupIds": user.groupIds,
                "linkedCalendars": user.linkedCalendars,
                "followedLocalCalendarIds": user.followedLocalCalendarIds,
                "createdAt": Timestamp(date: user.createdAt),
                "updatedAt": Timestamp(date: user.updatedAt)
            ]
            do {
                try await docRef.setData(data, merge: true)
                print("FriendService: Successfully pushed user \(user.id) to Firestore!")
            } catch {
                print("FriendService: Error pushing user to Firestore: \(error.localizedDescription)")
                throw error
            }
            return
        }
        #endif
        
        guard let url = URL(string: "\(firestoreBaseURL)/users/\(user.id)") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let fields: [String: Any] = [
            "displayName": ["stringValue": user.displayName],
            "email": ["stringValue": user.email ?? ""],
            "joeId": ["stringValue": user.joeId ?? ""],
            "locale": ["stringValue": user.locale],
            "isAdFree": ["booleanValue": user.isAdFree],
            "friendIds": ["arrayValue": ["values": user.friendIds.map { ["stringValue": $0] }]],
            "groupIds": ["arrayValue": ["values": user.groupIds.map { ["stringValue": $0] }]]
        ]
        
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["fields": fields])
        _ = try? await URLSession.shared.data(for: request)
    }
    
    public func pushGroupToFirestore(_ group: FriendGroup) async throws {
        #if canImport(FirebaseFirestore)
        if let firestore = FirebaseService.shared.db {
            let docRef = firestore.collection("groups").document(group.id)
            let data: [String: Any] = [
                "id": group.id,
                "name": group.name,
                "ownerUid": group.ownerUid,
                "memberUids": group.memberUids,
                "colorHex": group.colorHex,
                "iconName": group.iconName,
                "defaultPrivacy": group.defaultPrivacy.rawValue,
                "createdAt": Timestamp(date: group.createdAt),
                "updatedAt": Timestamp(date: group.updatedAt)
            ]
            do {
                try await docRef.setData(data, merge: true)
                print("FriendService: Successfully pushed group \(group.id) to Firestore!")
            } catch {
                print("FriendService: Error pushing group to Firestore: \(error.localizedDescription)")
                throw error
            }
            return
        }
        #endif
        
        guard let url = URL(string: "\(firestoreBaseURL)/groups/\(group.id)") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let fields: [String: Any] = [
            "name": ["stringValue": group.name],
            "ownerUid": ["stringValue": group.ownerUid],
            "memberUids": ["arrayValue": ["values": group.memberUids.map { ["stringValue": $0] }]],
            "colorHex": ["stringValue": group.colorHex],
            "iconName": ["stringValue": group.iconName],
            "defaultPrivacy": ["stringValue": group.defaultPrivacy.rawValue]
        ]
        
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["fields": fields])
        _ = try? await URLSession.shared.data(for: request)
    }
    
    public func deleteGroupFromFirestore(groupId: String) async throws {
        #if canImport(FirebaseFirestore)
        if let firestore = FirebaseService.shared.db {
            try await firestore.collection("groups").document(groupId).delete()
            return
        }
        #endif
        
        guard let url = URL(string: "\(firestoreBaseURL)/groups/\(groupId)") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        _ = try? await URLSession.shared.data(for: request)
    }
    
    public func pushFriendshipToFirestore(_ friendship: Friendship) async throws {
        #if canImport(FirebaseFirestore)
        if let firestore = FirebaseService.shared.db {
            let docRef = firestore.collection("friendships").document(friendship.id)
            let data: [String: Any] = [
                "id": friendship.id,
                "uidA": friendship.uidA,
                "uidB": friendship.uidB,
                "status": friendship.status.rawValue,
                "createdAt": Timestamp(date: friendship.createdAt)
            ]
            do {
                try await docRef.setData(data, merge: true)
                print("FriendService: Successfully pushed friendship \(friendship.id) to Firestore (uidA: \(friendship.uidA), uidB: \(friendship.uidB))!")
            } catch {
                #if canImport(FirebaseAuth)
                let authUid = Auth.auth().currentUser?.uid ?? "nil"
                #else
                let authUid = "no-auth"
                #endif
                print("FriendService: Error pushing friendship to Firestore: \(error.localizedDescription) [Current Auth UID: \(authUid), uidA: \(friendship.uidA)]")
                throw error
            }
            return
        }
        #endif
        
        guard let url = URL(string: "\(firestoreBaseURL)/friendships/\(friendship.id)") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let fields: [String: Any] = [
            "uidA": ["stringValue": friendship.uidA],
            "uidB": ["stringValue": friendship.uidB],
            "status": ["stringValue": friendship.status.rawValue]
        ]
        
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["fields": fields])
        _ = try? await URLSession.shared.data(for: request)
    }
    
    public func deleteFriendshipFromFirestore(friendshipId: String) async throws {
        #if canImport(FirebaseFirestore)
        if let firestore = FirebaseService.shared.db {
            try await firestore.collection("friendships").document(friendshipId).delete()
            return
        }
        #endif
        
        guard let url = URL(string: "\(firestoreBaseURL)/friendships/\(friendshipId)") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        _ = try? await URLSession.shared.data(for: request)
    }
    
    public func queryUsersFromFirestore(query: String) async throws -> [JoeUser] {
        #if canImport(FirebaseFirestore)
        if let firestore = FirebaseService.shared.db {
            let snapshot = try await firestore.collection("users").limit(to: 20).getDocuments()
            var results: [JoeUser] = []
            for doc in snapshot.documents {
                let user = FirebaseService.shared.parseJoeUser(id: doc.documentID, data: doc.data())
                let matchJoeId = user.joeId?.lowercased().contains(query) ?? false
                let matchName = user.displayName.lowercased().contains(query)
                let matchEmail = user.email?.lowercased().contains(query) ?? false
                if matchJoeId || matchName || matchEmail {
                    results.append(user)
                }
            }
            return results
        }
        #endif
        
        // Run structured query via REST
        guard let url = URL(string: "https://firestore.googleapis.com/v1/projects/\(projectId)/databases/(default)/documents:runQuery") else { return [] }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let queryBody: [String: Any] = [
            "structuredQuery": [
                "from": [["collectionId": "users"]],
                "limit": 20
            ]
        ]
        
        request.httpBody = try? JSONSerialization.data(withJSONObject: queryBody)
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode),
              let jsonArray = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return []
        }
        
        var results: [JoeUser] = []
        for item in jsonArray {
            guard let doc = item["document"] as? [String: Any],
                  let name = doc["name"] as? String,
                  let fields = doc["fields"] as? [String: Any] else {
                continue
            }
            
            let uid = name.components(separatedBy: "/").last ?? UUID().uuidString
            let displayName = (fields["displayName"] as? [String: Any])?["stringValue"] as? String ?? "User"
            let email = (fields["email"] as? [String: Any])?["stringValue"] as? String
            let joeId = (fields["joeId"] as? [String: Any])?["stringValue"] as? String
            let locale = (fields["locale"] as? [String: Any])?["stringValue"] as? String ?? "en"
            
            let user = JoeUser(id: uid, displayName: displayName, email: email, joeId: joeId, locale: locale)
            results.append(user)
        }
        
        return results
    }
}

