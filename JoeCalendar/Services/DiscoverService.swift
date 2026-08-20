//
//  DiscoverService.swift
//  JoeCalendar
//
//  Created for JoeCalendar Phase 3 Discover & Monetization.
//  Manages curated Local Calendars (next-14-days sliding window),
//  free-tier follow limits (unlocked by Pro), targeted promotions
//  with frequency capping (ad-free for Pro), and Firestore synchronization.
//

import Foundation
import Combine
import SwiftUI

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
    
    /// Next-14-days events feed aggregated from all followed local calendars
    public var upcomingFollowedEvents: [CalendarEvent] {
        let now = Date()
        let twoWeeksLater = Calendar.current.date(byAdding: .day, value: 14, to: now) ?? now
        
        var combined: [CalendarEvent] = []
        for calId in followedCalendarIds {
            if let events = localEventsMap[calId] {
                let valid = events.filter { $0.startDate >= Calendar.current.startOfDay(for: now) && $0.startDate <= twoWeeksLater }
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
    }
    
    /// Calls the live `targetPromotionsForUser` Cloud Function or Firestore collection
    public func fetchTargetedPromotions() async {
        guard !subscriptionService.isAdFree else {
            self.promotions = []
            return
        }
        
        let userRegion = selectedRegion == "all" ? "Tokyo" : selectedRegion
        
        // 1. Attempt Cloud Function callable via REST endpoint
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
        
        // 2. If remote has no items or offline, fallback to curated high-quality promotions
        seedDefaultPromotions()
    }
    
    /// Queries Firestore `localCalendars` collection
    private func fetchCuratedCalendarsFromFirestore() async {
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
                
                let cal = LocalCalendar(
                    id: id,
                    title: title,
                    description: description,
                    region: region,
                    category: category,
                    colorHex: colorHex,
                    subscriberCount: count
                )
                remoteCalendars.append(cal)
            }
            
            if !remoteCalendars.isEmpty {
                self.localCalendars = remoteCalendars
                persistData()
            }
        }
    }
    
    // MARK: - Local Calendar Events Query
    
    public func events(for calendarId: String) -> [CalendarEvent] {
        return localEventsMap[calendarId] ?? []
    }
    
    // MARK: - Persistence & User Sync
    
    private func syncFollowedToUser() {
        var user = FriendService.shared.currentUser
        user.followedLocalCalendarIds = Array(followedCalendarIds)
        
        // Sync to Firestore users/{uid}
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
    }
    
    private func loadPersistedData() {
        if let savedFollowed = UserDefaults.standard.stringArray(forKey: followedCalendarsKey) {
            self.followedCalendarIds = Set(savedFollowed)
        }
        if let data = UserDefaults.standard.data(forKey: localCalendarsCacheKey),
           let decoded = try? JSONDecoder().decode([LocalCalendar].self, from: data) {
            self.localCalendars = decoded
        }
    }
    
    // MARK: - Curated Seeding (Japanese Calm Aesthetic & 14-Day Sliding Window)
    
    private func seedCuratedLocalCalendars() {
        let cal1 = LocalCalendar(
            id: "local_tokyo_coffee",
            title: "Tokyo Artisan Coffee & Bakeries",
            description: "Editorially curated popups, seasonal roasts, and pastry dates across Shibuya, Daikanyama & Nakameguro.",
            region: "Tokyo",
            category: "Coffee & Food",
            colorHex: AppColor.GroupPastel.yamabuki.hexString,
            tags: ["Coffee", "Gourmet", "Weekend"],
            subscriberCount: 1840
        )
        
        let cal2 = LocalCalendar(
            id: "local_kyoto_crafts",
            title: "Kyoto Weekend Flea Markets & Crafts",
            description: "Traditional temple fairs, artisan pottery, antique kimonos, and tea ceremonies for the next 2 weeks.",
            region: "Kyoto",
            category: "Markets & Crafts",
            colorHex: AppColor.GroupPastel.matcha.hexString,
            tags: ["Crafts", "Antiques", "Culture", "Temple"],
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
            subscriberCount: 1560
        )
        
        let cal5 = LocalCalendar(
            id: "local_tokyo_art",
            title: "Tokyo Architecture & Modern Art Walk",
            description: "Contemporary galleries, architectural showcases, and museum exhibitions open for the 14-day window.",
            region: "Tokyo",
            category: "Art & Design",
            colorHex: AppColor.GroupPastel.mist.hexString,
            tags: ["Art", "Design", "Museum", "Exhibition"],
            subscriberCount: 970
        )
        
        self.localCalendars = [cal1, cal2, cal3, cal4, cal5]
        
        // Seed next-14-days events for each calendar
        seedLocalEvents()
        
        // Default follow 1 calendar for pleasant initial state
        if followedCalendarIds.isEmpty {
            followedCalendarIds = ["local_tokyo_coffee"]
        }
        
        persistData()
    }
    
    private func seedLocalEvents() {
        let today = Date()
        let cal = Calendar.current
        
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
            targeting: PromotionTargeting(regions: ["Tokyo", "Kyoto", "Taipei", "Osaka"], interests: ["Art", "Culture"]),
            startDate: today,
            endDate: cal.date(byAdding: .day, value: 25, to: today) ?? today,
            isPaid: true
        )
        
        self.promotions = [promo1, promo2]
    }
}
