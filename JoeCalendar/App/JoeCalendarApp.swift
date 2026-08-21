//
//  JoeCalendarApp.swift
//  JoeCalendar
//
//  Created for JoeCalendar Phase 0 Foundation.
//  Main application entry point.
//

import SwiftUI

#if canImport(GoogleSignIn)
import GoogleSignIn
#endif

@main
struct JoeCalendarApp: App {
    @StateObject private var themeManager = ThemeManager.shared
    @StateObject private var localeManager = LocaleManager.shared
    @StateObject private var firebaseService = FirebaseService.shared
    @StateObject private var googleService = GoogleCalendarService.shared
    @StateObject private var eventStore = EventStore.shared
    @StateObject private var subscriptionService = SubscriptionService.shared
    @StateObject private var discoverService = DiscoverService.shared
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(themeManager)
                .environmentObject(localeManager)
                .environmentObject(firebaseService)
                .environmentObject(googleService)
                .environmentObject(eventStore)
                .environmentObject(subscriptionService)
                .environmentObject(discoverService)
                .environment(\.locale, localeManager.effectiveLocale)
                .preferredColorScheme(themeManager.preferredScheme)
                .onOpenURL { url in
                    #if canImport(GoogleSignIn)
                    _ = GIDSignIn.sharedInstance.handle(url)
                    #endif
                }
        }
    }
}
