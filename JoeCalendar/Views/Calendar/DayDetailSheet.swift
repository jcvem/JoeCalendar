//
//  DayDetailSheet.swift
//  JoeCalendar
//
//  Created for JoeCalendar Phase 0 Foundation.
//  Event creation & detail editor modal with Japanese-calm design tokens.
//

import SwiftUI

public struct DayDetailSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var localeManager: LocaleManager
    
    @State private var title: String = ""
    @State private var isAllDay: Bool = false
    @State private var startDate: Date
    @State private var endDate: Date
    @State private var location: String = ""
    @State private var notes: String = ""
    @State private var visibilityType: EventVisibilityType = .private
    @State private var selectedGroupId: String = "workout_friends"
    @State private var selectedColorHex: String = AppColor.GroupPastel.sage.hexString
    @State private var calendarType: CalendarType = .joe
    
    public var onSave: (CalendarEvent) -> Void
    
    // Sample group list
    private let availableGroups: [FriendGroup] = [
        FriendGroup(id: "workout_friends", name: "Workout Crew", ownerUid: "me", colorHex: AppColor.GroupPastel.sage.hexString),
        FriendGroup(id: "family", name: "Family", ownerUid: "me", colorHex: AppColor.GroupPastel.sakura.hexString),
        FriendGroup(id: "work_team", name: "Work Team", ownerUid: "me", colorHex: AppColor.GroupPastel.mist.hexString)
    ]
    
    public init(selectedDate: Date, onSave: @escaping (CalendarEvent) -> Void) {
        let initialStart = Calendar.current.date(bySettingHour: 10, minute: 0, second: 0, of: selectedDate) ?? selectedDate
        let initialEnd = Calendar.current.date(bySettingHour: 11, minute: 0, second: 0, of: selectedDate) ?? selectedDate
        _startDate = State(initialValue: initialStart)
        _endDate = State(initialValue: initialEnd)
        self.onSave = onSave
    }
    
    public var body: some View {
        NavigationStack {
            ZStack {
                AppColor.paper
                    .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: AppSpacing.lg) {
                        // Title Card
                        VStack(alignment: .leading, spacing: AppSpacing.xs) {
                            Text(loc: "calendar_event_title")
                                .font(AppTypography.captionMedium())
                                .foregroundColor(AppColor.inkSecondary)
                            
                            TextField(
                                String(localized: "calendar_event_title_placeholder"),
                                text: $title
                            )
                            .font(AppTypography.title2())
                            .foregroundColor(AppColor.inkPrimary)
                        }
                        .paperCard(padding: AppSpacing.md)
                        
                        // Time & Date Card
                        VStack(spacing: AppSpacing.md) {
                            Toggle(isOn: $isAllDay) {
                                Text(loc: "calendar_all_day")
                                    .font(AppTypography.bodyMedium())
                                    .foregroundColor(AppColor.inkPrimary)
                            }
                            .tint(AppColor.accent)
                            
                            Divider()
                                .background(AppColor.inkBorder)
                            
                            DatePicker(
                                selection: $startDate,
                                displayedComponents: isAllDay ? [.date] : [.date, .hourAndMinute]
                            ) {
                                Text(loc: "calendar_starts")
                                    .font(AppTypography.body())
                                    .foregroundColor(AppColor.inkSecondary)
                            }
                            
                            if !isAllDay {
                                Divider()
                                    .background(AppColor.inkBorder)
                                
                                DatePicker(
                                    selection: $endDate,
                                    displayedComponents: [.date, .hourAndMinute]
                                ) {
                                    Text(loc: "calendar_ends")
                                        .font(AppTypography.body())
                                        .foregroundColor(AppColor.inkSecondary)
                                }
                            }
                        }
                        .paperCard(padding: AppSpacing.md)
                        
                        // Visibility Card (Social Groups Differentiator)
                        VStack(alignment: .leading, spacing: AppSpacing.md) {
                            Text(loc: "calendar_visibility")
                                .font(AppTypography.captionMedium())
                                .foregroundColor(AppColor.inkSecondary)
                            
                            Picker("Visibility", selection: $visibilityType) {
                                ForEach(EventVisibilityType.allCases, id: \.self) { type in
                                    Text(loc: type.displayNameKey)
                                        .tag(type)
                                }
                            }
                            .pickerStyle(.segmented)
                            
                            if visibilityType == .group {
                                VStack(alignment: .leading, spacing: AppSpacing.xs) {
                                    Text(loc: "calendar_select_groups")
                                        .font(AppTypography.caption())
                                        .foregroundColor(AppColor.inkSecondary)
                                    
                                    HStack(spacing: AppSpacing.sm) {
                                        ForEach(availableGroups) { group in
                                            Button(action: {
                                                selectedGroupId = group.id
                                                selectedColorHex = group.colorHex
                                            }) {
                                                HStack(spacing: 4) {
                                                    Circle()
                                                        .fill(Color(hexString: group.colorHex))
                                                        .frame(width: 8, height: 8)
                                                    Text(group.name)
                                                }
                                            }
                                            .buttonStyle(TimeTreeCapsuleButtonStyle(isSelected: selectedGroupId == group.id))
                                        }
                                    }
                                    
                                    Text(loc: "calendar_groups_helper")
                                        .font(AppTypography.caption())
                                        .foregroundColor(AppColor.inkTertiary)
                                        .padding(.top, 2)
                                }
                            }
                        }
                        .paperCard(padding: AppSpacing.md)
                        
                        // Pastel Color Tag Picker
                        VStack(alignment: .leading, spacing: AppSpacing.sm) {
                            Text(loc: "calendar_color_tag")
                                .font(AppTypography.captionMedium())
                                .foregroundColor(AppColor.inkSecondary)
                            
                            HStack(spacing: AppSpacing.md) {
                                ForEach(AppColor.GroupPastel.allCases) { pastel in
                                    Button(action: {
                                        selectedColorHex = pastel.hexString
                                    }) {
                                        ZStack {
                                            Circle()
                                                .fill(pastel.color)
                                                .frame(width: 28, height: 28)
                                            
                                            if selectedColorHex == pastel.hexString {
                                                Circle()
                                                    .stroke(Color.white, lineWidth: 2)
                                                    .frame(width: 12, height: 12)
                                            }
                                        }
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                        .paperCard(padding: AppSpacing.md)
                        
                        // Location & Notes Card
                        VStack(spacing: AppSpacing.md) {
                            HStack {
                                Image(systemName: "mappin.and.ellipse")
                                    .foregroundColor(AppColor.inkTertiary)
                                    .frame(width: 20)
                                TextField(
                                    String(localized: "calendar_location"),
                                    text: $location
                                )
                                .font(AppTypography.body())
                                .foregroundColor(AppColor.inkPrimary)
                            }
                            
                            Divider()
                                .background(AppColor.inkBorder)
                            
                            HStack(alignment: .top) {
                                Image(systemName: "note.text")
                                    .foregroundColor(AppColor.inkTertiary)
                                    .frame(width: 20)
                                    .padding(.top, 2)
                                TextField(
                                    String(localized: "calendar_notes_placeholder"),
                                    text: $notes,
                                    axis: .vertical
                                )
                                .lineLimit(3...6)
                                .font(AppTypography.body())
                                .foregroundColor(AppColor.inkPrimary)
                            }
                        }
                        .paperCard(padding: AppSpacing.md)
                    }
                    .padding(.horizontal, AppSpacing.lg)
                    .padding(.vertical, AppSpacing.lg)
                }
            }
            .navigationTitle(Text(loc: "calendar_new_event"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(action: { dismiss() }) {
                        Text(loc: "action_cancel")
                            .foregroundColor(AppColor.inkSecondary)
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button(action: {
                        let finalTitle = title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            ? "New Event"
                            : title
                        let newEvent = CalendarEvent(
                            title: finalTitle,
                            startDate: startDate,
                            endDate: isAllDay ? startDate : endDate,
                            isAllDay: isAllDay,
                            location: location.isEmpty ? nil : location,
                            notes: notes.isEmpty ? nil : notes,
                            calendarType: calendarType,
                            visibility: EventVisibility(
                                type: visibilityType,
                                groupIds: visibilityType == .group ? [selectedGroupId] : []
                            ),
                            createdBy: "me",
                            colorHex: selectedColorHex
                        )
                        onSave(newEvent)
                        dismiss()
                    }) {
                        Text(loc: "action_save")
                            .font(AppTypography.headline())
                            .foregroundColor(AppColor.accent)
                    }
                }
            }
        }
    }
}
