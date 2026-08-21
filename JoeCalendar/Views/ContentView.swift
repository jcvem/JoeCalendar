//
//  ContentView.swift
//  JoeCalendar
//
//  Created for JoeCalendar Phase 0 Foundation.
//  Root TabView container styled with TimeTree-inspired Japanese calm tokens.
//

import SwiftUI

public struct ContentView: View {
    @EnvironmentObject private var localeManager: LocaleManager
    @State private var selectedTab: TabItem = .calendar
    
    public enum TabItem: Int {
        case calendar
        case friends
        case discover
        case settings
    }
    
    public init() {}
    
    public var body: some View {
        TabView(selection: $selectedTab) {
            MonthCalendarView()
                .tabItem {
                    Label(
                        title: { Text(loc: "tab_calendar") },
                        icon: { Image(systemName: "calendar") }
                    )
                }
                .tag(TabItem.calendar)
            
            FriendsView()
                .tabItem {
                    Label(
                        title: { Text(loc: "tab_friends") },
                        icon: { Image(systemName: "person.2.fill") }
                    )
                }
                .tag(TabItem.friends)
            
            DiscoverView()
                .tabItem {
                    Label(
                        title: { Text(loc: "tab_discover") },
                        icon: { Image(systemName: "sparkles") }
                    )
                }
                .tag(TabItem.discover)
            
            SettingsView()
                .tabItem {
                    Label(
                        title: { Text(loc: "tab_settings") },
                        icon: { Image(systemName: "gearshape.fill") }
                    )
                }
                .tag(TabItem.settings)
        }
        .tint(AppColor.accent)
        .environment(\.locale, localeManager.effectiveLocale)
        .id("\(localeManager.selectedLanguage.rawValue)_\(localeManager.effectiveLanguageCode)")
    }
}
