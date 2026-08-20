//
//  EventKitService.swift
//  JoeCalendar
//
//  Created for JoeCalendar Phase 1 Core Calendar.
//  Encapsulates Apple EventKit authorization, reading, writing,
//  and two-way synchronization with Apple Calendar.
//

import Foundation
import EventKit
import Combine
import UIKit

public enum EventKitAuthStatus {
    case notDetermined
    case authorized
    case denied
    case restricted
    
    public var isAuthorized: Bool {
        self == .authorized
    }
}

@MainActor
public final class EventKitService: ObservableObject {
    public static let shared = EventKitService()
    
    private let eventStore = EKEventStore()
    
    @Published public private(set) var authStatus: EventKitAuthStatus = .notDetermined
    @Published public private(set) var isSyncing: Bool = false
    @Published public private(set) var lastSyncDate: Date?
    @Published public var availableCalendars: [EKCalendar] = []
    @Published public var selectedCalendarIDs: Set<String> = []
    
    private let selectedCalendarsKey = "joecalendar_selected_ek_calendar_ids"
    
    private init() {
        checkCurrentAuthorization()
        loadSelectedCalendarIDs()
    }
    
    // MARK: - Authorization
    
    public func checkCurrentAuthorization() {
        let status = EKEventStore.authorizationStatus(for: .event)
        switch status {
        case .authorized, .fullAccess, .writeOnly:
            self.authStatus = .authorized
            loadAvailableCalendars()
        case .denied:
            self.authStatus = .denied
        case .restricted:
            self.authStatus = .restricted
        case .notDetermined:
            self.authStatus = .notDetermined
        @unknown default:
            self.authStatus = .notDetermined
        }
    }
    
    public func requestAuthorization() async -> Bool {
        do {
            var granted = false
            if #available(iOS 17.0, *) {
                granted = try await eventStore.requestFullAccessToEvents()
            } else {
                granted = try await eventStore.requestAccess(to: .event)
            }
            
            if granted {
                self.authStatus = .authorized
                loadAvailableCalendars()
                return true
            } else {
                self.authStatus = .denied
                return false
            }
        } catch {
            self.authStatus = .denied
            return false
        }
    }
    
    public func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString),
              UIApplication.shared.canOpenURL(url) else {
            return
        }
        UIApplication.shared.open(url)
    }
    
    // MARK: - Calendar Management
    
    public func loadAvailableCalendars() {
        let calendars = eventStore.calendars(for: .event)
        self.availableCalendars = calendars.filter { $0.allowsContentModifications || !$0.isImmutable }
        if self.selectedCalendarIDs.isEmpty {
            // By default select all active calendars
            self.selectedCalendarIDs = Set(calendars.map { $0.calendarIdentifier })
            saveSelectedCalendarIDs()
        }
    }
    
    public func toggleCalendarSelection(_ calendarID: String) {
        if selectedCalendarIDs.contains(calendarID) {
            selectedCalendarIDs.remove(calendarID)
        } else {
            selectedCalendarIDs.insert(calendarID)
        }
        saveSelectedCalendarIDs()
    }
    
    private func loadSelectedCalendarIDs() {
        if let saved = UserDefaults.standard.array(forKey: selectedCalendarsKey) as? [String] {
            self.selectedCalendarIDs = Set(saved)
        }
    }
    
    private func saveSelectedCalendarIDs() {
        UserDefaults.standard.set(Array(selectedCalendarIDs), forKey: selectedCalendarsKey)
    }
    
    // MARK: - EventKit Read (Pull)
    
    public func fetchEvents(startDate: Date, endDate: Date) async -> [CalendarEvent] {
        guard authStatus.isAuthorized else { return [] }
        
        isSyncing = true
        defer {
            isSyncing = false
            lastSyncDate = Date()
        }
        
        let targetCalendars: [EKCalendar]
        if selectedCalendarIDs.isEmpty {
            targetCalendars = eventStore.calendars(for: .event)
        } else {
            targetCalendars = eventStore.calendars(for: .event).filter { selectedCalendarIDs.contains($0.calendarIdentifier) }
        }
        
        let predicate = eventStore.predicateForEvents(withStart: startDate, end: endDate, calendars: targetCalendars)
        let ekEvents = eventStore.events(matching: predicate)
        
        return ekEvents.map { ekEvent in
            mapEKEventToCalendarEvent(ekEvent)
        }
    }
    
    // MARK: - EventKit Write (Push Create / Update)
    
    public func saveEvent(_ event: CalendarEvent) async throws -> String {
        guard authStatus.isAuthorized else {
            throw NSError(domain: "JoeCalendar.EventKit", code: 401, userInfo: [NSLocalizedDescriptionKey: "EventKit unauthorized"])
        }
        
        let ekEvent: EKEvent
        if let extId = event.externalId, let existing = eventStore.event(withIdentifier: extId) {
            ekEvent = existing
        } else {
            ekEvent = EKEvent(eventStore: eventStore)
            ekEvent.calendar = eventStore.defaultCalendarForNewEvents ?? eventStore.calendars(for: .event).first
        }
        
        ekEvent.title = event.title
        ekEvent.startDate = event.startDate
        ekEvent.endDate = event.endDate
        ekEvent.isAllDay = event.isAllDay
        ekEvent.location = event.location
        ekEvent.notes = event.notes
        
        // Map Recurrence
        if let existingRules = ekEvent.recurrenceRules {
            for rule in existingRules {
                ekEvent.removeRecurrenceRule(rule)
            }
        }
        if let ekRule = mapRecurrenceToEKRecurrence(event.recurrence) {
            ekEvent.addRecurrenceRule(ekRule)
        }
        
        try eventStore.save(ekEvent, span: .thisEvent, commit: true)
        return ekEvent.eventIdentifier
    }
    
    // MARK: - EventKit Delete
    
    public func deleteEvent(externalId: String) async throws {
        guard authStatus.isAuthorized else { return }
        if let ekEvent = eventStore.event(withIdentifier: externalId) {
            try eventStore.remove(ekEvent, span: .thisEvent, commit: true)
        }
    }
    
    // MARK: - Mapping Helpers
    
    private func mapEKEventToCalendarEvent(_ ekEvent: EKEvent) -> CalendarEvent {
        var recurrence: EventRecurrence = .none
        if let firstRule = ekEvent.recurrenceRules?.first {
            switch firstRule.frequency {
            case .daily: recurrence = .daily
            case .weekly: recurrence = .weekly
            case .monthly: recurrence = .monthly
            case .yearly: recurrence = .yearly
            @unknown default: recurrence = .none
            }
        }
        
        // Pastel color matching or hex representation
        let colorHex = ekEvent.calendar.cgColor != nil
            ? AppColor.GroupPastel.allCases[abs(ekEvent.calendar.title.hashValue) % AppColor.GroupPastel.allCases.count].hexString
            : AppColor.GroupPastel.mist.hexString
        
        return CalendarEvent(
            id: ekEvent.eventIdentifier ?? UUID().uuidString,
            title: ekEvent.title ?? "(No Title)",
            startDate: ekEvent.startDate,
            endDate: ekEvent.endDate,
            isAllDay: ekEvent.isAllDay,
            location: ekEvent.location,
            notes: ekEvent.notes,
            calendarType: .device,
            visibility: EventVisibility(type: .private), // Device events are always private by default
            recurrence: recurrence,
            createdBy: "device",
            colorHex: colorHex,
            source: "device",
            externalId: ekEvent.eventIdentifier,
            externalCalendarId: ekEvent.calendar?.calendarIdentifier,
            syncStatus: .synced,
            createdAt: ekEvent.creationDate ?? Date(),
            updatedAt: ekEvent.lastModifiedDate ?? Date()
        )
    }
    
    private func mapRecurrenceToEKRecurrence(_ recurrence: EventRecurrence) -> EKRecurrenceRule? {
        switch recurrence {
        case .none:
            return nil
        case .daily:
            return EKRecurrenceRule(recurrenceWith: .daily, interval: 1, end: nil)
        case .weekly:
            return EKRecurrenceRule(recurrenceWith: .weekly, interval: 1, end: nil)
        case .monthly:
            return EKRecurrenceRule(recurrenceWith: .monthly, interval: 1, end: nil)
        case .yearly:
            return EKRecurrenceRule(recurrenceWith: .yearly, interval: 1, end: nil)
        }
    }
}
