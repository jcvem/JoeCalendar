//
//  DiscoverService.swift
//  JoeCalendar
//
//  Created for JoeCalendar Phase 3 Discover & Monetization.
//  Manages curated Local Calendars (next-30-days sliding window),
//  free-tier follow limits (unlocked by Pro), targeted promotions
//  with frequency capping (ad-free for Pro), and Firestore synchronization.
//

import Foundation
import Combine
import SwiftUI

#if canImport(FirebaseFirestore)
import FirebaseFirestore
#endif

#if canImport(FirebaseFunctions)
import FirebaseFunctions
#endif

@MainActor
public final class DiscoverService: ObservableObject {
    public static let shared = DiscoverService()
    
    // Constant limits
    public static let freeTierFollowLimit = 2
    public static let maxPromoCardsPerSession = 2
    
    // MARK: - Published State
    @Published public private(set) var localCalendars: [LocalCalendar] = []
    @Published public var followedCalendarIds: Set<String> = []
    @Published public private(set) var promotions: [Promotion] = []
    @Published public private(set) var localEventsMap: [String: [CalendarEvent]] = [:] // calendarId -> events
    
    // Filtering & View state
    @Published public var selectedRegion: String = "all"
    @Published public var selectedCategory: String? = nil
    @Published public var searchQuery: String = ""
    @Published public var isLoading: Bool = false
    @Published public var showPaywallForLimit: Bool = false
    
    // Persistence Keys
    private let followedCalendarsKey = "joecalendar_followed_local_calendars_v1"
    private let localCalendarsCacheKey = "joecalendar_local_calendars_cache_v1"
    private let localEventsMapCacheKey = "joecalendar_local_events_map_cache_v1"
    
    // Firestore REST configuration (joecalendar-e8327)
    private let projectId = "joecalendar-e8327"
    private var firestoreBaseURL: String {
        "https://firestore.googleapis.com/v1/projects/\(projectId)/databases/(default)/documents"
    }
    
    private let subscriptionService = SubscriptionService.shared
    
    private init() {
        loadPersistedData()
        if localCalendars.isEmpty {
            seedCuratedLocalCalendars()
        }
        if localEventsMap.isEmpty {
            seedLocalEvents()
        }
        
        Task {
            await refreshAll()
        }
    }
    
    // MARK: - Computed Properties
    
    /// Returns promotions respecting the ad-free subscription and session frequency cap (max 1–2)
    public var activePromotions: [Promotion] {
        guard !subscriptionService.isAdFree else {
            return []
        }
        
        var list = promotions
        if selectedRegion != "all" {
            list = list.filter { promo in
                if promo.targeting.regions.isEmpty { return true }
                return promo.targeting.regions.contains(selectedRegion)
            }
        }
        return Array(list.prefix(Self.maxPromoCardsPerSession))
    }
    
    /// Filtered local calendars according to search, region, and category
    public var filteredLocalCalendars: [LocalCalendar] {
        localCalendars.filter { cal in
            // Region filter
            if selectedRegion != "all" && cal.region.lowercased() != selectedRegion.lowercased() {
                return false
            }
            
            // Category filter
            if let cat = selectedCategory, !cat.isEmpty && cal.category.lowercased() != cat.lowercased() {
                return false
            }
            
            // Search query
            let cleanQuery = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if !cleanQuery.isEmpty {
                let matchTitle = cal.title.lowercased().contains(cleanQuery)
                let matchDesc = cal.description.lowercased().contains(cleanQuery)
                let matchTags = cal.tags.contains { $0.lowercased().contains(cleanQuery) }
                let matchRegion = cal.region.lowercased().contains(cleanQuery)
                return matchTitle || matchDesc || matchTags || matchRegion
            }
            
            return true
        }
    }
    
    /// Curated calendars followed by the user
    public var followedCalendars: [LocalCalendar] {
        localCalendars.filter { followedCalendarIds.contains($0.id) }
    }
    
    /// Next-30-days events feed aggregated from all followed local calendars
    public var upcomingFollowedEvents: [CalendarEvent] {
        let now = Date()
        let startOfDay = Calendar.current.startOfDay(for: now)
        let thirtyDaysLater = Calendar.current.date(byAdding: .day, value: 30, to: now) ?? now
        
        var combined: [CalendarEvent] = []
        for calId in followedCalendarIds {
            if let events = localEventsMap[calId] {
                let valid = events.filter { $0.startDate >= startOfDay && $0.startDate <= thirtyDaysLater }
                combined.append(contentsOf: valid)
            }
        }
        
        return combined.sorted { $0.startDate < $1.startDate }
    }
    
    /// Checks whether user can follow another local calendar
    public var canFollowMoreCalendars: Bool {
        if subscriptionService.isAdFree {
            return true
        }
        return followedCalendarIds.count < Self.freeTierFollowLimit
    }
    
    // MARK: - Follow / Unfollow Actions
    
    /// Toggles follow status for a local calendar; returns true if successful, false if paywall limit reached
    @discardableResult
    public func toggleFollow(for calendar: LocalCalendar) -> Bool {
        if followedCalendarIds.contains(calendar.id) {
            followedCalendarIds.remove(calendar.id)
            updateSubscriberCount(calendarId: calendar.id, delta: -1)
            persistData()
            syncFollowedToUser()
            return true
        } else {
            if canFollowMoreCalendars {
                followedCalendarIds.insert(calendar.id)
                updateSubscriberCount(calendarId: calendar.id, delta: 1)
                persistData()
                syncFollowedToUser()
                return true
            } else {
                // Free tier limit reached: trigger paywall
                self.showPaywallForLimit = true
                return false
            }
        }
    }
    
    public func isFollowing(_ calendarId: String) -> Bool {
        followedCalendarIds.contains(calendarId)
    }
    
    private func updateSubscriberCount(calendarId: String, delta: Int) {
        if let idx = localCalendars.firstIndex(where: { $0.id == calendarId }) {
            var cal = localCalendars[idx]
            cal.subscriberCount = max(0, cal.subscriberCount + delta)
            cal.updatedAt = Date()
            localCalendars[idx] = cal
        }
    }
    
    // MARK: - Refresh & Remote Sync
       public func refreshAll() async {
        self.isLoading = true
        defer { self.isLoading = false }
        
        await fetchTargetedPromotions()
        await fetchCuratedCalendarsFromFirestore()
        await fetchCuratedEventsFromFirestore()
    }
    
    /// Calls the live `targetPromotionsForUser` Cloud Function or Firestore collection
    public func fetchTargetedPromotions() async {
        guard !subscriptionService.isAdFree else {
            self.promotions = []
            return
        }
        
        let userRegion = selectedRegion == "all" ? "Tokyo" : selectedRegion
        
        // 1. Attempt Cloud Function callable via Firebase SDK
        #if canImport(FirebaseFunctions)
        if let functions = FirebaseService.shared.functions {
            do {
                let callable = functions.httpsCallable("targetPromotionsForUser")
                let result = try await callable.call([
                    "region": userRegion,
                    "interests": ["Coffee", "Art", "Culture", "Music", "Food"]
                ])
                
                if let data = result.data as? [String: Any] {
                    if let isAdFree = data["isAdFree"] as? Bool, isAdFree {
                        self.promotions = []
                        return
                    }
                    
                    if let promoList = data["promotions"] as? [[String: Any]], !promoList.isEmpty {
                        var parsed: [Promotion] = []
                        for item in promoList {
                            let id = item["id"] as? String ?? UUID().uuidString
                            let sponsor = item["sponsorName"] as? String ?? "Sponsored Partner"
                            let title = item["title"] as? String ?? "Featured Event"
                            let subtitle = item["subtitle"] as? String
                            let desc = item["description"] as? String ?? ""
                            let banner = item["bannerImageUrl"] as? String
                            let action = item["actionUrl"] as? String
                            
                            let promo = Promotion(
                                id: id,
                                sponsorName: sponsor,
                                title: title,
                                subtitle: subtitle,
                                description: desc,
                                bannerImageUrl: banner,
                                actionUrl: action,
                                targeting: PromotionTargeting(regions: [userRegion])
                            )
                            parsed.append(promo)
                        }
                        self.promotions = parsed
                        return
                    }
                }
            } catch {
                print("DiscoverService: Cloud Functions targetPromotionsForUser call failed: \(error.localizedDescription)")
            }
        }
        #endif
        
        // 2. Attempt Cloud Function callable via REST endpoint
        let endpoint = "https://asia-east1-\(projectId).cloudfunctions.net/targetPromotionsForUser"
        if let url = URL(string: endpoint) {
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            
            let payload: [String: Any] = [
                "data": [
                    "region": userRegion,
                    "interests": ["Coffee", "Art", "Culture", "Music", "Food"]
                ]
            ]
            request.httpBody = try? JSONSerialization.data(withJSONObject: payload)
            
            if let (data, response) = try? await URLSession.shared.data(for: request),
               let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let result = json["result"] as? [String: Any] {
                
                if let isAdFree = result["isAdFree"] as? Bool, isAdFree {
                    self.promotions = []
                    return
                }
                
                if let promoList = result["promotions"] as? [[String: Any]], !promoList.isEmpty {
                    // Successfully fetched promos from Cloud Function
                    var parsed: [Promotion] = []
                    for item in promoList {
                        let id = item["id"] as? String ?? UUID().uuidString
                        let sponsor = item["sponsorName"] as? String ?? "Sponsored Partner"
                        let title = item["title"] as? String ?? "Featured Event"
                        let desc = item["description"] as? String ?? ""
                        let actionUrl = item["actionUrl"] as? String
                        let subtitle = item["subtitle"] as? String
                        
                        let promo = Promotion(
                            id: id,
                            sponsorName: sponsor,
                            title: title,
                            subtitle: subtitle,
                            description: desc,
                            bannerImageUrl: nil,
                            actionUrl: actionUrl,
                            targeting: PromotionTargeting(regions: [userRegion])
                        )
                        parsed.append(promo)
                    }
                    self.promotions = parsed
                    return
                }
            }
        }
        
        // 3. If remote has no items or offline, fallback to curated high-quality promotions
        seedDefaultPromotions()
    }
    
    /// Queries Firestore `localCalendars` collection
    private func fetchCuratedCalendarsFromFirestore() async {
        #if canImport(FirebaseFirestore)
        if let firestore = FirebaseService.shared.db {
            do {
                let snapshot = try await firestore.collection("localCalendars").whereField("isCurated", isEqualTo: true).getDocuments()
                var remoteCalendars: [LocalCalendar] = []
                for doc in snapshot.documents {
                    let data = doc.data()
                    let id = doc.documentID
                    let title = data["title"] as? String ?? "Curated Calendar"
                    let description = data["description"] as? String ?? ""
                    let region = data["region"] as? String ?? "Tokyo"
                    let category = data["category"] as? String ?? "Culture"
                    let colorHex = data["colorHex"] as? String ?? AppColor.GroupPastel.sage.hexString
                    let tags = data["tags"] as? [String] ?? []
                    let count = data["subscriberCount"] as? Int ?? 0
                    let isCurated = data["isCurated"] as? Bool ?? true
                    let coverImageUrl = data["coverImageUrl"] as? String
                    
                    let windowStart = (data["windowStartDate"] as? Timestamp)?.dateValue() ?? Date()
                    let windowEnd = (data["windowEndDate"] as? Timestamp)?.dateValue() ?? (Calendar.current.date(byAdding: .day, value: 30, to: Date()) ?? Date())
                    let createdAt = (data["createdAt"] as? Timestamp)?.dateValue() ?? Date()
                    let updatedAt = (data["updatedAt"] as? Timestamp)?.dateValue() ?? Date()
                    
                    let cal = LocalCalendar(
                        id: id,
                        title: title,
                        description: description,
                        coverImageUrl: coverImageUrl,
                        region: region,
                        category: category,
                        colorHex: colorHex,
                        tags: tags,
                        windowStartDate: windowStart,
                        windowEndDate: windowEnd,
                        subscriberCount: count,
                        isCurated: isCurated,
                        createdAt: createdAt,
                        updatedAt: updatedAt
                    )
                    remoteCalendars.append(cal)
                }
                
                if !remoteCalendars.isEmpty {
                    self.localCalendars = remoteCalendars
                    persistData()
                    return
                }
            } catch {
                print("DiscoverService: Firestore localCalendars query error: \(error.localizedDescription)")
            }
        }
        #endif
        
        guard let url = URL(string: "\(firestoreBaseURL)/localCalendars") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        
        if let (data, response) = try? await URLSession.shared.data(for: request),
           let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let documents = json["documents"] as? [[String: Any]], !documents.isEmpty {
            
            var remoteCalendars: [LocalCalendar] = []
            for doc in documents {
                guard let name = doc["name"] as? String,
                      let fields = doc["fields"] as? [String: Any] else { continue }
                
                let id = name.components(separatedBy: "/").last ?? UUID().uuidString
                let title = (fields["title"] as? [String: Any])?["stringValue"] as? String ?? "Curated Calendar"
                let description = (fields["description"] as? [String: Any])?["stringValue"] as? String ?? ""
                let region = (fields["region"] as? [String: Any])?["stringValue"] as? String ?? "Tokyo"
                let category = (fields["category"] as? [String: Any])?["stringValue"] as? String ?? "Culture"
                let colorHex = (fields["colorHex"] as? [String: Any])?["stringValue"] as? String ?? AppColor.GroupPastel.sage.hexString
                let count = Int((fields["subscriberCount"] as? [String: Any])?["integerValue"] as? String ?? "0") ?? 0
                let isCurated = (fields["isCurated"] as? [String: Any])?["booleanValue"] as? Bool ?? true
                let coverImageUrl = (fields["coverImageUrl"] as? [String: Any])?["stringValue"] as? String
                
                let windowStart = parseIsoDate((fields["windowStartDate"] as? [String: Any])?["timestampValue"] as? String) ?? Date()
                let windowEnd = parseIsoDate((fields["windowEndDate"] as? [String: Any])?["timestampValue"] as? String) ?? (Calendar.current.date(byAdding: .day, value: 30, to: Date()) ?? Date())
                let createdAt = parseIsoDate((fields["createdAt"] as? [String: Any])?["timestampValue"] as? String) ?? Date()
                let updatedAt = parseIsoDate((fields["updatedAt"] as? [String: Any])?["timestampValue"] as? String) ?? Date()
                
                let cal = LocalCalendar(
                    id: id,
                    title: title,
                    description: description,
                    coverImageUrl: coverImageUrl,
                    region: region,
                    category: category,
                    colorHex: colorHex,
                    windowStartDate: windowStart,
                    windowEndDate: windowEnd,
                    subscriberCount: count,
                    isCurated: isCurated,
                    createdAt: createdAt,
                    updatedAt: updatedAt
                )
                remoteCalendars.append(cal)
            }
            
            if !remoteCalendars.isEmpty {
                self.localCalendars = remoteCalendars
                persistData()
            }
        }
    }
    
    /// Queries Firestore `localCalendarEvents` collection and populates `localEventsMap`
    private func fetchCuratedEventsFromFirestore() async {
        #if canImport(FirebaseFirestore)
        if let firestore = FirebaseService.shared.db {
            do {
                let snapshot = try await firestore.collection("localCalendarEvents").getDocuments()
                var remoteEventsMap: [String: [CalendarEvent]] = [:]
                
                for doc in snapshot.documents {
                    let data = doc.data()
                    let id = doc.documentID
                    let title = data["title"] as? String ?? ""
                    guard !title.isEmpty else { continue }
                    
                    let startDate = (data["startDate"] as? Timestamp)?.dateValue() ?? Date()
                    let endDate = (data["endDate"] as? Timestamp)?.dateValue() ?? startDate
                    let isAllDay = data["isAllDay"] as? Bool ?? false
                    let location = data["location"] as? String
                    let notes = data["notes"] as? String
                    let rawCalType = data["calendarType"] as? String ?? "local"
                    let calendarType = CalendarType(rawValue: rawCalType) ?? .local
                    let externalId = data["externalId"] as? String ?? id
                    let externalCalendarId = data["externalCalendarId"] as? String ?? ""
                    let source = data["source"] as? String ?? "culture.tw"
                    let colorHex = data["colorHex"] as? String ?? AppColor.GroupPastel.sage.hexString
                    let createdBy = data["createdBy"] as? String ?? "system_curator"
                    let rawSync = data["syncStatus"] as? String ?? "synced"
                    let syncStatus = SyncStatus(rawValue: rawSync) ?? .synced
                    let rawRecurrence = data["recurrence"] as? String ?? "none"
                    let recurrence = EventRecurrence(rawValue: rawRecurrence) ?? .none
                    let coverImageUrl = data["coverImageUrl"] as? String
                    let eventUrl = data["eventUrl"] as? String
                    let createdAt = (data["createdAt"] as? Timestamp)?.dateValue() ?? Date()
                    let updatedAt = (data["updatedAt"] as? Timestamp)?.dateValue() ?? Date()
                    
                    var visibility = EventVisibility(type: .public)
                    if let visData = data["visibility"] as? [String: Any],
                       let visTypeStr = visData["type"] as? String,
                       let visType = EventVisibilityType(rawValue: visTypeStr) {
                        let groupIds = visData["groupIds"] as? [String] ?? []
                        visibility = EventVisibility(type: visType, groupIds: groupIds)
                    }
                    
                    let event = CalendarEvent(
                        id: id,
                        title: title,
                        startDate: startDate,
                        endDate: endDate,
                        isAllDay: isAllDay,
                        location: location,
                        notes: notes,
                        calendarType: calendarType,
                        visibility: visibility,
                        recurrence: recurrence,
                        createdBy: createdBy,
                        colorHex: colorHex,
                        source: source,
                        externalId: externalId,
                        externalCalendarId: externalCalendarId,
                        syncStatus: syncStatus,
                        coverImageUrl: coverImageUrl,
                        eventUrl: eventUrl,
                        createdAt: createdAt,
                        updatedAt: updatedAt
                    )
                    
                    let key = !externalCalendarId.isEmpty ? externalCalendarId : (source.isEmpty ? id : source)
                    remoteEventsMap[key, default: []].append(event)
                }
                
                if !remoteEventsMap.isEmpty {
                    for (calId, evs) in remoteEventsMap {
                        self.localEventsMap[calId] = evs.sorted { $0.startDate < $1.startDate }
                    }
                    persistData()
                    return
                }
            } catch {
                print("DiscoverService: Firestore localCalendarEvents query error: \(error.localizedDescription)")
            }
        }
        #endif
        
        // REST Fallback for localCalendarEvents
        guard let url = URL(string: "\(firestoreBaseURL)/localCalendarEvents") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        
        if let (data, response) = try? await URLSession.shared.data(for: request),
           let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let documents = json["documents"] as? [[String: Any]], !documents.isEmpty {
            
            var remoteEventsMap: [String: [CalendarEvent]] = [:]
            for doc in documents {
                guard let name = doc["name"] as? String,
                      let fields = doc["fields"] as? [String: Any] else { continue }
                
                let id = name.components(separatedBy: "/").last ?? UUID().uuidString
                let title = (fields["title"] as? [String: Any])?["stringValue"] as? String ?? ""
                guard !title.isEmpty else { continue }
                
                let startDateStr = (fields["startDate"] as? [String: Any])?["timestampValue"] as? String
                let endDateStr = (fields["endDate"] as? [String: Any])?["timestampValue"] as? String
                let startDate = parseIsoDate(startDateStr) ?? Date()
                let endDate = parseIsoDate(endDateStr) ?? startDate
                
                let isAllDay = (fields["isAllDay"] as? [String: Any])?["booleanValue"] as? Bool ?? false
                let location = (fields["location"] as? [String: Any])?["stringValue"] as? String
                let notes = (fields["notes"] as? [String: Any])?["stringValue"] as? String
                let rawCalType = (fields["calendarType"] as? [String: Any])?["stringValue"] as? String ?? "local"
                let calendarType = CalendarType(rawValue: rawCalType) ?? .local
                let externalId = (fields["externalId"] as? [String: Any])?["stringValue"] as? String ?? id
                let externalCalendarId = (fields["externalCalendarId"] as? [String: Any])?["stringValue"] as? String ?? ""
                let source = (fields["source"] as? [String: Any])?["stringValue"] as? String ?? "culture.tw"
                let colorHex = (fields["colorHex"] as? [String: Any])?["stringValue"] as? String ?? AppColor.GroupPastel.sage.hexString
                let createdBy = (fields["createdBy"] as? [String: Any])?["stringValue"] as? String ?? "system_curator"
                let rawSync = (fields["syncStatus"] as? [String: Any])?["stringValue"] as? String ?? "synced"
                let syncStatus = SyncStatus(rawValue: rawSync) ?? .synced
                let rawRecurrence = (fields["recurrence"] as? [String: Any])?["stringValue"] as? String ?? "none"
                let recurrence = EventRecurrence(rawValue: rawRecurrence) ?? .none
                let coverImageUrl = (fields["coverImageUrl"] as? [String: Any])?["stringValue"] as? String
                let eventUrl = (fields["eventUrl"] as? [String: Any])?["stringValue"] as? String
                let createdAt = parseIsoDate((fields["createdAt"] as? [String: Any])?["timestampValue"] as? String) ?? Date()
                let updatedAt = parseIsoDate((fields["updatedAt"] as? [String: Any])?["timestampValue"] as? String) ?? Date()
                
                let event = CalendarEvent(
                    id: id,
                    title: title,
                    startDate: startDate,
                    endDate: endDate,
                    isAllDay: isAllDay,
                    location: location,
                    notes: notes,
                    calendarType: calendarType,
                    visibility: EventVisibility(type: .public),
                    recurrence: recurrence,
                    createdBy: createdBy,
                    colorHex: colorHex,
                    source: source,
                    externalId: externalId,
                    externalCalendarId: externalCalendarId,
                    syncStatus: syncStatus,
                    coverImageUrl: coverImageUrl,
                    eventUrl: eventUrl,
                    createdAt: createdAt,
                    updatedAt: updatedAt
                )
                
                let key = !externalCalendarId.isEmpty ? externalCalendarId : (source.isEmpty ? id : source)
                remoteEventsMap[key, default: []].append(event)
            }
            
            if !remoteEventsMap.isEmpty {
                for (calId, evs) in remoteEventsMap {
                    self.localEventsMap[calId] = evs.sorted { $0.startDate < $1.startDate }
                }
                persistData()
            }
        }
    }
    
    private func parseIsoDate(_ string: String?) -> Date? {
        guard let string = string, !string.isEmpty else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: string) {
            return date
        }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: string)
    }
    
    // MARK: - Local Calendar Events Query
    
    public func events(for calendarId: String) -> [CalendarEvent] {
        let events = localEventsMap[calendarId] ?? []
        let now = Calendar.current.startOfDay(for: Date())
        let windowEnd: Date
        if let cal = localCalendars.first(where: { $0.id == calendarId }) {
            windowEnd = max(cal.windowEndDate, Calendar.current.date(byAdding: .day, value: 30, to: now) ?? now)
        } else {
            windowEnd = Calendar.current.date(byAdding: .day, value: 30, to: now) ?? now
        }
        return events
            .filter { $0.startDate >= now && $0.startDate <= windowEnd }
            .sorted { $0.startDate < $1.startDate }
    }
    
    // MARK: - Persistence & User Sync
    
    private func syncFollowedToUser() {
        var user = FriendService.shared.currentUser
        user.followedLocalCalendarIds = Array(followedCalendarIds)
        
        #if canImport(FirebaseFirestore)
        if FirebaseService.shared.isConfigured {
            Task {
                try? await FirebaseService.shared.updateUserFollowedCalendars(uid: user.id, followedCalendarIds: user.followedLocalCalendarIds)
            }
            return
        }
        #endif
        
        // Sync to Firestore users/{uid} via REST
        guard let url = URL(string: "\(firestoreBaseURL)/users/\(user.id)?updateMask.fieldPaths=followedLocalCalendarIds") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let fields: [String: Any] = [
            "followedLocalCalendarIds": [
                "arrayValue": [
                    "values": user.followedLocalCalendarIds.map { ["stringValue": $0] }
                ]
            ]
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["fields": fields])
        
        Task {
            _ = try? await URLSession.shared.data(for: request)
        }
    }
    
    private func persistData() {
        let followedArray = Array(followedCalendarIds)
        UserDefaults.standard.set(followedArray, forKey: followedCalendarsKey)
        
        if let encoded = try? JSONEncoder().encode(localCalendars) {
            UserDefaults.standard.set(encoded, forKey: localCalendarsCacheKey)
        }
        
        if let encodedEvents = try? JSONEncoder().encode(localEventsMap) {
            UserDefaults.standard.set(encodedEvents, forKey: localEventsMapCacheKey)
        }
    }
    
    private func loadPersistedData() {
        if let savedFollowed = UserDefaults.standard.stringArray(forKey: followedCalendarsKey) {
            self.followedCalendarIds = Set(savedFollowed)
        }
        if let data = UserDefaults.standard.data(forKey: localCalendarsCacheKey),
           let decoded = try? JSONDecoder().decode([LocalCalendar].self, from: data) {
            self.localCalendars = decoded
        }
        if let eventsData = UserDefaults.standard.data(forKey: localEventsMapCacheKey),
           let decodedEvents = try? JSONDecoder().decode([String: [CalendarEvent]].self, from: eventsData) {
            self.localEventsMap = decodedEvents
        }
    }
    
    // MARK: - Curated Seeding (Japanese Calm Aesthetic & 30-Day Sliding Window)
    
    private func seedCuratedLocalCalendars() {
        let now = Date()
        let cal = Calendar.current
        let thirtyDaysLater = cal.date(byAdding: .day, value: 30, to: now) ?? now
        
        let calTaipei = LocalCalendar(
            id: "taipei_qinzi",
            title: "臺北 親子活動",
            description: "臺北市嚴選親子活動、兒童劇團、手作體驗與展演年曆。",
            region: "Taipei",
            category: "親子活動",
            colorHex: "#2D5D72",
            tags: ["親子", "Taipei", "family"],
            windowStartDate: now,
            windowEndDate: thirtyDaysLater,
            subscriberCount: 3120,
            isCurated: true
        )
        
        let calNewTaipei = LocalCalendar(
            id: "newtaipei_qinzi",
            title: "新北 親子活動",
            description: "新北市嚴選親子活動、藝文體驗、兒童劇場與圖書館活動年曆。",
            region: "New Taipei",
            category: "親子活動",
            colorHex: "#2D5D72",
            tags: ["親子", "New Taipei", "family"],
            windowStartDate: now,
            windowEndDate: thirtyDaysLater,
            subscriberCount: 2280,
            isCurated: true
        )
        
        let cal1 = LocalCalendar(
            id: "local_tokyo_coffee",
            title: "Tokyo Artisan Coffee & Bakeries",
            description: "Editorially curated popups, seasonal roasts, and pastry dates across Shibuya, Daikanyama & Nakameguro.",
            region: "Tokyo",
            category: "Coffee & Food",
            colorHex: AppColor.GroupPastel.yamabuki.hexString,
            tags: ["Coffee", "Gourmet", "Weekend"],
            windowStartDate: now,
            windowEndDate: thirtyDaysLater,
            subscriberCount: 1840
        )
        
        let cal2 = LocalCalendar(
            id: "local_kyoto_crafts",
            title: "Kyoto Weekend Flea Markets & Crafts",
            description: "Traditional temple fairs, artisan pottery, antique kimonos, and tea ceremonies for the next 30 days.",
            region: "Kyoto",
            category: "Markets & Crafts",
            colorHex: AppColor.GroupPastel.matcha.hexString,
            tags: ["Crafts", "Antiques", "Culture", "Temple"],
            windowStartDate: now,
            windowEndDate: thirtyDaysLater,
            subscriberCount: 1210
        )
        
        let cal3 = LocalCalendar(
            id: "local_taipei_indie",
            title: "Taipei Indie Music & Livehouse",
            description: "Underground gigs, acoustic sessions, and showcase dates in Gongguan, Ximending & Zhongshan.",
            region: "Taipei",
            category: "Music & Live",
            colorHex: AppColor.GroupPastel.akane.hexString,
            tags: ["Music", "Live", "Night", "Indie"],
            windowStartDate: now,
            windowEndDate: thirtyDaysLater,
            subscriberCount: 2430
        )
        
        let cal4 = LocalCalendar(
            id: "local_osaka_food",
            title: "Osaka Night Market & Street Food",
            description: "Late-night alley popups, seasonal tasting events, and street food festivals across Namba & Umeda.",
            region: "Osaka",
            category: "Nightlife & Food",
            colorHex: AppColor.GroupPastel.sakura.hexString,
            tags: ["Food", "Street", "Night", "Festival"],
            windowStartDate: now,
            windowEndDate: thirtyDaysLater,
            subscriberCount: 1560
        )
        
        let cal5 = LocalCalendar(
            id: "local_tokyo_art",
            title: "Tokyo Architecture & Modern Art Walk",
            description: "Contemporary galleries, architectural showcases, and museum exhibitions open for the 30-day window.",
            region: "Tokyo",
            category: "Art & Design",
            colorHex: AppColor.GroupPastel.mist.hexString,
            tags: ["Art", "Design", "Museum", "Exhibition"],
            windowStartDate: now,
            windowEndDate: thirtyDaysLater,
            subscriberCount: 970
        )
        
        self.localCalendars = [calTaipei, calNewTaipei, cal1, cal2, cal3, cal4, cal5]
        
        // Seed next-30-days events for each calendar
        seedLocalEvents()
        
        // Default follow 1 calendar for pleasant initial state
        if followedCalendarIds.isEmpty {
            followedCalendarIds = ["taipei_qinzi", "local_tokyo_coffee"]
        }
        
        persistData()
    }
    
    private func seedLocalEvents() {
        let today = Date()
        let cal = Calendar.current
        
        // Taipei Family events
        let tpeQinzi1 = CalendarEvent(
            id: "ev_tpe_qinzi_1",
            title: "【親子活動】小手拉大手 偶戲狂想曲",
            startDate: cal.date(byAdding: .day, value: 3, to: cal.date(bySettingHour: 10, minute: 30, second: 0, of: today)!)!,
            endDate: cal.date(byAdding: .day, value: 3, to: cal.date(bySettingHour: 12, minute: 0, second: 0, of: today)!)!,
            location: "臺北表演藝術中心 球劇場",
            notes: "適合3-8歲幼兒及家庭共同參與之偶戲互動體驗。",
            calendarType: .local,
            visibility: EventVisibility(type: .public),
            createdBy: "system_curator",
            colorHex: "#2D5D72",
            source: "culture.tw",
            externalId: "culture.tw_tpe_qinzi_1",
            externalCalendarId: "taipei_qinzi"
        )
        let tpeQinzi2 = CalendarEvent(
            id: "ev_tpe_qinzi_2",
            title: "繪本立體世界：森林動物探險 手作工作坊",
            startDate: cal.date(byAdding: .day, value: 8, to: cal.date(bySettingHour: 14, minute: 0, second: 0, of: today)!)!,
            endDate: cal.date(byAdding: .day, value: 8, to: cal.date(bySettingHour: 16, minute: 30, second: 0, of: today)!)!,
            location: "臺北市藝文推廣處 文山劇場",
            notes: "名額有限，適合親子共創立體紙雕城堡。",
            calendarType: .local,
            visibility: EventVisibility(type: .public),
            createdBy: "system_curator",
            colorHex: "#2D5D72",
            source: "culture.tw",
            externalId: "culture.tw_tpe_qinzi_2",
            externalCalendarId: "taipei_qinzi"
        )
        let tpeQinzi3 = CalendarEvent(
            id: "ev_tpe_qinzi_3",
            title: "草地野餐故事派對",
            startDate: cal.date(byAdding: .day, value: 16, to: cal.date(bySettingHour: 15, minute: 0, second: 0, of: today)!)!,
            endDate: cal.date(byAdding: .day, value: 16, to: cal.date(bySettingHour: 17, minute: 30, second: 0, of: today)!)!,
            location: "大安森林公園 音樂台草坪",
            notes: "免費草地說故事互動，歡迎自備野餐墊。",
            calendarType: .local,
            visibility: EventVisibility(type: .public),
            createdBy: "system_curator",
            colorHex: "#2D5D72",
            source: "travel.taipei",
            externalId: "travel.taipei_tpe_qinzi_3",
            externalCalendarId: "taipei_qinzi"
        )
        
        // New Taipei Family events
        let ntpcQinzi1 = CalendarEvent(
            id: "ev_ntpc_qinzi_1",
            title: "親子音樂劇《阿甯咕的爸鼻不見了？》",
            startDate: cal.date(byAdding: .day, value: 5, to: cal.date(bySettingHour: 14, minute: 30, second: 0, of: today)!)!,
            endDate: cal.date(byAdding: .day, value: 5, to: cal.date(bySettingHour: 16, minute: 0, second: 0, of: today)!)!,
            location: "新北市藝文中心演藝廳 - 新北市板橋區莊敬路62號",
            notes: "改編自知名繪本動畫，溫馨歡樂的親子劇場盛會。",
            calendarType: .local,
            visibility: EventVisibility(type: .public),
            createdBy: "system_curator",
            colorHex: "#2D5D72",
            source: "culture.tw",
            externalId: "culture.tw_ntpc_qinzi_1",
            externalCalendarId: "newtaipei_qinzi"
        )
        let ntpcQinzi2 = CalendarEvent(
            id: "ev_ntpc_qinzi_2",
            title: "2026新莊有好戲：掌中劇團親子體驗《食夢傳說》",
            startDate: cal.date(byAdding: .day, value: 12, to: cal.date(bySettingHour: 14, minute: 30, second: 0, of: today)!)!,
            endDate: cal.date(byAdding: .day, value: 12, to: cal.date(bySettingHour: 15, minute: 30, second: 0, of: today)!)!,
            location: "新莊文化藝術中心演藝廳 - 新北市新莊區中平路133號",
            notes: "傳統布袋戲現代改編，適合全家大小一同賞析。",
            calendarType: .local,
            visibility: EventVisibility(type: .public),
            createdBy: "system_curator",
            colorHex: "#2D5D72",
            source: "culture.tw",
            externalId: "culture.tw_ntpc_qinzi_2",
            externalCalendarId: "newtaipei_qinzi"
        )
        let ntpcQinzi3 = CalendarEvent(
            id: "ev_ntpc_qinzi_3",
            title: "【新北市立圖書館總館】週末親子繪本說故事",
            startDate: cal.date(byAdding: .day, value: 20, to: cal.date(bySettingHour: 10, minute: 0, second: 0, of: today)!)!,
            endDate: cal.date(byAdding: .day, value: 20, to: cal.date(bySettingHour: 11, minute: 30, second: 0, of: today)!)!,
            location: "新北市立圖書館總館 3F 兒童閱覽區 - 新北市板橋區貴興路139號",
            notes: "說故事老師生動演繹經典繪本與手作互動。",
            calendarType: .local,
            visibility: EventVisibility(type: .public),
            createdBy: "system_curator",
            colorHex: "#2D5D72",
            source: "culture.tw",
            externalId: "culture.tw_ntpc_qinzi_3",
            externalCalendarId: "newtaipei_qinzi"
        )
        
        // Tokyo Coffee events
        let coffee1 = CalendarEvent(
            id: "ev_tokyo_coffee_1",
            title: "Daikanyama Spring Roaster Tasting",
            startDate: cal.date(byAdding: .day, value: 2, to: cal.date(bySettingHour: 10, minute: 0, second: 0, of: today)!)!,
            endDate: cal.date(byAdding: .day, value: 2, to: cal.date(bySettingHour: 17, minute: 0, second: 0, of: today)!)!,
            location: "Hillside Terrace Block F, Daikanyama",
            notes: "Single-origin filter flights from 8 guest Japanese micro-roasters.",
            calendarType: .local,
            visibility: EventVisibility(type: .public),
            createdBy: "curator_tokyo",
            colorHex: AppColor.GroupPastel.yamabuki.hexString,
            source: "local_tokyo_coffee"
        )
        let coffee2 = CalendarEvent(
            id: "ev_tokyo_coffee_2",
            title: "Nakameguro Natural Wine & Sourdough Night",
            startDate: cal.date(byAdding: .day, value: 6, to: cal.date(bySettingHour: 18, minute: 0, second: 0, of: today)!)!,
            endDate: cal.date(byAdding: .day, value: 6, to: cal.date(bySettingHour: 22, minute: 0, second: 0, of: today)!)!,
            location: "Meguro Riverbank Studio",
            notes: "Limited evening pairing with guest French bakers.",
            calendarType: .local,
            visibility: EventVisibility(type: .public),
            createdBy: "curator_tokyo",
            colorHex: AppColor.GroupPastel.yamabuki.hexString,
            source: "local_tokyo_coffee"
        )
        let coffee3 = CalendarEvent(
            id: "ev_tokyo_coffee_3",
            title: "Shibuya Pour-Over Masterclass",
            startDate: cal.date(byAdding: .day, value: 11, to: cal.date(bySettingHour: 14, minute: 0, second: 0, of: today)!)!,
            endDate: cal.date(byAdding: .day, value: 11, to: cal.date(bySettingHour: 16, minute: 0, second: 0, of: today)!)!,
            location: "Kissa Shibuya 2F",
            notes: "Water temperature and extraction ratio workshop.",
            calendarType: .local,
            visibility: EventVisibility(type: .public),
            createdBy: "curator_tokyo",
            colorHex: AppColor.GroupPastel.yamabuki.hexString,
            source: "local_tokyo_coffee"
        )
        
        // Kyoto Crafts events
        let craft1 = CalendarEvent(
            id: "ev_kyoto_craft_1",
            title: "Kitano Tenmangu Shrine Antique Market",
            startDate: cal.date(byAdding: .day, value: 3, to: cal.date(bySettingHour: 7, minute: 0, second: 0, of: today)!)!,
            endDate: cal.date(byAdding: .day, value: 3, to: cal.date(bySettingHour: 16, minute: 0, second: 0, of: today)!)!,
            location: "Kitano Tenmangu Shrine Grounds, Kyoto",
            notes: "Monthly Tenjin-san fair: woodblock prints, ceramics, and antique kimonos.",
            calendarType: .local,
            visibility: EventVisibility(type: .public),
            createdBy: "curator_kyoto",
            colorHex: AppColor.GroupPastel.matcha.hexString,
            source: "local_kyoto_crafts"
        )
        let craft2 = CalendarEvent(
            id: "ev_kyoto_craft_2",
            title: "Higashiyama Ceramic Studio Open Day",
            startDate: cal.date(byAdding: .day, value: 8, to: cal.date(bySettingHour: 11, minute: 0, second: 0, of: today)!)!,
            endDate: cal.date(byAdding: .day, value: 8, to: cal.date(bySettingHour: 18, minute: 0, second: 0, of: today)!)!,
            location: "Gojo-zaka Kilns, Kyoto",
            notes: "Meet local potters and try hand-wheel clay shaping.",
            calendarType: .local,
            visibility: EventVisibility(type: .public),
            createdBy: "curator_kyoto",
            colorHex: AppColor.GroupPastel.matcha.hexString,
            source: "local_kyoto_crafts"
        )
        
        // Taipei Indie Music events
        let indie1 = CalendarEvent(
            id: "ev_taipei_indie_1",
            title: "The Wall Acoustic Showcase",
            startDate: cal.date(byAdding: .day, value: 4, to: cal.date(bySettingHour: 20, minute: 0, second: 0, of: today)!)!,
            endDate: cal.date(byAdding: .day, value: 4, to: cal.date(bySettingHour: 23, minute: 0, second: 0, of: today)!)!,
            location: "The Wall Livehouse, Gongguan, Taipei",
            notes: "Taiwanese indie folk singer-songwriter double bill.",
            calendarType: .local,
            visibility: EventVisibility(type: .public),
            createdBy: "curator_taipei",
            colorHex: AppColor.GroupPastel.akane.hexString,
            source: "local_taipei_indie"
        )
        let indie2 = CalendarEvent(
            id: "ev_taipei_indie_2",
            title: "Zhongshan Vinyl & Synth Popup",
            startDate: cal.date(byAdding: .day, value: 9, to: cal.date(bySettingHour: 15, minute: 0, second: 0, of: today)!)!,
            endDate: cal.date(byAdding: .day, value: 9, to: cal.date(bySettingHour: 21, minute: 0, second: 0, of: today)!)!,
            location: "Chifeng Street Loft, Taipei",
            notes: "City pop listening session & indie record trading.",
            calendarType: .local,
            visibility: EventVisibility(type: .public),
            createdBy: "curator_taipei",
            colorHex: AppColor.GroupPastel.akane.hexString,
            source: "local_taipei_indie"
        )
        
        // Osaka food events
        let osaka1 = CalendarEvent(
            id: "ev_osaka_food_1",
            title: "Umeda Night Street Food & Craft Beer",
            startDate: cal.date(byAdding: .day, value: 5, to: cal.date(bySettingHour: 17, minute: 30, second: 0, of: today)!)!,
            endDate: cal.date(byAdding: .day, value: 5, to: cal.date(bySettingHour: 22, minute: 30, second: 0, of: today)!)!,
            location: "Grand Front Plaza, Osaka",
            notes: "Kansai seasonal street bites and local craft breweries.",
            calendarType: .local,
            visibility: EventVisibility(type: .public),
            createdBy: "curator_osaka",
            colorHex: AppColor.GroupPastel.sakura.hexString,
            source: "local_osaka_food"
        )
        
        // Tokyo Art events
        let art1 = CalendarEvent(
            id: "ev_tokyo_art_1",
            title: "Mori Art Center Night Gallery Walk",
            startDate: cal.date(byAdding: .day, value: 7, to: cal.date(bySettingHour: 18, minute: 0, second: 0, of: today)!)!,
            endDate: cal.date(byAdding: .day, value: 7, to: cal.date(bySettingHour: 21, minute: 30, second: 0, of: today)!)!,
            location: "Roppongi Hills 53F, Tokyo",
            notes: "Special after-hours access with panoramic city lights.",
            calendarType: .local,
            visibility: EventVisibility(type: .public),
            createdBy: "curator_tokyo",
            colorHex: AppColor.GroupPastel.mist.hexString,
            source: "local_tokyo_art"
        )
        
        self.localEventsMap = [
            "taipei_qinzi": [tpeQinzi1, tpeQinzi2, tpeQinzi3],
            "newtaipei_qinzi": [ntpcQinzi1, ntpcQinzi2, ntpcQinzi3],
            "local_tokyo_coffee": [coffee1, coffee2, coffee3],
            "local_kyoto_crafts": [craft1, craft2],
            "local_taipei_indie": [indie1, indie2],
            "local_osaka_food": [osaka1],
            "local_tokyo_art": [art1]
        ]
    }
    
    private func seedDefaultPromotions() {
        let today = Date()
        let cal = Calendar.current
        
        let promo1 = Promotion(
            id: "promo_coffee_fest",
            sponsorName: "Blue Bottle Japan",
            title: "Single Origin Spring Tasting Fair",
            subtitle: "Complimentary pour-over tasting with code #JOECAL",
            description: "Experience rare seasonal micro-lots freshly roasted in Kiyosumi Shirakawa. Exclusive priority bookings for JoeCalendar members.",
            bannerImageUrl: nil,
            actionUrl: "https://store.bluebottlecoffee.jp",
            targeting: PromotionTargeting(regions: ["Tokyo", "Kyoto"], interests: ["Coffee", "Gourmet"]),
            startDate: today,
            endDate: cal.date(byAdding: .day, value: 20, to: today) ?? today,
            isPaid: true
        )
        
        let promo2 = Promotion(
            id: "promo_art_fair",
            sponsorName: "Tokyo Contemporary Art Circle",
            title: "Roppongi Art Night 2026 Special Pass",
            subtitle: "20% off exhibition tickets",
            description: "Discover all-night art installations, light design, and performances across Roppongi. Tap to claim early bird digital pass.",
            bannerImageUrl: nil,
            actionUrl: "https://www.roppongiartnight.com",
            targeting: PromotionTargeting(regions: ["Tokyo", "Kyoto", "Taipei", "New Taipei", "Osaka"], interests: ["Art", "Culture"]),
            startDate: today,
            endDate: cal.date(byAdding: .day, value: 25, to: today) ?? today,
            isPaid: true
        )
        
        self.promotions = [promo1, promo2]
    }
}

