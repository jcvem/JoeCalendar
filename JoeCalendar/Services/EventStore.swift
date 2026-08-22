//
//  EventStore.swift
//  JoeCalendar
//
//  Created for JoeCalendar Phase 1 Core Calendar.
//  Unified event repository merging Joe local, Apple EventKit,
//  and Google Calendar events with two-way sync and reactive filtering.
//

import Foundation
import Combine
import SwiftUI

#if canImport(FirebaseFirestore)
import FirebaseFirestore
#endif

public enum CalendarViewMode: String, CaseIterable, Identifiable {
    case month = "month"
    case week = "week"
    case list = "list"
    
    public var id: String { rawValue }
    
    public var displayNameKey: String {
        switch self {
        case .month: return "calendar_view_month"
        case .week: return "calendar_view_week"
        case .list: return "calendar_view_list"
        }
    }
    
    public var iconName: String {
        switch self {
        case .month: return "calendar"
        case .week: return "chart.bar.xaxis"
        case .list: return "list.bullet"
        }
    }
}

@MainActor
public final class EventStore: ObservableObject {
    public static let shared = EventStore()
    
    @Published public private(set) var events: [CalendarEvent] = []
    @Published public var isLoading: Bool = false
    @Published public var isSyncing: Bool = false
    @Published public var lastSyncDate: Date?
    
    // View state
    @Published public var selectedDate: Date = Date()
    @Published public var viewMode: CalendarViewMode = .month
    @Published public var selectedSourceFilter: CalendarType? = nil // nil means "All"
    @Published public var selectedGroupId: String? = nil
    @Published public var searchQuery: String = ""
    
    private let eventKitService = EventKitService.shared
    private let googleService = GoogleCalendarService.shared
    private let firebaseService = FirebaseService.shared
    
    private let calendar = Calendar.current
    private let localEventsKey = "joecalendar_persisted_events_v1"
    
    private init() {
        loadPersistedEvents()
        if events.isEmpty {
            seedDefaultEvents()
        }
        Task {
            await syncAll()
        }
    }
    
    // MARK: - Querying & Filtering
    
    public var filteredEvents: [CalendarEvent] {
        events.filter { event in
            // Guardrail: Never inject promo ad units into private, group, or calendar grid views
            if event.calendarType == .promo {
                return false
            }
            
            // Source type filter
            if let filter = selectedSourceFilter, event.calendarType != filter {
                return false
            }
            
            // Group filter (strict privacy isolation)
            if let groupId = selectedGroupId {
                if event.visibility.type != .group || !event.visibility.groupIds.contains(groupId) {
                    return false
                }
            }
            
            // Search query
            if !searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let q = searchQuery.lowercased()
                let matchTitle = event.title.lowercased().contains(q)
                let matchNotes = event.notes?.lowercased().contains(q) ?? false
                let matchLoc = event.location?.lowercased().contains(q) ?? false
                return matchTitle || matchNotes || matchLoc
            }
            
            return true
        }
    }
    
    public func events(for date: Date) -> [CalendarEvent] {
        filteredEvents.filter { event in
            if event.isAllDay {
                return calendar.isDate(event.startDate, inSameDayAs: date) ||
                       (event.isMultiDay && date >= calendar.startOfDay(for: event.startDate) && date <= calendar.startOfDay(for: event.endDate))
            } else {
                return calendar.isDate(event.startDate, inSameDayAs: date)
            }
        }.sorted { $0.startDate < $1.startDate }
    }
    
    public func events(in interval: DateInterval) -> [CalendarEvent] {
        filteredEvents.filter { event in
            interval.contains(event.startDate) || interval.contains(event.endDate) ||
            (event.startDate <= interval.start && event.endDate >= interval.end)
        }.sorted { $0.startDate < $1.startDate }
    }
    
    public func upcomingEvents(from startDate: Date = Date(), daysAhead: Int = 30) -> [(key: Date, events: [CalendarEvent])] {
        let endDate = calendar.date(byAdding: .day, value: daysAhead, to: startDate) ?? startDate
        let interval = DateInterval(start: calendar.startOfDay(for: startDate), end: calendar.endOfDay(for: endDate))
        let matched = events(in: interval)
        
        // Group by day
        var grouped: [Date: [CalendarEvent]] = [:]
        for event in matched {
            let dayKey = calendar.startOfDay(for: event.startDate)
            if grouped[dayKey] == nil {
                grouped[dayKey] = []
            }
            grouped[dayKey]?.append(event)
        }
        
        // Sort groups by date
        return grouped.sorted { $0.key < $1.key }
            .map { (key: $0.key, events: $0.value.sorted { $0.startDate < $1.startDate }) }
    }
    
    public func events(for groupId: String) -> [CalendarEvent] {
        events.filter { event in
            event.visibility.type == .group && event.visibility.groupIds.contains(groupId)
        }.sorted { $0.startDate < $1.startDate }
    }
    
    public func selectGroupFilter(_ groupId: String?) {
        self.selectedGroupId = groupId
    }
    
    public func clearGroupFilter() {
        self.selectedGroupId = nil
    }
    
    // MARK: - Mutations (Create, Edit, Delete)
    
    public func addEvent(_ event: CalendarEvent) async throws {
        var mutableEvent = event
        mutableEvent.updatedAt = Date()
        
        switch mutableEvent.calendarType {
        case .device:
            if eventKitService.authStatus.isAuthorized {
                do {
                    let extId = try await eventKitService.saveEvent(mutableEvent)
                    mutableEvent.externalId = extId
                    mutableEvent.syncStatus = .synced
                } catch {
                    mutableEvent.syncStatus = .pendingSync
                }
            }
        case .google:
            if googleService.isSignedIn {
                do {
                    let extId = try await googleService.saveEvent(mutableEvent)
                    mutableEvent.externalId = extId
                    mutableEvent.syncStatus = .synced
                } catch {
                    mutableEvent.syncStatus = .pendingSync
                }
            }
        case .joe, .local, .promo:
            mutableEvent.syncStatus = .synced
        }
        
        events.append(mutableEvent)
        events.sort { $0.startDate < $1.startDate }
        persistEvents()
        
        // Asynchronously mirror to Firestore `events/{eventId}`
        Task {
            try? await pushEventToFirestore(mutableEvent)
        }
    }
    
    public func updateEvent(_ event: CalendarEvent) async throws {
        var mutableEvent = event
        mutableEvent.updatedAt = Date()
        
        switch mutableEvent.calendarType {
        case .device:
            if eventKitService.authStatus.isAuthorized {
                do {
                    let extId = try await eventKitService.saveEvent(mutableEvent)
                    mutableEvent.externalId = extId
                    mutableEvent.syncStatus = .synced
                } catch {
                    mutableEvent.syncStatus = .pendingSync
                }
            }
        case .google:
            if googleService.isSignedIn {
                do {
                    let extId = try await googleService.saveEvent(mutableEvent)
                    mutableEvent.externalId = extId
                    mutableEvent.syncStatus = .synced
                } catch {
                    mutableEvent.syncStatus = .pendingSync
                }
            }
        case .joe, .local, .promo:
            mutableEvent.syncStatus = .synced
        }
        
        if let index = events.firstIndex(where: { $0.id == mutableEvent.id }) {
            events[index] = mutableEvent
            events.sort { $0.startDate < $1.startDate }
            persistEvents()
            
            Task {
                try? await pushEventToFirestore(mutableEvent)
            }
        }
    }
    
    public func deleteEvent(_ event: CalendarEvent) async throws {
        switch event.calendarType {
        case .device:
            if let extId = event.externalId {
                try? await eventKitService.deleteEvent(externalId: extId)
            }
        case .google:
            if let extId = event.externalId {
                try? await googleService.deleteEvent(externalId: extId)
            }
        case .joe, .local, .promo:
            break
        }
        
        events.removeAll { $0.id == event.id }
        persistEvents()
        
        Task {
            try? await deleteEventFromFirestore(eventId: event.id)
        }
    }
    
    // MARK: - Firestore Integration (Real SDK + REST Mirror)
    
    private func pushEventToFirestore(_ event: CalendarEvent) async throws {
        let createdByUid = event.createdBy.isEmpty ? FriendService.shared.currentUser.id : event.createdBy
        
        #if canImport(FirebaseFirestore)
        if let firestore = FirebaseService.shared.db {
            let docRef = firestore.collection("events").document(event.id)
            var data: [String: Any] = [
                "id": event.id,
                "title": event.title,
                "startDate": Timestamp(date: event.startDate),
                "endDate": Timestamp(date: event.endDate),
                "isAllDay": event.isAllDay,
                "calendarType": event.calendarType.rawValue,
                "visibility": [
                    "type": event.visibility.type.rawValue,
                    "groupIds": event.visibility.groupIds
                ],
                "recurrence": event.recurrence.rawValue,
                "createdBy": createdByUid,
                "colorHex": event.colorHex,
                "source": event.source ?? event.calendarType.rawValue,
                "syncStatus": event.syncStatus.rawValue,
                "createdAt": Timestamp(date: event.createdAt),
                "updatedAt": Timestamp(date: event.updatedAt)
            ]
            if let loc = event.location { data["location"] = loc }
            if let notes = event.notes { data["notes"] = notes }
            if let extId = event.externalId { data["externalId"] = extId }
            if let extCalId = event.externalCalendarId { data["externalCalendarId"] = extCalId }
            
            try await docRef.setData(data, merge: true)
            return
        }
        #endif
        
        let projectId = "joecalendar-e8327"
        guard let url = URL(string: "https://firestore.googleapis.com/v1/projects/\(projectId)/databases/(default)/documents/events/\(event.id)") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let isoFormatter = ISO8601DateFormatter()
        
        var fields: [String: Any] = [
            "title": ["stringValue": event.title],
            "startDate": ["timestampValue": isoFormatter.string(from: event.startDate)],
            "endDate": ["timestampValue": isoFormatter.string(from: event.endDate)],
            "isAllDay": ["booleanValue": event.isAllDay],
            "calendarType": ["stringValue": event.calendarType.rawValue],
            "visibility": [
                "mapValue": [
                    "fields": [
                        "type": ["stringValue": event.visibility.type.rawValue],
                        "groupIds": [
                            "arrayValue": [
                                "values": event.visibility.groupIds.map { ["stringValue": $0] }
                            ]
                        ]
                    ]
                ]
            ],
            "recurrence": ["stringValue": event.recurrence.rawValue],
            "createdBy": ["stringValue": createdByUid],
            "colorHex": ["stringValue": event.colorHex],
            "source": ["stringValue": event.source ?? event.calendarType.rawValue],
            "createdAt": ["timestampValue": isoFormatter.string(from: event.createdAt)],
            "updatedAt": ["timestampValue": isoFormatter.string(from: event.updatedAt)]
        ]
        
        if let location = event.location {
            fields["location"] = ["stringValue": location]
        }
        if let notes = event.notes {
            fields["notes"] = ["stringValue": notes]
        }
        
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["fields": fields])
        _ = try? await URLSession.shared.data(for: request)
    }
    
    private func deleteEventFromFirestore(eventId: String) async throws {
        #if canImport(FirebaseFirestore)
        if let firestore = FirebaseService.shared.db {
            try await firestore.collection("events").document(eventId).delete()
            return
        }
        #endif
        
        let projectId = "joecalendar-e8327"
        guard let url = URL(string: "https://firestore.googleapis.com/v1/projects/\(projectId)/databases/(default)/documents/events/\(eventId)") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        _ = try? await URLSession.shared.data(for: request)
    }
    
    #if canImport(FirebaseFirestore)
    private func fetchFirestoreEvents() async -> [CalendarEvent] {
        guard let firestore = FirebaseService.shared.db else { return [] }
        let currentUid = FriendService.shared.currentUser.id
        let groupIds = FriendService.shared.currentUser.groupIds
        
        var results: [CalendarEvent] = []
        
        // 1. Fetch events created by user
        if let ownSnapshot = try? await firestore.collection("events").whereField("createdBy", isEqualTo: currentUid).getDocuments() {
            for doc in ownSnapshot.documents {
                if let event = parseFirestoreEvent(id: doc.documentID, data: doc.data()) {
                    results.append(event)
                }
            }
        }
        
        // 2. Fetch public events
        if let pubSnapshot = try? await firestore.collection("events").whereField("visibility.type", isEqualTo: "public").limit(to: 50).getDocuments() {
            for doc in pubSnapshot.documents {
                if let event = parseFirestoreEvent(id: doc.documentID, data: doc.data()), !results.contains(where: { $0.id == event.id }) {
                    results.append(event)
                }
            }
        }
        
        // 3. Fetch group events for user's groups
        for groupId in groupIds {
            if let groupSnapshot = try? await firestore.collection("events")
                .whereField("visibility.type", isEqualTo: "group")
                .whereField("visibility.groupIds", arrayContains: groupId)
                .limit(to: 30)
                .getDocuments() {
                for doc in groupSnapshot.documents {
                    if let event = parseFirestoreEvent(id: doc.documentID, data: doc.data()), !results.contains(where: { $0.id == event.id }) {
                        results.append(event)
                    }
                }
            }
        }
        
        return results
    }
    
    private func parseFirestoreEvent(id: String, data: [String: Any]) -> CalendarEvent? {
        guard let title = data["title"] as? String else { return nil }
        
        let startDate = (data["startDate"] as? Timestamp)?.dateValue() ?? Date()
        let endDate = (data["endDate"] as? Timestamp)?.dateValue() ?? Date()
        let isAllDay = data["isAllDay"] as? Bool ?? false
        let location = data["location"] as? String
        let notes = data["notes"] as? String
        let calTypeStr = data["calendarType"] as? String ?? "joe"
        let calendarType = CalendarType(rawValue: calTypeStr) ?? .joe
        
        var visibility = EventVisibility(type: .private)
        if let visMap = data["visibility"] as? [String: Any] {
            let typeStr = visMap["type"] as? String ?? "private"
            let visType = EventVisibilityType(rawValue: typeStr) ?? .private
            let groupIds = visMap["groupIds"] as? [String] ?? []
            visibility = EventVisibility(type: visType, groupIds: groupIds)
        }
        
        let recStr = data["recurrence"] as? String ?? "none"
        let recurrence = EventRecurrence(rawValue: recStr) ?? .none
        let createdBy = data["createdBy"] as? String ?? ""
        let colorHex = data["colorHex"] as? String ?? AppColor.GroupPastel.sage.hexString
        let source = data["source"] as? String ?? calendarType.rawValue
        let externalId = data["externalId"] as? String
        let externalCalendarId = data["externalCalendarId"] as? String
        let syncStatusStr = data["syncStatus"] as? String ?? "synced"
        let syncStatus = SyncStatus(rawValue: syncStatusStr) ?? .synced
        let coverImageUrl = data["coverImageUrl"] as? String
        let eventUrl = data["eventUrl"] as? String
        let createdAt = (data["createdAt"] as? Timestamp)?.dateValue() ?? Date()
        let updatedAt = (data["updatedAt"] as? Timestamp)?.dateValue() ?? Date()
        
        return CalendarEvent(
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
    }
    #endif
    
    // MARK: - Synchronization
    
    public func syncAll() async {
        guard !isSyncing else { return }
        isSyncing = true
        defer {
            isSyncing = false
            lastSyncDate = Date()
        }
        
        let start = calendar.date(byAdding: .month, value: -2, to: Date()) ?? Date()
        let end = calendar.date(byAdding: .month, value: 4, to: Date()) ?? Date()
        
        // 1. Pull Device Calendar
        var deviceEvents: [CalendarEvent] = []
        if eventKitService.authStatus.isAuthorized {
            deviceEvents = await eventKitService.fetchEvents(startDate: start, endDate: end)
        }
        
        // 2. Pull Google Calendar
        var googleEvents: [CalendarEvent] = []
        if googleService.isSignedIn {
            googleEvents = (try? await googleService.fetchEvents(startDate: start, endDate: end)) ?? []
        }
        
        // 3. Pull Firestore Joe / Group / Public events if configured
        var firestoreEvents: [CalendarEvent] = []
        #if canImport(FirebaseFirestore)
        if FirebaseService.shared.isConfigured {
            firestoreEvents = await fetchFirestoreEvents()
        }
        #endif
        
        // 4. Merge with local Joe / curated events (Last-write-wins)
        let nonExternalEvents = events.filter { $0.calendarType == .joe || $0.calendarType == .local || $0.calendarType == .promo }
        
        var merged: [CalendarEvent] = nonExternalEvents
        merged.append(contentsOf: firestoreEvents)
        merged.append(contentsOf: deviceEvents)
        merged.append(contentsOf: googleEvents)
        
        // Deduplicate by externalId if present, else id
        var uniqueMap: [String: CalendarEvent] = [:]
        for ev in merged {
            let key = ev.externalId ?? ev.id
            if let existing = uniqueMap[key] {
                // Last write wins
                if ev.updatedAt >= existing.updatedAt {
                    uniqueMap[key] = ev
                }
            } else {
                uniqueMap[key] = ev
            }
        }
        
        self.events = Array(uniqueMap.values).sorted { $0.startDate < $1.startDate }
        persistEvents()
    }

    
    // MARK: - Persistence
    
    private func persistEvents() {
        // Only persist Joe / local events in UserDefaults, external events are re-fetched from sources
        let savable = events.filter { $0.calendarType == .joe || $0.calendarType == .local || $0.calendarType == .promo }
        if let encoded = try? JSONEncoder().encode(savable) {
            UserDefaults.standard.set(encoded, forKey: localEventsKey)
        }
    }
    
    private func loadPersistedEvents() {
        if let data = UserDefaults.standard.data(forKey: localEventsKey),
           let decoded = try? JSONDecoder().decode([CalendarEvent].self, from: data) {
            self.events = decoded
        }
    }
    
    // MARK: - Sample Seed
    
    private func seedDefaultEvents() {
        let today = Date()
        
        let event1 = CalendarEvent(
            id: "seed_joe_1",
            title: "Morning Pickleball Session",
            startDate: calendar.date(bySettingHour: 7, minute: 30, second: 0, of: today) ?? today,
            endDate: calendar.date(bySettingHour: 9, minute: 0, second: 0, of: today) ?? today,
            location: "Tokyo Sports Center Court 3",
            notes: "Bring extra paddle and water bottle. Shared with Workout Crew.",
            calendarType: .joe,
            visibility: EventVisibility(type: .group, groupIds: ["workout_friends"]),
            recurrence: .weekly,
            createdBy: "me",
            colorHex: AppColor.GroupPastel.sage.hexString,
            source: "joe"
        )
        
        let event2 = CalendarEvent(
            id: "seed_joe_2",
            title: "Family Weekend Brunch",
            startDate: calendar.date(byAdding: .day, value: 1, to: calendar.date(bySettingHour: 11, minute: 0, second: 0, of: today) ?? today) ?? today,
            endDate: calendar.date(byAdding: .day, value: 1, to: calendar.date(bySettingHour: 13, minute: 0, second: 0, of: today) ?? today) ?? today,
            location: "Daikanyama Cafe",
            notes: "Outdoor seating reserved.",
            calendarType: .joe,
            visibility: EventVisibility(type: .group, groupIds: ["family"]),
            recurrence: .none,
            createdBy: "me",
            colorHex: AppColor.GroupPastel.sakura.hexString,
            source: "joe"
        )
        
        let event3 = CalendarEvent(
            id: "seed_local_1",
            title: "Omotesando Light & Art Walk",
            startDate: calendar.date(byAdding: .day, value: 2, to: today) ?? today,
            endDate: calendar.date(byAdding: .day, value: 2, to: today) ?? today,
            isAllDay: true,
            location: "Mori Arts Center Gallery",
            notes: "Curated local cultural highlight for the next 14 days.",
            calendarType: .local,
            visibility: EventVisibility(type: .public),
            recurrence: .none,
            createdBy: "curator_tokyo",
            colorHex: AppColor.GroupPastel.yamabuki.hexString,
            source: "local"
        )
        
        let event4 = CalendarEvent(
            id: "seed_promo_1",
            title: "Tokyo Artisan Coffee Fair",
            startDate: calendar.date(byAdding: .day, value: 4, to: calendar.date(bySettingHour: 10, minute: 0, second: 0, of: today) ?? today) ?? today,
            endDate: calendar.date(byAdding: .day, value: 4, to: calendar.date(bySettingHour: 18, minute: 0, second: 0, of: today) ?? today) ?? today,
            location: "Shibuya Stream Hall",
            notes: "Free entry for JoeCalendar members. Special roaster tastings.",
            calendarType: .promo,
            visibility: EventVisibility(type: .public),
            recurrence: .none,
            createdBy: "sponsor_coffee_japan",
            colorHex: AppColor.GroupPastel.akane.hexString,
            source: "promo"
        )
        
        self.events = [event1, event2, event3, event4]
        persistEvents()
    }
}

// MARK: - Calendar End of Day Helper

private extension Calendar {
    func endOfDay(for date: Date) -> Date {
        let comps = DateComponents(day: 1, second: -1)
        return self.date(byAdding: comps, to: startOfDay(for: date)) ?? date
    }
}
