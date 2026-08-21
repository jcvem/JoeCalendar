//
//  MonthCalendarView.swift
//  JoeCalendar
//
//  Created for JoeCalendar Phase 0 Foundation & Extended for Phase 1 Core Calendar.
//  TimeTree-inspired Japanese calm calendar with view switcher (Month, Week, List),
//  source filters, pastel group tags, and unified event store integration.
//

import SwiftUI

public struct MonthCalendarView: View {
    @EnvironmentObject private var localeManager: LocaleManager
    @EnvironmentObject private var eventStore: EventStore
    @ObservedObject private var friendService = FriendService.shared
    
    @State private var displayedMonth: Date = Date()
    @State private var activeSheetMode: EventFormMode? = nil
    
    private let calendar = Calendar.current
    private var daysOfWeek: [String] {
        let formatter = DateFormatter()
        formatter.locale = localeManager.effectiveLocale
        if localeManager.effectiveLanguageCode.hasPrefix("zh") || localeManager.effectiveLanguageCode.hasPrefix("ja") {
            return formatter.veryShortStandaloneWeekdaySymbols ?? ["日", "一", "二", "三", "四", "五", "六"]
        } else {
            return formatter.shortStandaloneWeekdaySymbols.map { $0.uppercased() }
        }
    }
    
    public init() {}
    
    public var body: some View {
        NavigationStack {
            ZStack(alignment: .bottomTrailing) {
                AppColor.paper
                    .ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // Top Navigation & View Mode Selector Bar
                    topBar
                        .padding(.horizontal, AppSpacing.lg)
                        .padding(.top, AppSpacing.sm)
                        .padding(.bottom, AppSpacing.xs)
                    
                    // Source Filter Capsules (All, Joe, Apple, Google, Groups)
                    sourceFilterBar
                        .padding(.horizontal, AppSpacing.lg)
                        .padding(.bottom, AppSpacing.sm)
                    
                    // Active Group Filter Banner
                    if let groupId = eventStore.selectedGroupId, let group = friendService.userGroups.first(where: { $0.id == groupId }) {
                        groupFilterBanner(group: group)
                    }
                    
                    // Active View Content
                    switch eventStore.viewMode {
                    case .month:
                        monthContent
                    case .week:
                        WeekView()
                    case .list:
                        ListView()
                    }
                }
                
                // Floating Action Button (+ Add Event)
                Button(action: {
                    activeSheetMode = .new(defaultDate: eventStore.selectedDate)
                }) {
                    Image(systemName: "plus")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(width: 54, height: 54)
                        .background(AppColor.accent)
                        .clipShape(Circle())
                        .shadow(
                            color: AppColor.accent.opacity(0.35),
                            radius: 10,
                            x: 0,
                            y: 4
                        )
                }
                .padding(.trailing, AppSpacing.xl)
                .padding(.bottom, AppSpacing.xl)
            }
            .navigationBarHidden(true)
            .sheet(item: $activeSheetMode) { mode in
                EventFormSheet(mode: mode)
                    .environmentObject(localeManager)
                    .environmentObject(eventStore)
            }
        }
    }
    
    // MARK: - Top Bar
    
    private var topBar: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text(monthYearString(from: displayedMonth))
                    .font(AppTypography.title1())
                    .foregroundColor(AppColor.inkPrimary)
            }
            
            Spacer()
            
            // View Mode Switcher (Month / Week / List)
            HStack(spacing: 2) {
                ForEach(CalendarViewMode.allCases) { mode in
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            eventStore.viewMode = mode
                        }
                    }) {
                        Image(systemName: mode.iconName)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(eventStore.viewMode == mode ? .white : AppColor.inkSecondary)
                            .frame(width: 32, height: 32)
                            .background(eventStore.viewMode == mode ? AppColor.accent : Color.clear)
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(2)
            .background(AppColor.surfaceSubtle)
            .clipShape(Capsule())
            
            // Month navigation chevrons & Today button
            HStack(spacing: 4) {
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        displayedMonth = calendar.date(byAdding: .month, value: -1, to: displayedMonth) ?? displayedMonth
                    }
                }) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(AppColor.inkSecondary)
                        .frame(width: 30, height: 30)
                        .background(AppColor.surface)
                        .clipShape(Circle())
                }
                
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        eventStore.selectedDate = Date()
                        displayedMonth = Date()
                    }
                }) {
                    Text(loc: "calendar_today")
                        .font(AppTypography.captionMedium())
                        .foregroundColor(AppColor.accent)
                        .padding(.horizontal, AppSpacing.sm)
                        .padding(.vertical, 5)
                        .background(AppColor.accentLight)
                        .clipShape(Capsule())
                }
                
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        displayedMonth = calendar.date(byAdding: .month, value: 1, to: displayedMonth) ?? displayedMonth
                    }
                }) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(AppColor.inkSecondary)
                        .frame(width: 30, height: 30)
                        .background(AppColor.surface)
                        .clipShape(Circle())
                }
            }
        }
    }
    
    // MARK: - Source Filter Bar
    
    private var sourceFilterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: AppSpacing.xs) {
                // All Filter
                Button(action: {
                    eventStore.selectedSourceFilter = nil
                    eventStore.clearGroupFilter()
                }) {
                    Text(loc: "calendar_filter_all")
                }
                .buttonStyle(TimeTreeCapsuleButtonStyle(isSelected: eventStore.selectedSourceFilter == nil && eventStore.selectedGroupId == nil))
                
                // Joe Filter
                Button(action: {
                    toggleFilter(.joe)
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: CalendarType.joe.iconName)
                        Text(loc: CalendarType.joe.displayNameKey)
                    }
                }
                .buttonStyle(TimeTreeCapsuleButtonStyle(isSelected: eventStore.selectedSourceFilter == .joe && eventStore.selectedGroupId == nil))
                
                // Apple Device Filter
                Button(action: {
                    toggleFilter(.device)
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: CalendarType.device.iconName)
                        Text(loc: CalendarType.device.displayNameKey)
                    }
                }
                .buttonStyle(TimeTreeCapsuleButtonStyle(isSelected: eventStore.selectedSourceFilter == .device && eventStore.selectedGroupId == nil))
                
                // Google Filter
                Button(action: {
                    toggleFilter(.google)
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: CalendarType.google.iconName)
                        Text(loc: CalendarType.google.displayNameKey)
                    }
                }
                .buttonStyle(TimeTreeCapsuleButtonStyle(isSelected: eventStore.selectedSourceFilter == .google && eventStore.selectedGroupId == nil))
                
                // User Groups Filters
                ForEach(friendService.userGroups) { group in
                    let isSelected = eventStore.selectedGroupId == group.id
                    Button(action: {
                        if isSelected {
                            eventStore.clearGroupFilter()
                        } else {
                            eventStore.selectedSourceFilter = nil
                            eventStore.selectGroupFilter(group.id)
                        }
                    }) {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(Color(hexString: group.colorHex))
                                .frame(width: 7, height: 7)
                            Text(group.name)
                        }
                    }
                    .buttonStyle(TimeTreeCapsuleButtonStyle(isSelected: isSelected))
                }
            }
        }
    }
    
    private func toggleFilter(_ type: CalendarType) {
        eventStore.clearGroupFilter()
        if eventStore.selectedSourceFilter == type {
            eventStore.selectedSourceFilter = nil
        } else {
            eventStore.selectedSourceFilter = type
        }
    }
    
    private func groupFilterBanner(group: FriendGroup) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(Color(hexString: group.colorHex))
                .frame(width: 8, height: 8)
            
            Text(group.name)
                .font(AppTypography.captionMedium())
                .foregroundColor(AppColor.inkPrimary)
            
            Text(loc: "calendar_filter_active")
                .font(AppTypography.caption())
                .foregroundColor(AppColor.inkSecondary)
            
            Spacer()
            
            Button(action: {
                eventStore.clearGroupFilter()
            }) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(AppColor.inkTertiary)
                    .font(.system(size: 14))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, AppSpacing.md)
        .padding(.vertical, 6)
        .background(Color(hexString: group.colorHex).opacity(0.16))
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.sm, style: .continuous))
        .padding(.horizontal, AppSpacing.lg)
        .padding(.bottom, AppSpacing.xs)
    }
    
    // MARK: - Month Content
    
    private var monthContent: some View {
        VStack(spacing: 0) {
            // Days of week bar
            daysOfWeekHeader
                .padding(.horizontal, AppSpacing.sm)
                .padding(.bottom, AppSpacing.xs)
            
            // Month Grid
            monthGrid
                .padding(.horizontal, AppSpacing.sm)
            
            Divider()
                .background(AppColor.inkBorder)
                .padding(.top, AppSpacing.sm)
            
            // Selected Day's Event List
            dayEventList
        }
    }
    
    // MARK: - Days of Week Header
    
    private var daysOfWeekHeader: some View {
        HStack(spacing: 0) {
            ForEach(0..<7) { index in
                Text(daysOfWeek[index])
                    .font(AppTypography.captionMedium())
                    .foregroundColor(
                        index == 0 ? AppColor.destructive.opacity(0.8) :
                        (index == 6 ? AppColor.accent : AppColor.inkTertiary)
                    )
                    .frame(maxWidth: .infinity)
            }
        }
    }
    
    // MARK: - Month Grid
    
    private var monthGrid: some View {
        let daysInMonth = getDaysInMonthGrid(for: displayedMonth)
        let rows = daysInMonth.chunked(into: 7)
        
        return VStack(spacing: 4) {
            ForEach(0..<rows.count, id: \.self) { rowIndex in
                HStack(spacing: 4) {
                    ForEach(rows[rowIndex], id: \.self) { date in
                        dayCell(for: date)
                    }
                }
            }
        }
    }
    
    private func dayCell(for date: Date) -> some View {
        let isCurrentMonth = calendar.isDate(date, equalTo: displayedMonth, toGranularity: .month)
        let isSelected = calendar.isDate(date, inSameDayAs: eventStore.selectedDate)
        let isToday = calendar.isDateInToday(date)
        let dayEvents = eventStore.events(for: date)
        
        return Button(action: {
            eventStore.selectedDate = date
        }) {
            VStack(spacing: 2) {
                ZStack {
                    if isSelected {
                        Circle()
                            .fill(AppColor.accent)
                            .frame(width: 28, height: 28)
                    } else if isToday {
                        Circle()
                            .stroke(AppColor.accent, lineWidth: 1.5)
                            .frame(width: 28, height: 28)
                    }
                    
                    Text("\(calendar.component(.day, from: date))")
                        .font(AppTypography.footnote())
                        .fontWeight(isSelected || isToday ? .semibold : .regular)
                        .foregroundColor(
                            isSelected ? .white :
                            (!isCurrentMonth ? AppColor.inkTertiary.opacity(0.4) :
                            (isToday ? AppColor.accent : AppColor.inkPrimary))
                        )
                }
                
                // Event indicators (up to 3 pastel dots)
                HStack(spacing: 2) {
                    ForEach(dayEvents.prefix(3)) { event in
                        Circle()
                            .fill(event.color)
                            .frame(width: 5, height: 5)
                    }
                }
                .frame(height: 6)
            }
            .frame(maxWidth: .infinity, minHeight: 40)
            .background(
                RoundedRectangle(cornerRadius: AppRadius.sm)
                    .fill(isSelected ? AppColor.surfaceSubtle : Color.clear)
            )
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Selected Day Event List
    
    private var dayEventList: some View {
        let selectedDayEvents = eventStore.events(for: eventStore.selectedDate)
        
        return ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.md) {
                HStack {
                    Text(selectedDateFormatted)
                        .font(AppTypography.headline())
                        .foregroundColor(AppColor.inkSecondary)
                    
                    Spacer()
                    
                    Text("\(selectedDayEvents.count)")
                        .font(AppTypography.captionMedium())
                        .foregroundColor(AppColor.inkSecondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(AppColor.surfaceSubtle)
                        .clipShape(Capsule())
                }
                .padding(.horizontal, AppSpacing.lg)
                .padding(.top, AppSpacing.md)
                
                if selectedDayEvents.isEmpty {
                    VStack(spacing: AppSpacing.sm) {
                        Image(systemName: "calendar.badge.clock")
                            .font(.system(size: 32))
                            .foregroundColor(AppColor.inkTertiary)
                            .padding(.top, AppSpacing.xl)
                        
                        Text(loc: "calendar_no_events_selected")
                            .font(AppTypography.subheadline())
                            .foregroundColor(AppColor.inkTertiary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, AppSpacing.xl)
                } else {
                    VStack(spacing: AppSpacing.sm) {
                        ForEach(selectedDayEvents) { event in
                            Button(action: {
                                activeSheetMode = .edit(event: event)
                            }) {
                                eventCard(event: event)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, AppSpacing.lg)
                }
            }
            .padding(.bottom, 80)
        }
    }
    
    private func eventCard(event: CalendarEvent) -> some View {
        HStack(spacing: AppSpacing.md) {
            // Left color bar
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
                    
                    // Source / Visibility Badge
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
                
                HStack(spacing: AppSpacing.md) {
                    if event.isAllDay {
                        Text(loc: "calendar_all_day")
                            .font(AppTypography.caption())
                            .foregroundColor(AppColor.inkSecondary)
                    } else {
                        Text("\(timeString(from: event.startDate)) - \(timeString(from: event.endDate))")
                            .font(AppTypography.caption())
                            .foregroundColor(AppColor.inkSecondary)
                    }
                    
                    if let location = event.location, !location.isEmpty {
                        HStack(spacing: 2) {
                            Image(systemName: "mappin.and.ellipse")
                                .font(.system(size: 10))
                            Text(location)
                                .font(AppTypography.caption())
                                .lineLimit(1)
                        }
                        .foregroundColor(AppColor.inkTertiary)
                    }
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
    
    // MARK: - Helpers
    
    private func monthYearString(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = localeManager.effectiveLocale
        formatter.dateFormat = "LLLL yyyy"
        return formatter.string(from: date).capitalized
    }
    
    private var selectedDateFormatted: String {
        let formatter = DateFormatter()
        formatter.locale = localeManager.effectiveLocale
        formatter.dateStyle = .full
        return formatter.string(from: eventStore.selectedDate)
    }
    
    private func timeString(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = localeManager.effectiveLocale
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
    
    private func getDaysInMonthGrid(for month: Date) -> [Date] {
        guard let monthInterval = calendar.dateInterval(of: .month, for: month),
              let firstDayOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: monthInterval.start)) else {
            return []
        }
        
        let weekday = calendar.component(.weekday, from: firstDayOfMonth) - 1 // 0 for Sunday
        let startDate = calendar.date(byAdding: .day, value: -weekday, to: firstDayOfMonth) ?? firstDayOfMonth
        
        var days: [Date] = []
        for i in 0..<35 {
            if let date = calendar.date(byAdding: .day, value: i, to: startDate) {
                days.append(date)
            }
        }
        return days
    }
}

// MARK: - Array Chunk Helper

private extension Array {
    func chunked(into size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}
