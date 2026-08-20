//
//  EventFormSheet.swift
//  JoeCalendar
//
//  Created for JoeCalendar Phase 1 Core Calendar.
//  TimeTree-inspired Japanese calm event editor supporting creation,
//  editing, recurrence rules, source dispatch, and social group picking.
//

import SwiftUI

public enum EventFormMode: Equatable {
    case new(defaultDate: Date)
    case edit(event: CalendarEvent)
}

public struct EventFormSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var localeManager: LocaleManager
    @EnvironmentObject private var eventStore: EventStore
    
    private let mode: EventFormMode
    private let existingEvent: CalendarEvent?
    
    @State private var title: String
    @State private var isAllDay: Bool
    @State private var startDate: Date
    @State private var endDate: Date
    @State private var recurrence: EventRecurrence
    @State private var calendarType: CalendarType
    @State private var visibilityType: EventVisibilityType
    @State private var selectedGroupId: String
    @State private var selectedColorHex: String
    @State private var location: String
    @State private var notes: String
    
    @State private var isShowingDeleteAlert: Bool = false
    @State private var isSaving: Bool = false
    
    // Sample groups for Social Unit differentiator
    private let availableGroups: [FriendGroup] = [
        FriendGroup(id: "workout_friends", name: "Workout Crew", ownerUid: "me", colorHex: AppColor.GroupPastel.sage.hexString),
        FriendGroup(id: "family", name: "Family", ownerUid: "me", colorHex: AppColor.GroupPastel.sakura.hexString),
        FriendGroup(id: "work_team", name: "Work Team", ownerUid: "me", colorHex: AppColor.GroupPastel.mist.hexString)
    ]
    
    public init(mode: EventFormMode) {
        self.mode = mode
        switch mode {
        case .new(let defaultDate):
            self.existingEvent = nil
            _title = State(initialValue: "")
            _isAllDay = State(initialValue: false)
            let start = Calendar.current.date(bySettingHour: 10, minute: 0, second: 0, of: defaultDate) ?? defaultDate
            let end = Calendar.current.date(bySettingHour: 11, minute: 0, second: 0, of: defaultDate) ?? defaultDate
            _startDate = State(initialValue: start)
            _endDate = State(initialValue: end)
            _recurrence = State(initialValue: .none)
            _calendarType = State(initialValue: .joe)
            _visibilityType = State(initialValue: .private)
            _selectedGroupId = State(initialValue: "workout_friends")
            _selectedColorHex = State(initialValue: AppColor.GroupPastel.sage.hexString)
            _location = State(initialValue: "")
            _notes = State(initialValue: "")
            
        case .edit(let event):
            self.existingEvent = event
            _title = State(initialValue: event.title)
            _isAllDay = State(initialValue: event.isAllDay)
            _startDate = State(initialValue: event.startDate)
            _endDate = State(initialValue: event.endDate)
            _recurrence = State(initialValue: event.recurrence)
            _calendarType = State(initialValue: event.calendarType)
            _visibilityType = State(initialValue: event.visibility.type)
            _selectedGroupId = State(initialValue: event.visibility.groupIds.first ?? "workout_friends")
            _selectedColorHex = State(initialValue: event.colorHex)
            _location = State(initialValue: event.location ?? "")
            _notes = State(initialValue: event.notes ?? "")
        }
    }
    
    public var body: some View {
        NavigationStack {
            ZStack {
                AppColor.paper
                    .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: AppSpacing.lg) {
                        // Title Card
                        titleCard
                        
                        // Time & Date Card
                        timeDateCard
                        
                        // Recurrence Card
                        recurrenceCard
                        
                        // Source / Calendar Type Card
                        sourceCard
                        
                        // Visibility & Social Group Card
                        visibilityCard
                        
                        // Pastel Color Tag Picker
                        colorPickerCard
                        
                        // Location & Notes Card
                        locationNotesCard
                        
                        // Delete Button (if in edit mode)
                        if existingEvent != nil {
                            deleteButtonCard
                        }
                    }
                    .padding(.horizontal, AppSpacing.lg)
                    .padding(.vertical, AppSpacing.lg)
                }
            }
            .navigationTitle(Text(loc: existingEvent == nil ? "calendar_new_event" : "calendar_edit_event"))
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
                        saveEvent()
                    }) {
                        if isSaving {
                            ProgressView()
                                .tint(AppColor.accent)
                        } else {
                            Text(loc: "action_save")
                                .font(AppTypography.headline())
                                .foregroundColor(AppColor.accent)
                        }
                    }
                    .disabled(isSaving)
                }
            }
            .alert(isPresented: $isShowingDeleteAlert) {
                Alert(
                    title: Text(loc: "calendar_delete_title"),
                    message: Text(loc: "calendar_delete_message"),
                    primaryButton: .destructive(Text(loc: "action_delete")) {
                        deleteEvent()
                    },
                    secondaryButton: .cancel(Text(loc: "action_cancel"))
                )
            }
        }
    }
    
    // MARK: - Subviews
    
    private var titleCard: some View {
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
    }
    
    private var timeDateCard: some View {
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
    }
    
    private var recurrenceCard: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            Text(loc: "calendar_repeat")
                .font(AppTypography.captionMedium())
                .foregroundColor(AppColor.inkSecondary)
            
            Picker("Repeat", selection: $recurrence) {
                ForEach(EventRecurrence.allCases, id: \.self) { rec in
                    Text(loc: rec.displayNameKey)
                        .tag(rec)
                }
            }
            .pickerStyle(.segmented)
        }
        .paperCard(padding: AppSpacing.md)
    }
    
    private var sourceCard: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            Text(loc: "calendar_type")
                .font(AppTypography.captionMedium())
                .foregroundColor(AppColor.inkSecondary)
            
            Picker("Source", selection: $calendarType) {
                Text(loc: "calendar_type_joe").tag(CalendarType.joe)
                Text(loc: "calendar_type_device").tag(CalendarType.device)
                Text(loc: "calendar_type_google").tag(CalendarType.google)
            }
            .pickerStyle(.segmented)
        }
        .paperCard(padding: AppSpacing.md)
    }
    
    private var visibilityCard: some View {
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
    }
    
    private var colorPickerCard: some View {
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
    }
    
    private var locationNotesCard: some View {
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
    
    private var deleteButtonCard: some View {
        Button(action: {
            isShowingDeleteAlert = true
        }) {
            HStack {
                Spacer()
                Image(systemName: "trash")
                Text(loc: "action_delete")
                Spacer()
            }
            .font(AppTypography.headline())
            .foregroundColor(AppColor.destructive)
            .padding(.vertical, AppSpacing.md)
            .background(AppColor.surface)
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous)
                    .stroke(AppColor.destructive.opacity(0.3), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Actions
    
    private func saveEvent() {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalTitle = trimmedTitle.isEmpty ? "New Event" : trimmedTitle
        let finalEnd = isAllDay ? startDate : (endDate < startDate ? startDate.addingTimeInterval(3600) : endDate)
        
        isSaving = true
        
        Task {
            if let existing = existingEvent {
                var updated = existing
                updated.title = finalTitle
                updated.startDate = startDate
                updated.endDate = finalEnd
                updated.isAllDay = isAllDay
                updated.recurrence = recurrence
                updated.calendarType = calendarType
                updated.visibility = EventVisibility(
                    type: visibilityType,
                    groupIds: visibilityType == .group ? [selectedGroupId] : []
                )
                updated.colorHex = selectedColorHex
                updated.location = location.isEmpty ? nil : location
                updated.notes = notes.isEmpty ? nil : notes
                
                try? await eventStore.updateEvent(updated)
            } else {
                let newEvent = CalendarEvent(
                    title: finalTitle,
                    startDate: startDate,
                    endDate: finalEnd,
                    isAllDay: isAllDay,
                    location: location.isEmpty ? nil : location,
                    notes: notes.isEmpty ? nil : notes,
                    calendarType: calendarType,
                    visibility: EventVisibility(
                        type: visibilityType,
                        groupIds: visibilityType == .group ? [selectedGroupId] : []
                    ),
                    recurrence: recurrence,
                    createdBy: "me",
                    colorHex: selectedColorHex,
                    source: calendarType.rawValue
                )
                
                try? await eventStore.addEvent(newEvent)
            }
            
            isSaving = false
            dismiss()
        }
    }
    
    private func deleteEvent() {
        guard let existing = existingEvent else { return }
        Task {
            try? await eventStore.deleteEvent(existing)
            dismiss()
        }
    }
}
