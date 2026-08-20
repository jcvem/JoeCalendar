//
//  JoeCalendarApp.swift
//  JoeCalendar
//
//  Created for JoeCalendar Phase 0 Foundation.
//  Main application entry point.
//

import SwiftUI

@main
struct JoeCalendarApp: App {
    @StateObject private var localeManager = LocaleManager.shared
    @StateObject private var firebaseService = FirebaseService.shared
    @StateObject private var eventStore = EventStore.shared
    @StateObject private var subscriptionService = SubscriptionService.shared
    @StateObject private var discoverService = DiscoverService.shared
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(localeManager)
                .environmentObject(firebaseService)
                .environmentObject(eventStore)
                .environmentObject(subscriptionService)
                .environmentObject(discoverService)
                .environment(\.locale, localeManager.effectiveLocale)
        }
    }
}
