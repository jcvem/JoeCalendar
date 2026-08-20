//
//  MonthCalendarView.swift
//  JoeCalendar
//
//  Created for JoeCalendar Phase 0 Foundation.
//  TimeTree-inspired Japanese calm month view with high whitespace,
//  pastel group tags, and smooth date selection.
//

import SwiftUI

public struct MonthCalendarView: View {
    @EnvironmentObject private var localeManager: LocaleManager
    @State private var selectedDate: Date = Date()
    @State private var displayedMonth: Date = Date()
    @State private var isAddEventPresented: Bool = false
    
    // Sample events for Phase 0 demonstration
    @State private var events: [CalendarEvent] = [
        CalendarEvent(
            title: "Morning Pickleball",
            startDate: Calendar.current.date(bySettingHour: 7, minute: 30, second: 0, of: Date()) ?? Date(),
            endDate: Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: Date()) ?? Date(),
            location: "Tokyo Sports Dome",
            notes: "Bring racket and extra balls",
            calendarType: .joe,
            visibility: EventVisibility(type: .group, groupIds: ["workout_friends"]),
            colorHex: AppColor.GroupPastel.sage.hexString
        ),
        CalendarEvent(
            title: "Design System Review",
            startDate: Calendar.current.date(bySettingHour: 14, minute: 0, second: 0, of: Date()) ?? Date(),
            endDate: Calendar.current.date(bySettingHour: 15, minute: 30, second: 0, of: Date()) ?? Date(),
            location: "Online / Meet",
            notes: "Review Japanese-calm tokens and TimeTree alignment",
            calendarType: .google,
            visibility: EventVisibility(type: .private),
            colorHex: AppColor.GroupPastel.mist.hexString
        ),
        CalendarEvent(
            title: "Omotesando Art Exhibition",
            startDate: Calendar.current.date(byAdding: .day, value: 2, to: Date()) ?? Date(),
            endDate: Calendar.current.date(byAdding: .day, value: 2, to: Date()) ?? Date(),
            isAllDay: true,
            location: "Mori Arts Center",
            calendarType: .local,
            visibility: EventVisibility(type: .public),
            colorHex: AppColor.GroupPastel.sakura.hexString
        )
    ]
    
    private let calendar = Calendar.current
    private let daysOfWeek = ["SUN", "MON", "TUE", "WED", "THU", "FRI", "SAT"]
    
    public init() {}
    
    public var body: some View {
        NavigationStack {
            ZStack(alignment: .bottomTrailing) {
                AppColor.paper
                    .ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // Header Bar
                    headerBar
                        .padding(.horizontal, AppSpacing.lg)
                        .padding(.top, AppSpacing.sm)
                        .padding(.bottom, AppSpacing.md)
                    
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
                
                // Floating Action Button (+ Add Event)
                Button(action: {
                    isAddEventPresented = true
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
            .sheet(isPresented: $isAddEventPresented) {
                DayDetailSheet(
                    selectedDate: selectedDate,
                    onSave: { newEvent in
                        events.append(newEvent)
                    }
                )
                .environmentObject(localeManager)
            }
        }
    }
    
    // MARK: - Header Bar
    
    private var headerBar: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text(monthYearString(from: displayedMonth))
                    .font(AppTypography.title1())
                    .foregroundColor(AppColor.inkPrimary)
            }
            
            Spacer()
            
            HStack(spacing: AppSpacing.sm) {
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        displayedMonth = calendar.date(byAdding: .month, value: -1, to: displayedMonth) ?? displayedMonth
                    }
                }) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(AppColor.inkSecondary)
                        .frame(width: 32, height: 32)
                        .background(AppColor.surface)
                        .clipShape(Circle())
                }
                
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selectedDate = Date()
                        displayedMonth = Date()
                    }
                }) {
                    Text(loc: "calendar_today")
                        .font(AppTypography.subheadline())
                        .foregroundColor(AppColor.accent)
                        .padding(.horizontal, AppSpacing.md)
                        .padding(.vertical, 6)
                        .background(AppColor.accentLight)
                        .clipShape(Capsule())
                }
                
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        displayedMonth = calendar.date(byAdding: .month, value: 1, to: displayedMonth) ?? displayedMonth
                    }
                }) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(AppColor.inkSecondary)
                        .frame(width: 32, height: 32)
                        .background(AppColor.surface)
                        .clipShape(Circle())
                }
            }
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
        let isSelected = calendar.isDate(date, inSameDayAs: selectedDate)
        let isToday = calendar.isDateInToday(date)
        let dayEvents = eventsForDate(date)
        
        return Button(action: {
            selectedDate = date
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
                            (!isCurrentMonth ? AppColor.inkTertiary.opacity(0.5) :
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
        let selectedDayEvents = eventsForDate(selectedDate)
        
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
                            eventCard(event: event)
                        }
                    }
                    .padding(.horizontal, AppSpacing.lg)
                }
            }
            .padding(.bottom, 80) // Leave space for floating action button
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
                    
                    Spacer()
                    
                    // Visibility Badge
                    HStack(spacing: 3) {
                        Image(systemName: event.visibility.type == .group ? "person.2.fill" : (event.visibility.type == .public ? "globe" : "lock.fill"))
                            .font(.system(size: 9))
                        Text(loc: event.visibility.type.displayNameKey)
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
    
    private func eventsForDate(_ date: Date) -> [CalendarEvent] {
        events.filter { calendar.isDate($0.startDate, inSameDayAs: date) }
    }
    
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
        return formatter.string(from: selectedDate)
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
