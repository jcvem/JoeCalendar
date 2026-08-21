//
//  ListView.swift
//  JoeCalendar
//
//  Created for JoeCalendar Phase 1 Core Calendar.
//  TimeTree-inspired Japanese agenda list view grouped chronologically
//  by date with search, source badges, and event detail sheets.
//

import SwiftUI

public struct ListView: View {
    @EnvironmentObject private var localeManager: LocaleManager
    @EnvironmentObject private var eventStore: EventStore
    
    @State private var activeSheetMode: EventFormMode? = nil
    
    private let calendar = Calendar.current
    
    public init() {}
    
    public var body: some View {
        VStack(spacing: 0) {
            // Search Bar
            searchBar
                .padding(.horizontal, AppSpacing.lg)
                .padding(.top, AppSpacing.xs)
                .padding(.bottom, AppSpacing.sm)
            
            Divider()
                .background(AppColor.inkBorder)
            
            // Grouped Event List
            let grouped = eventStore.upcomingEvents(from: Date(), daysAhead: 60)
            
            if grouped.isEmpty {
                emptyStateView
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: AppSpacing.lg) {
                        ForEach(grouped, id: \.key) { group in
                            daySection(date: group.key, events: group.events)
                        }
                    }
                    .padding(.horizontal, AppSpacing.lg)
                    .padding(.vertical, AppSpacing.md)
                    .padding(.bottom, 80)
                }
            }
        }
        .background(AppColor.paper)
        .sheet(item: $activeSheetMode) { mode in
            EventFormSheet(mode: mode)
                .environmentObject(localeManager)
                .environmentObject(eventStore)
        }
    }
    
    // MARK: - Search Bar
    
    private var searchBar: some View {
        HStack(spacing: AppSpacing.sm) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(AppColor.inkTertiary)
            
            TextField(
                "calendar_search_placeholder".localized(),
                text: $eventStore.searchQuery
            )
            .font(AppTypography.body())
            .foregroundColor(AppColor.inkPrimary)
            
            if !eventStore.searchQuery.isEmpty {
                Button(action: {
                    eventStore.searchQuery = ""
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(AppColor.inkTertiary)
                }
            }
        }
        .padding(.horizontal, AppSpacing.md)
        .padding(.vertical, AppSpacing.sm)
        .background(AppColor.surface)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous)
                .stroke(AppColor.inkBorder, lineWidth: 1)
        )
    }
    
    // MARK: - Day Section
    
    private func daySection(date: Date, events: [CalendarEvent]) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            // Day Header
            HStack(spacing: AppSpacing.sm) {
                Text(dayHeaderString(from: date))
                    .font(AppTypography.headline())
                    .foregroundColor(calendar.isDateInToday(date) ? AppColor.accent : AppColor.inkPrimary)
                
                if calendar.isDateInToday(date) {
                    Text(loc: "calendar_today")
                        .font(AppTypography.captionMedium())
                        .foregroundColor(AppColor.accent)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(AppColor.accentLight)
                        .clipShape(Capsule())
                }
                
                Spacer()
                
                Text("\(events.count)")
                    .font(AppTypography.captionMedium())
                    .foregroundColor(AppColor.inkSecondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(AppColor.surfaceSubtle)
                    .clipShape(Capsule())
            }
            .padding(.top, AppSpacing.xs)
            
            // Events in this day
            VStack(spacing: AppSpacing.sm) {
                ForEach(events) { event in
                    eventRowCard(event: event)
                }
            }
        }
    }
    
    // MARK: - Event Row Card
    
    private func eventRowCard(event: CalendarEvent) -> some View {
        Button(action: {
            activeSheetMode = .edit(event: event)
        }) {
            HStack(spacing: AppSpacing.md) {
                // Color Bar
                RoundedRectangle(cornerRadius: 2)
                    .fill(event.color)
                    .frame(width: 4)
                
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(event.title)
                            .font(AppTypography.headline())
                            .foregroundColor(AppColor.inkPrimary)
                            .lineLimit(1)
                        
                        Spacer()
                        
                        // Source Badge
                        HStack(spacing: 3) {
                            Image(systemName: event.calendarType.iconName)
                                .font(.system(size: 9))
                            Text(loc: event.calendarType.displayNameKey)
                                .font(AppTypography.caption())
                        }
                        .foregroundColor(AppColor.inkSecondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(AppColor.surfaceSubtle)
                        .clipShape(Capsule())
                    }
                    
                    // Time and Location
                    HStack(spacing: AppSpacing.md) {
                        HStack(spacing: 4) {
                            Image(systemName: "clock")
                                .font(.system(size: 10))
                            if event.isAllDay {
                                Text(loc: "calendar_all_day")
                                    .font(AppTypography.caption())
                            } else {
                                Text("\(timeString(from: event.startDate)) - \(timeString(from: event.endDate))")
                                    .font(AppTypography.caption())
                            }
                        }
                        .foregroundColor(AppColor.inkSecondary)
                        
                        if let loc = event.location, !loc.isEmpty {
                            HStack(spacing: 3) {
                                Image(systemName: "mappin.and.ellipse")
                                    .font(.system(size: 10))
                                Text(loc)
                                    .font(AppTypography.caption())
                                    .lineLimit(1)
                            }
                            .foregroundColor(AppColor.inkTertiary)
                        }
                        
                        Spacer()
                        
                        if event.recurrence != .none {
                            Image(systemName: "repeat")
                                .font(.system(size: 10))
                                .foregroundColor(AppColor.inkTertiary)
                        }
                    }
                    
                    if let notes = event.notes, !notes.isEmpty {
                        Text(notes)
                            .font(AppTypography.footnote())
                            .foregroundColor(AppColor.inkSecondary)
                            .lineLimit(2)
                            .padding(.top, 2)
                    }
                }
                .padding(.vertical, AppSpacing.sm)
                .padding(.trailing, AppSpacing.sm)
            }
            .padding(.horizontal, AppSpacing.md)
            .background(AppColor.surface)
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous)
                    .stroke(AppColor.inkBorder, lineWidth: 1)
            )
            .shadow(
                color: AppShadow.subtle.color,
                radius: AppShadow.subtle.radius,
                x: AppShadow.subtle.x,
                y: AppShadow.subtle.y
            )
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Empty State
    
    private var emptyStateView: some View {
        VStack(spacing: AppSpacing.md) {
            Spacer()
            
            Image(systemName: "calendar.badge.exclamationmark")
                .font(.system(size: 44))
                .foregroundColor(AppColor.inkTertiary)
            
            Text(loc: "calendar_no_events_found")
                .font(AppTypography.title3())
                .foregroundColor(AppColor.inkPrimary)
            
            Text(loc: "calendar_no_events_hint")
                .font(AppTypography.subheadline())
                .foregroundColor(AppColor.inkSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, AppSpacing.xxl)
            
            Button(action: {
                activeSheetMode = .new(defaultDate: Date())
            }) {
                HStack(spacing: 6) {
                    Image(systemName: "plus")
                    Text(loc: "calendar_add_event")
                }
            }
            .buttonStyle(TimeTreePrimaryButtonStyle(isCompact: true))
            .padding(.top, AppSpacing.sm)
            
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
    
    // MARK: - Helpers
    
    private func dayHeaderString(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = localeManager.effectiveLocale
        formatter.dateFormat = "EEEE, MMM d"
        return formatter.string(from: date)
    }
    
    private func timeString(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = localeManager.effectiveLocale
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}
