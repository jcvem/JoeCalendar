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
            // Source type filter
            if let filter = selectedSourceFilter, event.calendarType != filter {
                return false
            }
            
            // Group filter
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
    }
    
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
        
        // 3. Merge with local Joe / curated events (Last-write-wins)
        let nonExternalEvents = events.filter { $0.calendarType == .joe || $0.calendarType == .local || $0.calendarType == .promo }
        
        // Filter out old external events and replace with fresh sync
        var merged: [CalendarEvent] = nonExternalEvents
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
