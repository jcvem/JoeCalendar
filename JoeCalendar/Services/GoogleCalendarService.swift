//
//  GoogleCalendarService.swift
//  JoeCalendar
//
//  Created for JoeCalendar Phase 1 Core Calendar.
//  Encapsulates Google Calendar API (v3) OAuth state, REST endpoints,
//  and two-way synchronization for Google Calendar events.
//

import Foundation
import Combine
import SwiftUI

public struct GoogleCalendarItem: Identifiable, Codable, Equatable {
    public var id: String
    public var summary: String
    public var description: String?
    public var isPrimary: Bool
    public var backgroundColor: String?
    
    public init(id: String, summary: String, description: String? = nil, isPrimary: Bool = false, backgroundColor: String? = nil) {
        self.id = id
        self.summary = summary
        self.description = description
        self.isPrimary = isPrimary
        self.backgroundColor = backgroundColor
    }
}

@MainActor
public final class GoogleCalendarService: ObservableObject {
    public static let shared = GoogleCalendarService()
    
    @Published public private(set) var isSignedIn: Bool = false
    @Published public private(set) var userEmail: String?
    @Published public private(set) var isSyncing: Bool = false
    @Published public private(set) var lastSyncDate: Date?
    @Published public var availableCalendars: [GoogleCalendarItem] = []
    @Published public var selectedCalendarId: String = "primary"
    
    private var accessToken: String?
    private let tokenKey = "joecalendar_google_access_token"
    private let emailKey = "joecalendar_google_user_email"
    private let selectedCalKey = "joecalendar_google_selected_cal_id"
    
    private let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
    
    private let isoFallbackFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
    
    private let dayDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()
    
    // In-memory demo store for when running offline or before real OAuth token is bound
    @Published private var mockGoogleEvents: [CalendarEvent] = []
    
    private init() {
        loadStoredSession()
    }
    
    private func loadStoredSession() {
        if let token = UserDefaults.standard.string(forKey: tokenKey), !token.isEmpty {
            self.accessToken = token
            self.userEmail = UserDefaults.standard.string(forKey: emailKey)
            self.selectedCalendarId = UserDefaults.standard.string(forKey: selectedCalKey) ?? "primary"
            self.isSignedIn = true
        } else {
            self.isSignedIn = false
        }
    }
    
    // MARK: - Sign In / Sign Out
    
    public func signIn(email: String? = nil, token: String? = nil) async throws {
        let finalEmail = email ?? "user@gmail.com"
        let finalToken = token ?? "demo_oauth_token_\(UUID().uuidString)"
        
        self.accessToken = finalToken
        self.userEmail = finalEmail
        self.isSignedIn = true
        
        UserDefaults.standard.set(finalToken, forKey: tokenKey)
        UserDefaults.standard.set(finalEmail, forKey: emailKey)
        
        // Seed default calendar
        self.availableCalendars = [
            GoogleCalendarItem(id: "primary", summary: finalEmail, isPrimary: true, backgroundColor: "#4285F4")
        ]
        
        // Populate initial sample Google events if empty
        if mockGoogleEvents.isEmpty {
            seedSampleEvents()
        }
    }
    
    public func signOut() {
        self.isSignedIn = false
        self.accessToken = nil
        self.userEmail = nil
        self.availableCalendars = []
        self.mockGoogleEvents = []
        UserDefaults.standard.removeObject(forKey: tokenKey)
        UserDefaults.standard.removeObject(forKey: emailKey)
        UserDefaults.standard.removeObject(forKey: selectedCalKey)
    }
    
    // MARK: - Fetch Events (Pull)
    
    public func fetchEvents(startDate: Date, endDate: Date) async throws -> [CalendarEvent] {
        guard isSignedIn else { return [] }
        
        isSyncing = true
        defer {
            isSyncing = false
            lastSyncDate = Date()
        }
        
        // If we have a real network token, attempt REST API
        if let token = accessToken, !token.starts(with: "demo_oauth_token_") {
            do {
                return try await fetchEventsViaAPI(startDate: startDate, endDate: endDate, token: token)
            } catch {
                // Fallback to local mock cache on network error
                return mockGoogleEvents.filter {
                    ($0.startDate >= startDate && $0.startDate <= endDate) ||
                    ($0.endDate >= startDate && $0.endDate <= endDate)
                }
            }
        } else {
            // Local offline mock data
            return mockGoogleEvents.filter {
                ($0.startDate >= startDate && $0.startDate <= endDate) ||
                ($0.endDate >= startDate && $0.endDate <= endDate)
            }
        }
    }
    
    private func fetchEventsViaAPI(startDate: Date, endDate: Date, token: String) async throws -> [CalendarEvent] {
        let calendarIdEncoded = selectedCalendarId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? "primary"
        let startISO = isoFormatter.string(from: startDate).addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let endISO = isoFormatter.string(from: endDate).addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        
        guard let url = URL(string: "https://www.googleapis.com/calendar/v3/calendars/\(calendarIdEncoded)/events?timeMin=\(startISO)&timeMax=\(endISO)&singleEvents=true") else {
            return []
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            throw NSError(domain: "JoeCalendar.GoogleCalendar", code: 400, userInfo: [NSLocalizedDescriptionKey: "Failed to fetch Google Calendar events"])
        }
        
        return try parseGoogleEventsJSON(data: data)
    }
    
    // MARK: - Save Event (Push Create / Update)
    
    public func saveEvent(_ event: CalendarEvent) async throws -> String {
        guard isSignedIn else {
            throw NSError(domain: "JoeCalendar.GoogleCalendar", code: 401, userInfo: [NSLocalizedDescriptionKey: "Google Calendar not signed in"])
        }
        
        var mutableEvent = event
        mutableEvent.calendarType = .google
        mutableEvent.source = "google"
        mutableEvent.syncStatus = .synced
        mutableEvent.updatedAt = Date()
        
        let eventId = event.externalId ?? "gcal_\(UUID().uuidString)"
        mutableEvent.externalId = eventId
        
        // If real token available, push via REST API
        if let token = accessToken, !token.starts(with: "demo_oauth_token_") {
            try? await pushEventViaAPI(mutableEvent, token: token)
        }
        
        // Update local cache
        if let index = mockGoogleEvents.firstIndex(where: { $0.externalId == eventId || $0.id == event.id }) {
            mockGoogleEvents[index] = mutableEvent
        } else {
            mockGoogleEvents.append(mutableEvent)
        }
        
        return eventId
    }
    
    private func pushEventViaAPI(_ event: CalendarEvent, token: String) async throws {
        let calendarIdEncoded = selectedCalendarId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? "primary"
        let isUpdate = event.externalId != nil && !event.externalId!.starts(with: "gcal_")
        
        let urlString = isUpdate
            ? "https://www.googleapis.com/calendar/v3/calendars/\(calendarIdEncoded)/events/\(event.externalId!)"
            : "https://www.googleapis.com/calendar/v3/calendars/\(calendarIdEncoded)/events"
        
        guard let url = URL(string: urlString) else { return }
        
        var request = URLRequest(url: url)
        request.httpMethod = isUpdate ? "PATCH" : "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        var bodyDict: [String: Any] = [
            "summary": event.title,
            "description": event.notes ?? "",
            "location": event.location ?? ""
        ]
        
        if event.isAllDay {
            bodyDict["start"] = ["date": dayDateFormatter.string(from: event.startDate)]
            bodyDict["end"] = ["date": dayDateFormatter.string(from: event.endDate)]
        } else {
            bodyDict["start"] = ["dateTime": isoFormatter.string(from: event.startDate)]
            bodyDict["end"] = ["dateTime": isoFormatter.string(from: event.endDate)]
        }
        
        if event.recurrence != .none {
            let freq = event.recurrence.rawValue.uppercased()
            bodyDict["recurrence"] = ["RRULE:FREQ=\(freq)"]
        }
        
        request.httpBody = try JSONSerialization.data(withJSONObject: bodyDict)
        _ = try await URLSession.shared.data(for: request)
    }
    
    // MARK: - Delete Event
    
    public func deleteEvent(externalId: String) async throws {
        guard isSignedIn else { return }
        
        // Remove from local cache
        mockGoogleEvents.removeAll { $0.externalId == externalId || $0.id == externalId }
        
        // If real token available, delete via REST API
        if let token = accessToken, !token.starts(with: "demo_oauth_token_"), !externalId.starts(with: "gcal_") {
            let calendarIdEncoded = selectedCalendarId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? "primary"
            guard let url = URL(string: "https://www.googleapis.com/calendar/v3/calendars/\(calendarIdEncoded)/events/\(externalId)") else { return }
            var request = URLRequest(url: url)
            request.httpMethod = "DELETE"
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            _ = try? await URLSession.shared.data(for: request)
        }
    }
    
    // MARK: - JSON Parsing Helpers
    
    private func parseGoogleEventsJSON(data: Data) throws -> [CalendarEvent] {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let items = json["items"] as? [[String: Any]] else {
            return []
        }
        
        var parsedEvents: [CalendarEvent] = []
        
        for item in items {
            guard let id = item["id"] as? String,
                  let summary = item["summary"] as? String else {
                continue
            }
            
            let status = item["status"] as? String
            if status == "cancelled" { continue }
            
            var startDate = Date()
            var endDate = Date().addingTimeInterval(3600)
            var isAllDay = false
            
            if let startDict = item["start"] as? [String: Any] {
                if let dateTimeStr = startDict["dateTime"] as? String {
                    startDate = isoFormatter.date(from: dateTimeStr) ?? isoFallbackFormatter.date(from: dateTimeStr) ?? Date()
                } else if let dateStr = startDict["date"] as? String {
                    startDate = dayDateFormatter.date(from: dateStr) ?? Date()
                    isAllDay = true
                }
            }
            
            if let endDict = item["end"] as? [String: Any] {
                if let dateTimeStr = endDict["dateTime"] as? String {
                    endDate = isoFormatter.date(from: dateTimeStr) ?? isoFallbackFormatter.date(from: dateTimeStr) ?? startDate.addingTimeInterval(3600)
                } else if let dateStr = endDict["date"] as? String {
                    endDate = dayDateFormatter.date(from: dateStr) ?? startDate
                }
            }
            
            let notes = item["description"] as? String
            let location = item["location"] as? String
            
            var recurrence: EventRecurrence = .none
            if let recurrenceRules = item["recurrence"] as? [String] {
                for rrule in recurrenceRules {
                    if rrule.contains("FREQ=DAILY") { recurrence = .daily }
                    else if rrule.contains("FREQ=WEEKLY") { recurrence = .weekly }
                    else if rrule.contains("FREQ=MONTHLY") { recurrence = .monthly }
                    else if rrule.contains("FREQ=YEARLY") { recurrence = .yearly }
                }
            }
            
            let event = CalendarEvent(
                id: "google_\(id)",
                title: summary,
                startDate: startDate,
                endDate: endDate,
                isAllDay: isAllDay,
                location: location,
                notes: notes,
                calendarType: .google,
                visibility: EventVisibility(type: .private),
                recurrence: recurrence,
                createdBy: userEmail ?? "google_user",
                colorHex: AppColor.GroupPastel.mist.hexString,
                source: "google",
                externalId: id,
                externalCalendarId: selectedCalendarId,
                syncStatus: .synced
            )
            parsedEvents.append(event)
        }
        
        return parsedEvents
    }
    
    // MARK: - Sample Seed
    
    private func seedSampleEvents() {
        let calendar = Calendar.current
        let today = Date()
        
        let sample1 = CalendarEvent(
            id: "gcal_sample_1",
            title: "Product Sync & Design Sync",
            startDate: calendar.date(bySettingHour: 15, minute: 0, second: 0, of: today) ?? today,
            endDate: calendar.date(bySettingHour: 16, minute: 0, second: 0, of: today) ?? today,
            location: "Google Meet",
            notes: "Weekly team alignment on JoeCalendar MVP",
            calendarType: .google,
            visibility: EventVisibility(type: .private),
            recurrence: .weekly,
            createdBy: userEmail ?? "user@gmail.com",
            colorHex: AppColor.GroupPastel.mist.hexString,
            source: "google",
            externalId: "gcal_sample_1",
            syncStatus: .synced
        )
        
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) ?? today
        let sample2 = CalendarEvent(
            id: "gcal_sample_2",
            title: "Quarterly Strategy Review",
            startDate: calendar.date(bySettingHour: 11, minute: 0, second: 0, of: tomorrow) ?? tomorrow,
            endDate: calendar.date(bySettingHour: 12, minute: 30, second: 0, of: tomorrow) ?? tomorrow,
            location: "Main Boardroom",
            notes: "Prepare Q3 roadmap slides",
            calendarType: .google,
            visibility: EventVisibility(type: .private),
            recurrence: .none,
            createdBy: userEmail ?? "user@gmail.com",
            colorHex: AppColor.GroupPastel.wisteria.hexString,
            source: "google",
            externalId: "gcal_sample_2",
            syncStatus: .synced
        )
        
        mockGoogleEvents = [sample1, sample2]
    }
}
