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
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(localeManager)
                .environmentObject(firebaseService)
                .environment(\.locale, localeManager.effectiveLocale)
        }
    }
}
