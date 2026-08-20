//
//  WeekView.swift
//  JoeCalendar
//
//  Created for JoeCalendar Phase 1 Core Calendar.
//  TimeTree-inspired horizontal 7-day strip + hourly schedule view
//  with pastel group color bars, all-day banner, and live time marker.
//

import SwiftUI

public struct WeekView: View {
    @EnvironmentObject private var localeManager: LocaleManager
    @EnvironmentObject private var eventStore: EventStore
    
    @State private var selectedDate: Date = Date()
    @State private var startOfWeekDate: Date = Date()
    @State private var activeSheetMode: EventFormMode? = nil
    
    private let calendar = Calendar.current
    private let hours = Array(0...23)
    private let hourHeight: CGFloat = 60.0
    
    public init() {}
    
    public var body: some View {
        VStack(spacing: 0) {
            // Week Header & 7-Day Strip
            weekHeaderBar
                .padding(.horizontal, AppSpacing.lg)
                .padding(.top, AppSpacing.xs)
                .padding(.bottom, AppSpacing.sm)
            
            sevenDayStrip
                .padding(.horizontal, AppSpacing.sm)
                .padding(.bottom, AppSpacing.sm)
            
            Divider()
                .background(AppColor.inkBorder)
            
            // All-Day Events Section (if any for selected date)
            allDaySection
            
            // Hourly Timeline ScrollView
            hourlyTimelineView
        }
        .background(AppColor.paper)
        .onAppear {
            updateStartOfWeek(for: eventStore.selectedDate)
            selectedDate = eventStore.selectedDate
        }
        .onChange(of: eventStore.selectedDate) { _, newDate in
            selectedDate = newDate
            updateStartOfWeek(for: newDate)
        }
        .sheet(item: Binding<IdentifiableEventFormMode?>(
            get: { activeSheetMode.map { IdentifiableEventFormMode(mode: $0) } },
            set: { activeSheetMode = $0?.mode }
        )) { item in
            EventFormSheet(mode: item.mode)
                .environmentObject(localeManager)
                .environmentObject(eventStore)
        }
    }
    
    // MARK: - Week Header
    
    private var weekHeaderBar: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(weekRangeString)
                    .font(AppTypography.title2())
                    .foregroundColor(AppColor.inkPrimary)
            }
            
            Spacer()
            
            HStack(spacing: AppSpacing.sm) {
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        shiftWeek(by: -1)
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
                        selectedDate = Date()
                        eventStore.selectedDate = Date()
                        updateStartOfWeek(for: Date())
                    }
                }) {
                    Text(loc: "calendar_today")
                        .font(AppTypography.captionMedium())
                        .foregroundColor(AppColor.accent)
                        .padding(.horizontal, AppSpacing.md)
                        .padding(.vertical, 5)
                        .background(AppColor.accentLight)
                        .clipShape(Capsule())
                }
                
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        shiftWeek(by: 1)
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
    
    // MARK: - 7-Day Strip
    
    private var sevenDayStrip: some View {
        let days = currentWeekDays
        
        return HStack(spacing: 4) {
            ForEach(days, id: \.self) { day in
                let isSelected = calendar.isDate(day, inSameDayAs: selectedDate)
                let isToday = calendar.isDateInToday(day)
                let dayEvents = eventStore.events(for: day)
                let weekdayIndex = calendar.component(.weekday, from: day) - 1 // 0=Sun, 6=Sat
                
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        selectedDate = day
                        eventStore.selectedDate = day
                    }
                }) {
                    VStack(spacing: 4) {
                        Text(shortWeekdayName(for: day))
                            .font(AppTypography.caption())
                            .foregroundColor(
                                weekdayIndex == 0 ? AppColor.destructive.opacity(0.8) :
                                (weekdayIndex == 6 ? AppColor.accent : AppColor.inkSecondary)
                            )
                        
                        ZStack {
                            if isSelected {
                                Circle()
                                    .fill(AppColor.accent)
                                    .frame(width: 30, height: 30)
                            } else if isToday {
                                Circle()
                                    .stroke(AppColor.accent, lineWidth: 1.5)
                                    .frame(width: 30, height: 30)
                            }
                            
                            Text("\(calendar.component(.day, from: day))")
                                .font(AppTypography.subheadline())
                                .fontWeight(isSelected || isToday ? .bold : .regular)
                                .foregroundColor(
                                    isSelected ? .white :
                                    (isToday ? AppColor.accent : AppColor.inkPrimary)
                                )
                        }
                        
                        // Event Dots
                        HStack(spacing: 2) {
                            ForEach(dayEvents.prefix(3)) { ev in
                                Circle()
                                    .fill(ev.color)
                                    .frame(width: 4, height: 4)
                            }
                        }
                        .frame(height: 5)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous)
                            .fill(isSelected ? AppColor.surfaceSubtle : Color.clear)
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }
    
    // MARK: - All-Day Section
    
    @ViewBuilder
    private var allDaySection: some View {
        let allDayEvents = eventStore.events(for: selectedDate).filter { $0.isAllDay }
        if !allDayEvents.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(loc: "calendar_all_day")
                        .font(AppTypography.captionMedium())
                        .foregroundColor(AppColor.inkSecondary)
                    Spacer()
                }
                .padding(.horizontal, AppSpacing.lg)
                .padding(.top, AppSpacing.xs)
                
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: AppSpacing.sm) {
                        ForEach(allDayEvents) { event in
                            Button(action: {
                                activeSheetMode = .edit(event: event)
                            }) {
                                HStack(spacing: 6) {
                                    Circle()
                                        .fill(event.color)
                                        .frame(width: 8, height: 8)
                                    Text(event.title)
                                        .font(AppTypography.footnote())
                                        .foregroundColor(AppColor.inkPrimary)
                                        .lineLimit(1)
                                }
                                .padding(.horizontal, AppSpacing.md)
                                .padding(.vertical, 6)
                                .background(AppColor.surface)
                                .clipShape(RoundedRectangle(cornerRadius: AppRadius.sm, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: AppRadius.sm, style: .continuous)
                                        .stroke(event.color.opacity(0.4), lineWidth: 1)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, AppSpacing.lg)
                    .padding(.bottom, AppSpacing.xs)
                }
                
                Divider()
                    .background(AppColor.inkBorder)
            }
            .background(AppColor.surfaceSubtle.opacity(0.5))
        }
    }
    
    // MARK: - Hourly Timeline
    
    private var hourlyTimelineView: some View {
        let timedEvents = eventStore.events(for: selectedDate).filter { !$0.isAllDay }
        
        return ScrollViewReader { proxy in
            ScrollView {
                ZStack(alignment: .topLeading) {
                    // Hourly Background Grid
                    VStack(spacing: 0) {
                        ForEach(hours, id: \.self) { hour in
                            HStack(alignment: .top, spacing: AppSpacing.md) {
                                Text(String(format: "%02d:00", hour))
                                    .font(AppTypography.caption())
                                    .foregroundColor(AppColor.inkTertiary)
                                    .frame(width: 44, alignment: .trailing)
                                
                                VStack(spacing: 0) {
                                    Divider()
                                        .background(AppColor.inkBorderSubtle)
                                    Spacer()
                                }
                            }
                            .frame(height: hourHeight)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                if let slotDate = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: selectedDate) {
                                    activeSheetMode = .new(defaultDate: slotDate)
                                }
                            }
                            .id(hour)
                        }
                    }
                    
                    // Timed Event Cards Overlay
                    ForEach(timedEvents) { event in
                        let (topOffset, height) = calculatePosition(for: event)
                        
                        Button(action: {
                            activeSheetMode = .edit(event: event)
                        }) {
                            HStack(spacing: 6) {
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(event.color)
                                    .frame(width: 3)
                                
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(event.title)
                                        .font(AppTypography.footnote())
                                        .fontWeight(.semibold)
                                        .foregroundColor(AppColor.inkPrimary)
                                        .lineLimit(1)
                                    
                                    if height > 40 {
                                        Text("\(timeString(from: event.startDate)) - \(timeString(from: event.endDate))")
                                            .font(AppTypography.caption())
                                            .foregroundColor(AppColor.inkSecondary)
                                            .lineLimit(1)
                                    }
                                }
                                
                                Spacer()
                            }
                            .padding(.horizontal, 6)
                            .padding(.vertical, 4)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .frame(height: max(height, 28))
                            .background(event.color.opacity(0.18))
                            .clipShape(RoundedRectangle(cornerRadius: AppRadius.sm, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: AppRadius.sm, style: .continuous)
                                    .stroke(event.color.opacity(0.4), lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                        .padding(.leading, 56)
                        .padding(.trailing, AppSpacing.md)
                        .offset(y: topOffset)
                    }
                    
                    // Live Current Time Indicator
                    if calendar.isDateInToday(selectedDate) {
                        let nowOffset = calculateNowOffset()
                        HStack(spacing: 0) {
                            Circle()
                                .fill(AppColor.destructive)
                                .frame(width: 8, height: 8)
                            Rectangle()
                                .fill(AppColor.destructive)
                                .frame(height: 1.5)
                        }
                        .padding(.leading, 48)
                        .offset(y: nowOffset - 4)
                    }
                }
                .padding(.top, AppSpacing.sm)
                .padding(.bottom, 80)
            }
            .onAppear {
                let currentHour = calendar.component(.hour, from: Date())
                let targetHour = max(0, currentHour - 1)
                proxy.scrollTo(targetHour, anchor: .top)
            }
        }
    }
    
    // MARK: - Helpers
    
    private var currentWeekDays: [Date] {
        var days: [Date] = []
        for i in 0..<7 {
            if let d = calendar.date(byAdding: .day, value: i, to: startOfWeekDate) {
                days.append(d)
            }
        }
        return days
    }
    
    private func updateStartOfWeek(for date: Date) {
        let weekday = calendar.component(.weekday, from: date) - 1 // 0=Sun
        startOfWeekDate = calendar.date(byAdding: .day, value: -weekday, to: calendar.startOfDay(for: date)) ?? date
    }
    
    private func shiftWeek(by count: Int) {
        if let newDate = calendar.date(byAdding: .day, value: count * 7, to: selectedDate) {
            selectedDate = newDate
            eventStore.selectedDate = newDate
            updateStartOfWeek(for: newDate)
        }
    }
    
    private var weekRangeString: String {
        guard let first = currentWeekDays.first, let last = currentWeekDays.last else { return "" }
        let formatter = DateFormatter()
        formatter.locale = localeManager.effectiveLocale
        formatter.dateFormat = "MMM d"
        let firstStr = formatter.string(from: first)
        let lastStr = formatter.string(from: last)
        return "\(firstStr) – \(lastStr)"
    }
    
    private func shortWeekdayName(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = localeManager.effectiveLocale
        formatter.dateFormat = "EEE"
        return formatter.string(from: date).uppercased()
    }
    
    private func timeString(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = localeManager.effectiveLocale
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
    
    private func calculatePosition(for event: CalendarEvent) -> (top: CGFloat, height: CGFloat) {
        let startHour = calendar.component(.hour, from: event.startDate)
        let startMinute = calendar.component(.minute, from: event.startDate)
        let durationMinutes = max(15, Int(event.endDate.timeIntervalSince(event.startDate) / 60))
        
        let startFloat = CGFloat(startHour) + CGFloat(startMinute) / 60.0
        let durationFloat = CGFloat(durationMinutes) / 60.0
        
        let top = startFloat * hourHeight
        let height = max(28, durationFloat * hourHeight)
        return (top, height)
    }
    
    private func calculateNowOffset() -> CGFloat {
        let now = Date()
        let hour = calendar.component(.hour, from: now)
        let minute = calendar.component(.minute, from: now)
        let totalHours = CGFloat(hour) + CGFloat(minute) / 60.0
        return totalHours * hourHeight
    }
}

// Wrapper for Identifiable sheet binding
private struct IdentifiableEventFormMode: Identifiable {
    let id = UUID()
    let mode: EventFormMode
}
