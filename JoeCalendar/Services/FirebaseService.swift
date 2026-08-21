//
//  FirebaseService.swift
//  JoeCalendar
//
//  Created for JoeCalendar Phase 0 Foundation & Phase 4 Firebase Client Integration.
//  Encapsulates Firebase initialization, Auth state, Firestore database access,
//  and Cloud Functions dispatch against live backend (joecalendar-e8327).
//  Gracefully falls back to local-stub mode when GoogleService-Info.plist is absent.
//

import Foundation
import Combine
import SwiftUI

#if canImport(FirebaseCore)
import FirebaseCore
#endif

#if canImport(FirebaseAuth)
import FirebaseAuth
#endif

#if canImport(FirebaseFirestore)
import FirebaseFirestore
#endif

#if canImport(FirebaseFunctions)
import FirebaseFunctions
#endif

public enum AuthProviderType {
    case apple
    case google
    case email(email: String, password: String)
    case anonymous
}

@MainActor
public final class FirebaseService: ObservableObject {
    public static let shared = FirebaseService()
    
    // MARK: - Published Properties
    @Published public var isAuthenticated: Bool = false
    @Published public var currentUser: JoeUser?
    @Published public var isConfigured: Bool = false
    @Published public var authErrorMessage: String? = nil
    @Published public var isAuthenticating: Bool = false
    
    // MARK: - Private Properties
    private static var didConfigureFirebase: Bool = false
    #if canImport(FirebaseAuth)
    private var authStateHandle: AuthStateDidChangeListenerHandle?
    #endif
    
    // Project configuration
    public let projectId = "joecalendar-e8327"
    public let functionsRegion = "asia-east1"
    
    private init() {
        checkConfiguration()
        #if canImport(FirebaseAuth)
        setupAuthStateListener()
        #endif
    }
    
    deinit {
        #if canImport(FirebaseAuth)
        if let handle = authStateHandle {
            Auth.auth().removeStateDidChangeListener(handle)
        }
        #endif
    }
    
    // MARK: - Firebase SDK Accessors
    
    #if canImport(FirebaseFirestore)
    public var db: Firestore? {
        guard isConfigured else { return nil }
        return Firestore.firestore()
    }
    #endif
    
    #if canImport(FirebaseFunctions)
    public var functions: Functions? {
        guard isConfigured else { return nil }
        return Functions.functions(region: functionsRegion)
    }
    #endif
    
    // MARK: - Initialization & Configuration
    
    /// Checks if GoogleService-Info.plist is present in the app bundle and configures Firebase
    public func checkConfiguration() {
        #if canImport(FirebaseCore)
        if !Self.didConfigureFirebase {
            if let plistPath = Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist"),
               FileManager.default.fileExists(atPath: plistPath) {
                FirebaseApp.configure()
                Self.didConfigureFirebase = true
                self.isConfigured = true
                print("FirebaseService: FirebaseApp configured successfully with GoogleService-Info.plist")
            } else {
                self.isConfigured = false
                print("FirebaseService: GoogleService-Info.plist not found in bundle. Running in local-stub fallback mode.")
            }
        } else {
            self.isConfigured = true
        }
        #else
        self.isConfigured = false
        print("FirebaseService: FirebaseCore not imported. Running in local-stub fallback mode.")
        #endif
    }
    
    // MARK: - Auth State Listener
    
    #if canImport(FirebaseAuth)
    private func setupAuthStateListener() {
        guard isConfigured else {
            // Local fallback initial state
            if currentUser == nil {
                self.currentUser = loadFallbackUser()
                self.isAuthenticated = (currentUser != nil)
            }
            return
        }
        
        self.authStateHandle = Auth.auth().addStateDidChangeListener { [weak self] _, firebaseUser in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                if let fbUser = firebaseUser {
                    self.isAuthenticated = true
                    await self.syncUserProfile(for: fbUser)
                } else {
                    self.isAuthenticated = false
                    self.currentUser = nil
                }
            }
        }
    }
    #endif
    
    // MARK: - Authentication Methods
    
    /// Main sign-in dispatcher
    public func signIn(with provider: AuthProviderType) async throws {
        self.isAuthenticating = true
        self.authErrorMessage = nil
        defer { self.isAuthenticating = false }
        
        guard isConfigured else {
            // Local stub mode
            try await Task.sleep(nanoseconds: 300_000_000)
            let stubUser = loadFallbackUser()
            self.currentUser = stubUser
            self.isAuthenticated = true
            return
        }
        
        #if canImport(FirebaseAuth)
        switch provider {
        case .email(let email, let password):
            try await signInWithEmail(email: email, password: password)
        case .anonymous:
            try await signInAnonymously()
        case .apple:
            try await signInWithAppleStub()
        case .google:
            try await signInWithGoogleStub()
        }
        #else
        self.currentUser = loadFallbackUser()
        self.isAuthenticated = true
        #endif
    }
    
    #if canImport(FirebaseAuth)
    /// Real Firebase Auth: Email & Password Sign In
    public func signInWithEmail(email: String, password: String) async throws {
        do {
            let authResult = try await Auth.auth().signIn(withEmail: email, password: password)
            await syncUserProfile(for: authResult.user)
        } catch {
            self.authErrorMessage = error.localizedDescription
            throw error
        }
    }
    
    /// Real Firebase Auth: Email & Password Sign Up
    public func signUpWithEmail(email: String, password: String, displayName: String) async throws {
        do {
            let authResult = try await Auth.auth().createUser(withEmail: email, password: password)
            let changeRequest = authResult.user.createProfileChangeRequest()
            changeRequest.displayName = displayName
            try await changeRequest.commitChanges()
            
            // Create user profile in Firestore
            let newUser = JoeUser(
                id: authResult.user.uid,
                displayName: displayName,
                email: email,
                locale: LocaleManager.shared.effectiveLanguageCode,
                isAdFree: false,
                friendIds: [],
                groupIds: [],
                createdAt: Date(),
                updatedAt: Date()
            )
            try await saveUserProfile(newUser)
            self.currentUser = newUser
            self.isAuthenticated = true
        } catch {
            self.authErrorMessage = error.localizedDescription
            throw error
        }
    }
    
    /// Real Firebase Auth: Anonymous Auth (useful for instant testing without registration)
    public func signInAnonymously() async throws {
        do {
            let authResult = try await Auth.auth().signInAnonymously()
            await syncUserProfile(for: authResult.user)
        } catch {
            self.authErrorMessage = error.localizedDescription
            throw error
        }
    }
    
    /// Sign in with Apple credential
    public func signInWithAppleCredential(idToken: String, rawNonce: String, fullName: PersonNameComponents?) async throws {
        let credential = OAuthProvider.appleCredential(withIDToken: idToken, rawNonce: rawNonce, fullName: fullName)
        do {
            let authResult = try await Auth.auth().signIn(with: credential)
            var displayName = authResult.user.displayName
            if let fullName = fullName, (displayName == nil || displayName?.isEmpty == true) {
                let formatter = PersonNameComponentsFormatter()
                displayName = formatter.string(from: fullName)
            }
            await syncUserProfile(for: authResult.user, overrideDisplayName: displayName)
        } catch {
            self.authErrorMessage = error.localizedDescription
            throw error
        }
    }
    
    /// Sign in with Apple stub when called from generic picker
    private func signInWithAppleStub() async throws {
        // When triggered without Apple UI payload, perform anonymous sign-in
        try await signInAnonymously()
    }
    
    /// Sign in with Google placeholder (ready for GoogleSignIn SDK or OAuth token)
    private func signInWithGoogleStub() async throws {
        // Note: Full GoogleSignIn-iOS SDK requires GoogleSignIn pod/framework.
        // Falls back to anonymous auth linked session for testability.
        try await signInAnonymously()
    }
    #endif
    
    /// Sign out
    public func signOut() {
        #if canImport(FirebaseAuth)
        if isConfigured {
            try? Auth.auth().signOut()
        }
        #endif
        self.isAuthenticated = false
        self.currentUser = nil
    }
    
    // MARK: - Firestore Profile Synchronization
    
    #if canImport(FirebaseAuth)
    private func syncUserProfile(for fbUser: FirebaseAuth.User, overrideDisplayName: String? = nil) async {
        let uid = fbUser.uid
        let displayName = overrideDisplayName ?? fbUser.displayName ?? fbUser.email?.components(separatedBy: "@").first ?? "JoeCalendar User"
        let email = fbUser.email
        
        #if canImport(FirebaseFirestore)
        if let firestore = db {
            let userDocRef = firestore.collection("users").document(uid)
            do {
                let snapshot = try await userDocRef.getDocument()
                if snapshot.exists, let data = snapshot.data() {
                    let user = parseJoeUser(id: uid, data: data)
                    self.currentUser = user
                    self.isAuthenticated = true
                    return
                } else {
                    // Initialize new user doc in Firestore
                    let newUser = JoeUser(
                        id: uid,
                        displayName: displayName,
                        email: email,
                        locale: LocaleManager.shared.effectiveLanguageCode,
                        isAdFree: false,
                        friendIds: [],
                        groupIds: [],
                        createdAt: Date(),
                        updatedAt: Date()
                    )
                    try await saveUserProfile(newUser)
                    self.currentUser = newUser
                    self.isAuthenticated = true
                    return
                }
            } catch {
                print("FirebaseService: Error fetching user doc from Firestore: \(error.localizedDescription)")
            }
        }
        #endif
        
        // Fallback user object if Firestore document read fails
        self.currentUser = JoeUser(
            id: uid,
            displayName: displayName,
            email: email,
            locale: LocaleManager.shared.effectiveLanguageCode,
            isAdFree: false
        )
        self.isAuthenticated = true
    }
    #endif
    
    // MARK: - Firestore Helpers for User State
    
    /// Saves or updates a user profile in Firestore `users/{uid}`
    public func saveUserProfile(_ user: JoeUser) async throws {
        #if canImport(FirebaseFirestore)
        guard let firestore = db else { return }
        
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
            "updatedAt": Timestamp(date: Date())
        ]
        
        try await docRef.setData(data, merge: true)
        #endif
    }
    
    /// Updates `groupIds` in `users/{uid}` to satisfy Firestore security rules
    public func updateUserGroupIds(uid: String, groupIds: [String]) async throws {
        #if canImport(FirebaseFirestore)
        guard let firestore = db else { return }
        let docRef = firestore.collection("users").document(uid)
        try await docRef.updateData([
            "groupIds": groupIds,
            "updatedAt": Timestamp(date: Date())
        ])
        #endif
    }
    
    /// Updates `friendIds` in `users/{uid}`
    public func updateUserFriendIds(uid: String, friendIds: [String]) async throws {
        #if canImport(FirebaseFirestore)
        guard let firestore = db else { return }
        let docRef = firestore.collection("users").document(uid)
        try await docRef.updateData([
            "friendIds": friendIds,
            "updatedAt": Timestamp(date: Date())
        ])
        #endif
    }
    
    /// Updates `followedLocalCalendarIds` in `users/{uid}`
    public func updateUserFollowedCalendars(uid: String, followedCalendarIds: [String]) async throws {
        #if canImport(FirebaseFirestore)
        guard let firestore = db else { return }
        let docRef = firestore.collection("users").document(uid)
        try await docRef.updateData([
            "followedLocalCalendarIds": followedCalendarIds,
            "updatedAt": Timestamp(date: Date())
        ])
        #endif
    }
    
    /// Updates `isAdFree` flag in `users/{uid}`
    public func updateUserAdFree(uid: String, isAdFree: Bool) async throws {
        #if canImport(FirebaseFirestore)
        guard let firestore = db else { return }
        let docRef = firestore.collection("users").document(uid)
        try await docRef.updateData([
            "isAdFree": isAdFree,
            "updatedAt": Timestamp(date: Date())
        ])
        #endif
    }
    
    // MARK: - Parsing Helpers
    
    #if canImport(FirebaseFirestore)
    public func parseJoeUser(id: String, data: [String: Any]) -> JoeUser {
        let displayName = data["displayName"] as? String ?? "User"
        let email = data["email"] as? String
        let avatarUrl = data["avatarUrl"] as? String
        let joeId = data["joeId"] as? String
        let locale = data["locale"] as? String ?? "en"
        let isAdFree = data["isAdFree"] as? Bool ?? false
        let friendIds = data["friendIds"] as? [String] ?? []
        let groupIds = data["groupIds"] as? [String] ?? []
        let linkedCalendars = data["linkedCalendars"] as? [String] ?? []
        let followedLocalCalendarIds = data["followedLocalCalendarIds"] as? [String] ?? []
        
        let createdAtTimestamp = data["createdAt"] as? Timestamp
        let updatedAtTimestamp = data["updatedAt"] as? Timestamp
        let createdAt = createdAtTimestamp?.dateValue() ?? Date()
        let updatedAt = updatedAtTimestamp?.dateValue() ?? Date()
        
        return JoeUser(
            id: id,
            displayName: displayName,
            email: email,
            avatarUrl: avatarUrl,
            joeId: joeId,
            locale: locale,
            isAdFree: isAdFree,
            friendIds: friendIds,
            groupIds: groupIds,
            linkedCalendars: linkedCalendars,
            followedLocalCalendarIds: followedLocalCalendarIds,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
    #endif
    
    // MARK: - Fallback Seed User
    
    private func loadFallbackUser() -> JoeUser {
        return JoeUser(
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
    }
}
