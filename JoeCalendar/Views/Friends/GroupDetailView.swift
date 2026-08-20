//
//  GroupDetailView.swift
//  JoeCalendar
//
//  Created for JoeCalendar Phase 2 Social Groups.
//  TimeTree-inspired group privacy hub:
//  - Group event feed & timeline
//  - Per-group calendar filtering
//  - Member circle management (add/remove)
//

import SwiftUI

public enum GroupDetailTab: String, CaseIterable, Identifiable {
    case events = "events"
    case members = "members"
    
    public var id: String { rawValue }
    
    public var displayNameKey: String {
        switch self {
        case .events: return "friends_group_events"
        case .members: return "friends_group_members"
        }
    }
}

public struct GroupDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var localeManager: LocaleManager
    @EnvironmentObject private var eventStore: EventStore
    @ObservedObject private var friendService = FriendService.shared
    
    public let group: FriendGroup
    
    @State private var selectedTab: GroupDetailTab = .events
    @State private var activeSheetMode: EventFormMode? = nil
    @State private var isShowingAddMemberSheet: Bool = false
    @State private var isShowingDeleteAlert: Bool = false
    @State private var isShowingLeaveAlert: Bool = false
    
    public init(group: FriendGroup) {
        self.group = group
    }
    
    private var liveGroup: FriendGroup {
        friendService.userGroups.first(where: { $0.id == group.id }) ?? group
    }
    
    private var isOwner: Bool {
        liveGroup.ownerUid == friendService.currentUser.id
    }
    
    private var groupEvents: [CalendarEvent] {
        eventStore.events(for: liveGroup.id)
    }
    
    public var body: some View {
        ZStack {
            AppColor.paper
                .ignoresSafeArea()
            
            ScrollView {
                VStack(spacing: AppSpacing.lg) {
                    // Group Header Card
                    headerCard
                    
                    // Action Buttons (Filter Calendar & + New Event)
                    actionButtonsCard
                    
                    // Segmented Control (Events Feed / Members)
                    Picker("", selection: $selectedTab) {
                        ForEach(GroupDetailTab.allCases) { tab in
                            Text(loc: tab.displayNameKey).tag(tab)
                        }
                    }
                    .pickerStyle(.segmented)
                    
                    // Content by Tab
                    switch selectedTab {
                    case .events:
                        eventsFeedSection
                    case .members:
                        membersSection
                    }
                }
                .padding(.horizontal, AppSpacing.lg)
                .padding(.vertical, AppSpacing.lg)
            }
        }
        .navigationTitle(liveGroup.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    if isOwner {
                        Button(role: .destructive, action: {
                            isShowingDeleteAlert = true
                        }) {
                            Label(String(localized: "friends_delete_group"), systemImage: "trash")
                        }
                    } else {
                        Button(role: .destructive, action: {
                            isShowingLeaveAlert = true
                        }) {
                            Label(String(localized: "friends_leave_group"), systemImage: "rectangle.portrait.and.arrow.right")
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .foregroundColor(AppColor.inkSecondary)
                }
            }
        }
        .sheet(item: Binding<IdentifiableEventFormMode?>(
            get: { activeSheetMode.map { IdentifiableEventFormMode(mode: $0) } },
            set: { activeSheetMode = $0?.mode }
        )) { item in
            EventFormSheet(mode: item.mode)
                .environmentObject(localeManager)
                .environmentObject(eventStore)
        }
        .sheet(isPresented: $isShowingAddMemberSheet) {
            AddGroupMemberSheet(group: liveGroup)
                .environmentObject(localeManager)
        }
        .alert(isPresented: $isShowingDeleteAlert) {
            Alert(
                title: Text(loc: "friends_delete_group_title"),
                message: Text(loc: "friends_delete_group_message"),
                primaryButton: .destructive(Text(loc: "action_delete")) {
                    Task {
                        try? await friendService.deleteGroup(groupId: liveGroup.id)
                        dismiss()
                    }
                },
                secondaryButton: .cancel(Text(loc: "action_cancel"))
            )
        }
        .alert(isPresented: $isShowingLeaveAlert) {
            Alert(
                title: Text(loc: "friends_leave_group_title"),
                message: Text(loc: "friends_leave_group_message"),
                primaryButton: .destructive(Text(loc: "friends_leave_group")) {
                    Task {
                        try? await friendService.removeMember(friendService.currentUser.id, from: liveGroup.id)
                        dismiss()
                    }
                },
                secondaryButton: .cancel(Text(loc: "action_cancel"))
            )
        }
    }
    
    // MARK: - Subviews
    
    private var headerCard: some View {
        HStack(spacing: AppSpacing.md) {
            ZStack {
                Circle()
                    .fill(Color(hexString: liveGroup.colorHex).opacity(0.2))
                    .frame(width: 56, height: 56)
                
                Image(systemName: liveGroup.iconName)
                    .font(.system(size: 24))
                    .foregroundColor(Color(hexString: liveGroup.colorHex))
            }
            
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(liveGroup.name)
                        .font(AppTypography.title2())
                        .foregroundColor(AppColor.inkPrimary)
                    
                    if isOwner {
                        Text(loc: "friends_role_owner")
                            .font(AppTypography.caption())
                            .foregroundColor(AppColor.accent)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(AppColor.accentLight)
                            .clipShape(Capsule())
                    }
                }
                
                Text("\(liveGroup.memberUids.count) " + String(localized: "friends_members_count"))
                    .font(AppTypography.footnote())
                    .foregroundColor(AppColor.inkSecondary)
            }
            
            Spacer()
        }
        .paperCard(padding: AppSpacing.md)
    }
    
    private var actionButtonsCard: some View {
        HStack(spacing: AppSpacing.md) {
            // Filter Calendar Button
            Button(action: {
                if eventStore.selectedGroupId == liveGroup.id {
                    eventStore.clearGroupFilter()
                } else {
                    eventStore.selectGroupFilter(liveGroup.id)
                }
            }) {
                HStack(spacing: 6) {
                    Image(systemName: eventStore.selectedGroupId == liveGroup.id ? "checkmark.circle.fill" : "calendar")
                    Text(loc: eventStore.selectedGroupId == liveGroup.id ? "calendar_filter_active" : "friends_filter_calendar")
                }
            }
            .buttonStyle(TimeTreeSecondaryButtonStyle(isCompact: false))
            
            // New Event for Group Button
            Button(action: {
                activeSheetMode = .new(defaultDate: Date(), preselectedGroupId: liveGroup.id)
            }) {
                HStack(spacing: 6) {
                    Image(systemName: "plus")
                    Text(loc: "friends_new_group_event")
                }
            }
            .buttonStyle(TimeTreePrimaryButtonStyle(isCompact: false))
        }
    }
    
    // MARK: - Events Feed Section
    
    private var eventsFeedSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            if groupEvents.isEmpty {
                VStack(spacing: AppSpacing.md) {
                    Image(systemName: "sportscourt")
                        .font(.system(size: 36))
                        .foregroundColor(AppColor.inkTertiary)
                        .padding(.top, AppSpacing.lg)
                    
                    Text(loc: "friends_group_no_events")
                        .font(AppTypography.headline())
                        .foregroundColor(AppColor.inkPrimary)
                    
                    Text(loc: "friends_group_no_events_desc")
                        .font(AppTypography.footnote())
                        .foregroundColor(AppColor.inkSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, AppSpacing.lg)
                    
                    Button(action: {
                        activeSheetMode = .new(defaultDate: Date(), preselectedGroupId: liveGroup.id)
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "plus")
                            Text(loc: "friends_new_group_event")
                        }
                    }
                    .buttonStyle(TimeTreePrimaryButtonStyle(isCompact: true))
                    .padding(.top, AppSpacing.xs)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, AppSpacing.xl)
            } else {
                VStack(spacing: AppSpacing.sm) {
                    ForEach(groupEvents) { event in
                        Button(action: {
                            activeSheetMode = .edit(event: event)
                        }) {
                            groupEventRow(event: event)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
    
    private func groupEventRow(event: CalendarEvent) -> some View {
        HStack(spacing: AppSpacing.md) {
            RoundedRectangle(cornerRadius: 2)
                .fill(Color(hexString: liveGroup.colorHex))
                .frame(width: 4)
            
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(event.title)
                        .font(AppTypography.headline())
                        .foregroundColor(AppColor.inkPrimary)
                    Spacer()
                    
                    Text(dateFormatted(event.startDate))
                        .font(AppTypography.caption())
                        .foregroundColor(AppColor.inkSecondary)
                }
                
                HStack(spacing: AppSpacing.md) {
                    if event.isAllDay {
                        Text(loc: "calendar_all_day")
                            .font(AppTypography.caption())
                            .foregroundColor(AppColor.inkSecondary)
                    } else {
                        Text("\(timeFormatted(event.startDate)) - \(timeFormatted(event.endDate))")
                            .font(AppTypography.caption())
                            .foregroundColor(AppColor.inkSecondary)
                    }
                    
                    if let location = event.location, !location.isEmpty {
                        HStack(spacing: 2) {
                            Image(systemName: "mappin.and.ellipse")
                                .font(.system(size: 9))
                            Text(location)
                                .font(AppTypography.caption())
                                .lineLimit(1)
                        }
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
    
    // MARK: - Members Section
    
    private var membersSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            HStack {
                Text(loc: "friends_group_members")
                    .font(AppTypography.headline())
                    .foregroundColor(AppColor.inkPrimary)
                
                Spacer()
                
                if isOwner {
                    Button(action: {
                        isShowingAddMemberSheet = true
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "person.badge.plus")
                            Text(loc: "friends_add_members_to_group")
                        }
                        .font(AppTypography.captionMedium())
                        .foregroundColor(AppColor.accent)
                    }
                }
            }
            
            VStack(spacing: AppSpacing.xs) {
                ForEach(liveGroup.memberUids, id: \.self) { memberUid in
                    let user = friendService.user(for: memberUid)
                    let isGroupOwner = liveGroup.ownerUid == memberUid
                    let isMe = memberUid == friendService.currentUser.id
                    
                    HStack(spacing: AppSpacing.md) {
                        ZStack {
                            Circle()
                                .fill(isGroupOwner ? Color(hexString: liveGroup.colorHex).opacity(0.2) : AppColor.accentLight)
                                .frame(width: 38, height: 38)
                            
                            Text((user?.displayName.prefix(1) ?? "U").uppercased())
                                .font(AppTypography.headline())
                                .foregroundColor(isGroupOwner ? Color(hexString: liveGroup.colorHex) : AppColor.accent)
                        }
                        
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(user?.displayName ?? "Member")
                                    .font(AppTypography.bodyMedium())
                                    .foregroundColor(AppColor.inkPrimary)
                                
                                if isMe {
                                    Text(loc: "friends_tag_you")
                                        .font(AppTypography.caption())
                                        .foregroundColor(AppColor.inkTertiary)
                                }
                            }
                            
                            if let joeId = user?.joeId {
                                Text("@\(joeId)")
                                    .font(AppTypography.caption())
                                    .foregroundColor(AppColor.inkTertiary)
                            }
                        }
                        
                        Spacer()
                        
                        if isGroupOwner {
                            Text(loc: "friends_role_owner")
                                .font(AppTypography.caption())
                                .foregroundColor(AppColor.accent)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(AppColor.accentLight)
                                .clipShape(Capsule())
                        } else if isOwner && !isMe {
                            Button(action: {
                                Task {
                                    try? await friendService.removeMember(memberUid, from: liveGroup.id)
                                }
                            }) {
                                Image(systemName: "minus.circle")
                                    .font(.system(size: 16))
                                    .foregroundColor(AppColor.destructive)
                            }
                        }
                    }
                    .padding(AppSpacing.md)
                    .background(AppColor.surface)
                    .clipShape(RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous)
                            .stroke(AppColor.inkBorder, lineWidth: 1)
                    )
                }
            }
        }
    }
    
    // MARK: - Helpers
    
    private func dateFormatted(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = localeManager.effectiveLocale
        formatter.dateStyle = .medium
        return formatter.string(from: date)
    }
    
    private func timeFormatted(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = localeManager.effectiveLocale
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

// MARK: - Add Member Sheet

private struct AddGroupMemberSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var friendService = FriendService.shared
    public let group: FriendGroup
    
    @State private var selectedUids: Set<String> = []
    @State private var isSaving: Bool = false
    
    private var availableFriends: [JoeUser] {
        friendService.friends.filter { !group.memberUids.contains($0.id) }
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                AppColor.paper
                    .ignoresSafeArea()
                
                ScrollView {
                    VStack(alignment: .leading, spacing: AppSpacing.md) {
                        if availableFriends.isEmpty {
                            VStack(spacing: AppSpacing.sm) {
                                Text(loc: "friends_all_friends_in_group")
                                    .font(AppTypography.body())
                                    .foregroundColor(AppColor.inkSecondary)
                                    .padding(.top, AppSpacing.xl)
                            }
                            .frame(maxWidth: .infinity)
                        } else {
                            ForEach(availableFriends) { friend in
                                let isSelected = selectedUids.contains(friend.id)
                                Button(action: {
                                    if isSelected {
                                        selectedUids.remove(friend.id)
                                    } else {
                                        selectedUids.insert(friend.id)
                                    }
                                }) {
                                    HStack(spacing: AppSpacing.md) {
                                        ZStack {
                                            Circle()
                                                .fill(AppColor.accentLight)
                                                .frame(width: 36, height: 36)
                                            Text(friend.displayName.prefix(1))
                                                .font(AppTypography.headline())
                                                .foregroundColor(AppColor.accent)
                                        }
                                        
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(friend.displayName)
                                                .font(AppTypography.bodyMedium())
                                                .foregroundColor(AppColor.inkPrimary)
                                            if let joeId = friend.joeId {
                                                Text("@\(joeId)")
                                                    .font(AppTypography.caption())
                                                    .foregroundColor(AppColor.inkTertiary)
                                            }
                                        }
                                        
                                        Spacer()
                                        
                                        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                            .foregroundColor(isSelected ? AppColor.accent : AppColor.inkTertiary)
                                            .font(.system(size: 20))
                                    }
                                    .padding(AppSpacing.md)
                                    .background(AppColor.surface)
                                    .clipShape(RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous)
                                            .stroke(AppColor.inkBorder, lineWidth: 1)
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding(AppSpacing.lg)
                }
            }
            .navigationTitle(Text(loc: "friends_add_members_to_group"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(action: { dismiss() }) {
                        Text(loc: "action_cancel")
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button(action: {
                        isSaving = true
                        Task {
                            try? await friendService.addMembers(Array(selectedUids), to: group.id)
                            isSaving = false
                            dismiss()
                        }
                    }) {
                        if isSaving {
                            ProgressView()
                        } else {
                            Text(loc: "action_save")
                        }
                    }
                    .disabled(selectedUids.isEmpty || isSaving)
                }
            }
        }
    }
}

// Wrapper for Identifiable sheet binding
private struct IdentifiableEventFormMode: Identifiable {
    let id = UUID()
    let mode: EventFormMode
}
