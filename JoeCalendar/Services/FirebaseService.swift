//
//  FirebaseService.swift
//  JoeCalendar
//
//  Created for JoeCalendar Phase 0 Foundation.
//  Encapsulates Firebase initialization, Auth state, and Firestore interactions.
//  Note: GoogleService-Info.plist is gitignored and will be placed by PM.
//

import Foundation
import Combine

public enum AuthProviderType {
    case apple
    case google
    case email
    case anonymous
}

@MainActor
public final class FirebaseService: ObservableObject {
    public static let shared = FirebaseService()
    
    @Published public var isAuthenticated: Bool = false
    @Published public var currentUser: JoeUser?
    @Published public var isConfigured: Bool = false
    
    private init() {
        checkConfiguration()
    }
    
    /// Checks if GoogleService-Info.plist is present in the app bundle
    public func checkConfiguration() {
        if let _ = Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist") {
            self.isConfigured = true
        } else {
            self.isConfigured = false
        }
    }
    
    /// Sign in placeholder for Phase 0
    public func signIn(with provider: AuthProviderType) async throws {
        // Phase 0 stub: simulates local guest auth
        self.isAuthenticated = true
        self.currentUser = JoeUser(
            id: "guest_user_demo",
            displayName: "JoeCalendar User",
            email: "user@joecalendar.app",
            locale: LocaleManager.shared.effectiveLanguageCode,
            isAdFree: false
        )
    }
    
    /// Sign out
    public func signOut() {
        self.isAuthenticated = false
        self.currentUser = nil
    }
}
