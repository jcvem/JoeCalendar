//
//  GoogleCalendarService.swift
//  JoeCalendar
//
//  Created for JoeCalendar Phase 1 Core Calendar & Upgraded for Real Google OAuth + Calendar Sync.
//  Encapsulates Google Calendar API (v3) OAuth state via GoogleSignIn-iOS SDK,
//  secure token refresh, REST endpoints (calendarList, events pull/push/delete),
//  and graceful offline demo fallback.
//

import Foundation
import Combine
import SwiftUI
import UIKit

#if canImport(GoogleSignIn)
import GoogleSignIn
#endif

#if canImport(FirebaseAuth)
import FirebaseAuth
#endif

public struct GoogleCalendarItem: Identifiable, Codable, Equatable, Hashable {
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

public enum GoogleCalendarConfig {
    /// OAuth 2.0 Client ID for Google Sign-In (iOS Bundle: com.vemstudio.joecalendar).
    /// Founder note: Set via GoogleService-Info.plist or Info.plist GIDClientID.
    /// FLAG: NEED_GOOGLE_OAUTH_CLIENT_ID
    public static let fallbackClientID: String = "950611334449-8274paf82h4qpmmq9fuapr8lmtllpbk9.apps.googleusercontent.com"
}

@MainActor
public final class GoogleCalendarService: ObservableObject {
    public static let shared = GoogleCalendarService()
    
    // MARK: - Published Properties
    
    @Published public private(set) var isSignedIn: Bool = false
    @Published public var isGoogleConnected: Bool = false
    @Published public private(set) var isConfigured: Bool = true
    @Published public private(set) var userEmail: String?
    @Published public private(set) var userDisplayName: String?
    @Published public private(set) var userAvatarUrl: URL?
    @Published public private(set) var isSyncing: Bool = false
    @Published public private(set) var lastSyncDate: Date?
    @Published public var availableCalendars: [GoogleCalendarItem] = []
    @Published public var selectedCalendarId: String = "primary"
    @Published public var authErrorMessage: String? = nil
    
    // MARK: - OAuth Scopes
    
    public static let calendarScopes: [String] = [
        "https://www.googleapis.com/auth/calendar",
        "https://www.googleapis.com/auth/calendar.readonly",
        "https://www.googleapis.com/auth/calendar.events"
    ]
    
    // In-memory access token (secure: never saved in plaintext UserDefaults)
    private var accessToken: String?
    
    private let emailKey = "joecalendar_google_user_email"
    private let selectedCalKey = "joecalendar_google_selected_cal_id"
    private let legacyTokenKey = "joecalendar_google_access_token"
    
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
        checkConfiguration()
        loadStoredSession()
        Task {
            await restorePreviousSignIn()
        }
    }
    
    // MARK: - Client ID & Configuration
    
    public var resolvedClientID: String? {
        if let id = Bundle.main.object(forInfoDictionaryKey: "GIDClientID") as? String, !id.isEmpty {
            return id
        }
        if let id = Bundle.main.object(forInfoDictionaryKey: "GoogleSignInClientID") as? String, !id.isEmpty {
            return id
        }
        if let path = Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist"),
           let dict = NSDictionary(contentsOfFile: path) as? [String: Any],
           let id = dict["CLIENT_ID"] as? String, !id.isEmpty {
            return id
        }
        if !GoogleCalendarConfig.fallbackClientID.isEmpty {
            return GoogleCalendarConfig.fallbackClientID
        }
        return nil
    }
    
    private func checkConfiguration() {
        if let clientID = resolvedClientID, !clientID.isEmpty {
            self.isConfigured = true
            #if canImport(GoogleSignIn)
            GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientID)
            #endif
        } else {
            self.isConfigured = false
            print("GoogleCalendarService: No Google OAuth Client ID found. Running with demo fallback.")
        }
    }
    
    private func loadStoredSession() {
        // Clean legacy plaintext token if previously persisted
        UserDefaults.standard.removeObject(forKey: legacyTokenKey)
        
        self.userEmail = UserDefaults.standard.string(forKey: emailKey)
        self.selectedCalendarId = UserDefaults.standard.string(forKey: selectedCalKey) ?? "primary"
        if let email = self.userEmail, !email.isEmpty {
            self.isSignedIn = true
            self.isGoogleConnected = true
        }
    }
    
    // MARK: - Google Sign-In (Real OAuth)
    
    /// Presents Google Sign-In sheet, requests Calendar scopes, and binds real OAuth access token
    public func signIn(presenting viewController: UIViewController? = nil) async throws {
        self.authErrorMessage = nil
        
        #if canImport(GoogleSignIn)
        guard let clientID = resolvedClientID, !clientID.isEmpty else {
            print("GoogleCalendarService: Missing Client ID, falling back to demo sign-in.")
            try await signInWithDemo()
            return
        }
        
        GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientID)
        
        guard let presentingVC = viewController ?? getTopViewController() else {
            let error = NSError(
                domain: "JoeCalendar.GoogleCalendar",
                code: 400,
                userInfo: [NSLocalizedDescriptionKey: "Could not find a presenting view controller for Google Sign-In."]
            )
            self.authErrorMessage = error.localizedDescription
            throw error
        }
        
        do {
            let result = try await GIDSignIn.sharedInstance.signIn(
                withPresenting: presentingVC,
                hint: nil,
                additionalScopes: Self.calendarScopes
            )
            
            applyGoogleUser(result.user)
            
            // Link or authenticate Firebase with Google credential if Firebase is available
            #if canImport(FirebaseAuth)
            if let idToken = result.user.idToken?.tokenString {
                let credential = GoogleAuthProvider.credential(
                    withIDToken: idToken,
                    accessToken: result.user.accessToken.tokenString
                )
                do {
                    _ = try await Auth.auth().signIn(with: credential)
                    print("GoogleCalendarService: Firebase Auth linked successfully with Google user!")
                } catch {
                    print("GoogleCalendarService: Firebase Auth link note: \(error.localizedDescription)")
                }
            }
            #endif
            
            // Fetch the user's real Google Calendar list
            await fetchAvailableCalendars()
            
        } catch {
            self.authErrorMessage = error.localizedDescription
            print("GoogleCalendarService: Google Sign-In failed: \(error.localizedDescription)")
            throw error
        }
        #else
        // If GoogleSignIn SDK is not linked at runtime, fall back gracefully to demo mode
        try await signInWithDemo()
        #endif
    }
    
    #if canImport(GoogleSignIn)
    private func applyGoogleUser(_ user: GIDGoogleUser) {
        let token = user.accessToken.tokenString
        let email = user.profile?.email ?? "user@gmail.com"
        let displayName = user.profile?.name
        let avatarUrl = user.profile?.imageURL(withDimension: 120)
        
        self.accessToken = token
        self.userEmail = email
        self.userDisplayName = displayName
        self.userAvatarUrl = avatarUrl
        self.isSignedIn = true
        self.isGoogleConnected = true
        
        UserDefaults.standard.set(email, forKey: emailKey)
        
        // Seed default primary calendar if list is empty
        if self.availableCalendars.isEmpty {
            self.availableCalendars = [
                GoogleCalendarItem(id: "primary", summary: email, isPrimary: true, backgroundColor: "#4285F4")
            ]
        }
    }
    #endif
    
    /// Restores a previously active Google sign-in session from secure keychain on app launch
    public func restorePreviousSignIn() async {
        #if canImport(GoogleSignIn)
        guard GIDSignIn.sharedInstance.hasPreviousSignIn() else { return }
        do {
            let user = try await GIDSignIn.sharedInstance.restorePreviousSignIn()
            applyGoogleUser(user)
            await fetchAvailableCalendars()
            print("GoogleCalendarService: Restored previous Google session for \(user.profile?.email ?? "user")")
        } catch {
            print("GoogleCalendarService: Previous session restore note: \(error.localizedDescription)")
        }
        #endif
    }
    
    // MARK: - Demo Fallback Mode
    
    /// Fallback demo mode for offline testing or when client ID is not configured
    public func signInWithDemo(email: String? = nil, token: String? = nil) async throws {
        let finalEmail = email ?? "user@gmail.com"
        let finalToken = token ?? "demo_oauth_token_\(UUID().uuidString)"
        
        self.accessToken = finalToken
        self.userEmail = finalEmail
        self.userDisplayName = "Demo Google User"
        self.isSignedIn = true
        self.isGoogleConnected = true
        
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
    
    // MARK: - Sign Out
    
    public func signOut() {
        #if canImport(GoogleSignIn)
        GIDSignIn.sharedInstance.signOut()
        #endif
        
        self.isSignedIn = false
        self.isGoogleConnected = false
        self.accessToken = nil
        self.userEmail = nil
        self.userDisplayName = nil
        self.userAvatarUrl = nil
        self.availableCalendars = []
        self.mockGoogleEvents = []
        self.authErrorMessage = nil
        
        UserDefaults.standard.removeObject(forKey: emailKey)
        UserDefaults.standard.removeObject(forKey: selectedCalKey)
        UserDefaults.standard.removeObject(forKey: legacyTokenKey)
    }
    
    // MARK: - Token Refresh & Management
    
    /// Retrieves a fresh access token, proactively refreshing via GoogleSignIn SDK if expired
    private func getFreshAccessToken() async throws -> String? {
        #if canImport(GoogleSignIn)
        if let currentUser = GIDSignIn.sharedInstance.currentUser {
            do {
                let refreshedUser = try await currentUser.refreshTokensIfNeeded()
                let freshToken = refreshedUser.accessToken.tokenString
                self.accessToken = freshToken
                return freshToken
            } catch {
                print("GoogleCalendarService: Token refresh failed: \(error.localizedDescription)")
                throw error
            }
        }
        #endif
        return self.accessToken
    }
    
    // MARK: - Fetch Calendars List (calendarList)
    
    public func fetchAvailableCalendars() async {
        guard isSignedIn, let token = accessToken, !token.starts(with: "demo_oauth_token_") else {
            return
        }
        
        do {
            let calendars = try await fetchCalendarListViaAPI(token: token, isRetry: false)
            if !calendars.isEmpty {
                self.availableCalendars = calendars
            }
        } catch {
            print("GoogleCalendarService: Failed to fetch calendar list: \(error.localizedDescription)")
        }
    }
    
    private func fetchCalendarListViaAPI(token: String, isRetry: Bool) async throws -> [GoogleCalendarItem] {
        guard let url = URL(string: "https://www.googleapis.com/calendar/v3/users/me/calendarList") else {
            return []
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NSError(domain: "JoeCalendar.GoogleCalendar", code: 500, userInfo: [NSLocalizedDescriptionKey: "Invalid network response"])
        }
        
        // Handle 401 Token Expiry -> Refresh and retry once
        if httpResponse.statusCode == 401 && !isRetry {
            print("GoogleCalendarService: Received 401 on calendarList fetch. Refreshing token...")
            if let freshToken = try await getFreshAccessToken() {
                return try await fetchCalendarListViaAPI(token: freshToken, isRetry: true)
            }
        }
        
        guard (200...299).contains(httpResponse.statusCode) else {
            throw NSError(domain: "JoeCalendar.GoogleCalendar", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "Calendar list fetch returned status \(httpResponse.statusCode)"])
        }
        
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let items = json["items"] as? [[String: Any]] else {
            return []
        }
        
        var parsedCalendars: [GoogleCalendarItem] = []
        for item in items {
            guard let id = item["id"] as? String,
                  let summary = item["summary"] as? String else {
                continue
            }
            let description = item["description"] as? String
            let isPrimary = (item["primary"] as? Bool) ?? false
            let bgColor = item["backgroundColor"] as? String
            
            parsedCalendars.append(GoogleCalendarItem(
                id: id,
                summary: summary,
                description: description,
                isPrimary: isPrimary,
                backgroundColor: bgColor
            ))
        }
        
        return parsedCalendars
    }
    
    // MARK: - Fetch Events (REST Pull)
    
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
                return try await fetchEventsViaAPI(startDate: startDate, endDate: endDate, token: token, isRetry: false)
            } catch {
                print("GoogleCalendarService: Real REST API fetch error: \(error.localizedDescription). Returning cached events.")
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
    
    private func fetchEventsViaAPI(startDate: Date, endDate: Date, token: String, isRetry: Bool) async throws -> [CalendarEvent] {
        let calendarIdEncoded = selectedCalendarId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? "primary"
        let startISO = isoFormatter.string(from: startDate).addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let endISO = isoFormatter.string(from: endDate).addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        
        guard let url = URL(string: "https://www.googleapis.com/calendar/v3/calendars/\(calendarIdEncoded)/events?timeMin=\(startISO)&timeMax=\(endISO)&singleEvents=true&orderBy=startTime") else {
            return []
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NSError(domain: "JoeCalendar.GoogleCalendar", code: 500, userInfo: [NSLocalizedDescriptionKey: "Invalid network response"])
        }
        
        // Handle 401 Token Expiry -> Refresh and retry once
        if httpResponse.statusCode == 401 && !isRetry {
            print("GoogleCalendarService: Received 401 on events fetch. Refreshing token...")
            if let freshToken = try await getFreshAccessToken() {
                return try await fetchEventsViaAPI(startDate: startDate, endDate: endDate, token: freshToken, isRetry: true)
            }
        }
        
        guard (200...299).contains(httpResponse.statusCode) else {
            throw NSError(domain: "JoeCalendar.GoogleCalendar", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "Failed to fetch Google Calendar events (HTTP \(httpResponse.statusCode))"])
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
            do {
                try await pushEventViaAPI(mutableEvent, token: token, isRetry: false)
            } catch {
                print("GoogleCalendarService: pushEvent error: \(error.localizedDescription)")
            }
        }
        
        // Update local cache
        if let index = mockGoogleEvents.firstIndex(where: { $0.externalId == eventId || $0.id == event.id }) {
            mockGoogleEvents[index] = mutableEvent
        } else {
            mockGoogleEvents.append(mutableEvent)
        }
        
        return eventId
    }
    
    private func pushEventViaAPI(_ event: CalendarEvent, token: String, isRetry: Bool) async throws {
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
        let (_, response) = try await URLSession.shared.data(for: request)
        
        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 401 && !isRetry {
            print("GoogleCalendarService: Received 401 on event push. Refreshing token...")
            if let freshToken = try await getFreshAccessToken() {
                try await pushEventViaAPI(event, token: freshToken, isRetry: true)
            }
        }
    }
    
    // MARK: - Delete Event
    
    public func deleteEvent(externalId: String) async throws {
        guard isSignedIn else { return }
        
        // Remove from local cache
        mockGoogleEvents.removeAll { $0.externalId == externalId || $0.id == externalId }
        
        // If real token available, delete via REST API
        if let token = accessToken, !token.starts(with: "demo_oauth_token_"), !externalId.starts(with: "gcal_") {
            try await deleteEventViaAPI(externalId: externalId, token: token, isRetry: false)
        }
    }
    
    private func deleteEventViaAPI(externalId: String, token: String, isRetry: Bool) async throws {
        let calendarIdEncoded = selectedCalendarId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? "primary"
        guard let url = URL(string: "https://www.googleapis.com/calendar/v3/calendars/\(calendarIdEncoded)/events/\(externalId)") else { return }
        
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        let (_, response) = try await URLSession.shared.data(for: request)
        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 401 && !isRetry {
            print("GoogleCalendarService: Received 401 on event delete. Refreshing token...")
            if let freshToken = try await getFreshAccessToken() {
                try await deleteEventViaAPI(externalId: externalId, token: freshToken, isRetry: true)
            }
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
    
    // MARK: - Top View Controller Helper
    
    private func getTopViewController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .filter { $0.activationState == .foregroundActive }
        
        let window = scenes.flatMap { $0.windows }.first(where: { $0.isKeyWindow })
            ?? UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap { $0.windows }.first
        
        var topController = window?.rootViewController
        while let presented = topController?.presentedViewController {
            topController = presented
        }
        return topController
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

