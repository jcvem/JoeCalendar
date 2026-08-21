//
//  FriendsView.swift
//  JoeCalendar
//
//  Created for JoeCalendar Phase 0 Foundation & Extended for Phase 2 Social Groups.
//  Social & friend groups hub supporting:
//  - Multi-group privacy units (e.g. workout vs family vs work)
//  - Firestore-backed friends list & user search
//  - Pending friend requests lifecycle (accept/decline)
//

import SwiftUI

public enum FriendsTabSection: String, CaseIterable, Identifiable {
    case groups = "groups"
    case friends = "friends"
    case requests = "requests"
    
    public var id: String { rawValue }
    
    public var displayNameKey: String {
        switch self {
        case .groups: return "friends_tab_groups"
        case .friends: return "friends_tab_friends"
        case .requests: return "friends_tab_requests"
        }
    }
}

public struct FriendsView: View {
    @EnvironmentObject private var localeManager: LocaleManager
    @EnvironmentObject private var eventStore: EventStore
    @ObservedObject private var friendService = FriendService.shared
    
    @State private var selectedSection: FriendsTabSection = .groups
    @State private var isShowingCreateGroupSheet: Bool = false
    @State private var isShowingAddFriendSheet: Bool = false
    
    public init() {}
    
    public var body: some View {
        NavigationStack {
            ZStack {
                AppColor.paper
                    .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: AppSpacing.lg) {
                        // Section Switcher (Groups / Friends / Requests)
                        sectionPicker
                        
                        // Privacy Explainer Banner
                        privacyExplainerBanner
                        
                        // Section Content
                        switch selectedSection {
                        case .groups:
                            groupsSectionContent
                        case .friends:
                            friendsSectionContent
                        case .requests:
                            requestsSectionContent
                        }
                    }
                    .padding(.horizontal, AppSpacing.lg)
                    .padding(.vertical, AppSpacing.lg)
                }
            }
            .navigationTitle(Text(loc: "friends_title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    toolbarActionButton
                }
            }
            .sheet(isPresented: $isShowingCreateGroupSheet) {
                CreateGroupSheet()
                    .environmentObject(localeManager)
            }
            .sheet(isPresented: $isShowingAddFriendSheet) {
                AddFriendSheet()
                    .environmentObject(localeManager)
            }
        }
    }
    
    // MARK: - Subviews
    
    private var sectionPicker: some View {
        HStack(spacing: 4) {
            ForEach(FriendsTabSection.allCases) { section in
                let isSelected = selectedSection == section
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        selectedSection = section
                    }
                }) {
                    HStack(spacing: 4) {
                        Text(loc: section.displayNameKey)
                            .font(AppTypography.subheadline())
                            .fontWeight(isSelected ? .semibold : .regular)
                        
                        // Badge count
                        if section == .groups && !friendService.userGroups.isEmpty {
                            Text("\(friendService.userGroups.count)")
                                .font(AppTypography.caption())
                                .padding(.horizontal, 6)
                                .padding(.vertical, 1)
                                .background(isSelected ? Color.white.opacity(0.25) : AppColor.inkBorder)
                                .clipShape(Capsule())
                        } else if section == .friends && !friendService.friends.isEmpty {
                            Text("\(friendService.friends.count)")
                                .font(AppTypography.caption())
                                .padding(.horizontal, 6)
                                .padding(.vertical, 1)
                                .background(isSelected ? Color.white.opacity(0.25) : AppColor.inkBorder)
                                .clipShape(Capsule())
                        } else if section == .requests && !friendService.pendingIncomingRequests.isEmpty {
                            Text("\(friendService.pendingIncomingRequests.count)")
                                .font(AppTypography.caption())
                                .foregroundColor(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 1)
                                .background(AppColor.destructive)
                                .clipShape(Capsule())
                        }
                    }
                    .foregroundColor(isSelected ? .white : AppColor.inkSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, AppSpacing.sm)
                    .background(isSelected ? AppColor.accent : Color.clear)
                    .clipShape(RoundedRectangle(cornerRadius: AppRadius.sm, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(AppColor.surfaceSubtle)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous))
    }
    
    private var toolbarActionButton: some View {
        Group {
            switch selectedSection {
            case .groups:
                Button(action: { isShowingCreateGroupSheet = true }) {
                    HStack(spacing: 4) {
                        Image(systemName: "plus")
                        Text(loc: "friends_create_group")
                    }
                    .font(AppTypography.captionMedium())
                    .foregroundColor(AppColor.accent)
                }
            case .friends, .requests:
                Button(action: { isShowingAddFriendSheet = true }) {
                    HStack(spacing: 4) {
                        Image(systemName: "person.badge.plus")
                        Text(loc: "friends_add_friend")
                    }
                    .font(AppTypography.captionMedium())
                    .foregroundColor(AppColor.accent)
                }
            }
        }
    }
    
    private var privacyExplainerBanner: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            HStack(spacing: 6) {
                Image(systemName: "shield.lefthalf.filled")
                    .foregroundColor(AppColor.accent)
                    .font(.system(size: 13, weight: .semibold))
                Text(loc: "friends_privacy_title")
                    .font(AppTypography.captionMedium())
                    .foregroundColor(AppColor.accent)
            }
            
            Text(loc: "friends_empty_groups_desc")
                .font(AppTypography.footnote())
                .foregroundColor(AppColor.inkSecondary)
                .lineSpacing(3)
        }
        .paperCard(padding: AppSpacing.md)
    }
    
    // MARK: - 1. Groups Section Content
    
    private var groupsSectionContent: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            HStack {
                Text(loc: "friends_groups_section")
                    .font(AppTypography.headline())
                    .foregroundColor(AppColor.inkPrimary)
                
                Spacer()
                
                Button(action: { isShowingCreateGroupSheet = true }) {
                    HStack(spacing: 4) {
                        Image(systemName: "plus")
                            .font(.system(size: 11, weight: .bold))
                        Text(loc: "friends_create_group")
                            .font(AppTypography.captionMedium())
                    }
                    .foregroundColor(AppColor.accent)
                }
            }
            
            if friendService.userGroups.isEmpty {
                VStack(spacing: AppSpacing.md) {
                    Image(systemName: "person.3")
                        .font(.system(size: 36))
                        .foregroundColor(AppColor.inkTertiary)
                        .padding(.top, AppSpacing.lg)
                    
                    Text(loc: "friends_empty_groups_title")
                        .font(AppTypography.headline())
                        .foregroundColor(AppColor.inkPrimary)
                    
                    Button(action: { isShowingCreateGroupSheet = true }) {
                        Text(loc: "friends_create_group")
                    }
                    .buttonStyle(TimeTreePrimaryButtonStyle(isCompact: true))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, AppSpacing.xl)
            } else {
                VStack(spacing: AppSpacing.sm) {
                    ForEach(friendService.userGroups) { group in
                        NavigationLink(destination: GroupDetailView(group: group).environmentObject(eventStore)) {
                            groupRow(group: group)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
    
    private func groupRow(group: FriendGroup) -> some View {
        HStack(spacing: AppSpacing.md) {
            ZStack {
                Circle()
                    .fill(Color(hexString: group.colorHex).opacity(0.18))
                    .frame(width: 44, height: 44)
                
                Image(systemName: group.iconName)
                    .foregroundColor(Color(hexString: group.colorHex))
                    .font(.system(size: 19))
            }
            
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(group.name)
                        .font(AppTypography.headline())
                        .foregroundColor(AppColor.inkPrimary)
                    
                    if group.ownerUid == friendService.currentUser.id {
                        Text(loc: "friends_role_owner")
                            .font(AppTypography.caption())
                            .foregroundColor(AppColor.accent)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(AppColor.accentLight)
                            .clipShape(Capsule())
                    }
                }
                
                Text("\(group.memberUids.count) " + "friends_members_count".localized())
                    .font(AppTypography.caption())
                    .foregroundColor(AppColor.inkSecondary)
            }
            
            Spacer()
            
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(AppColor.inkTertiary)
        }
        .padding(AppSpacing.md)
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
    
    // MARK: - 2. Friends Section Content
    
    private var friendsSectionContent: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            HStack {
                Text(loc: "friends_my_friends_section")
                    .font(AppTypography.headline())
                    .foregroundColor(AppColor.inkPrimary)
                
                Spacer()
                
                Button(action: { isShowingAddFriendSheet = true }) {
                    HStack(spacing: 4) {
                        Image(systemName: "person.badge.plus")
                            .font(.system(size: 12))
                        Text(loc: "friends_add_friend")
                            .font(AppTypography.captionMedium())
                    }
                    .foregroundColor(AppColor.accent)
                }
            }
            
            if friendService.friends.isEmpty {
                VStack(spacing: AppSpacing.md) {
                    Image(systemName: "person.2.slash")
                        .font(.system(size: 36))
                        .foregroundColor(AppColor.inkTertiary)
                        .padding(.top, AppSpacing.lg)
                    
                    Text(loc: "friends_no_friends_title")
                        .font(AppTypography.headline())
                        .foregroundColor(AppColor.inkPrimary)
                    
                    Text(loc: "friends_no_friends_desc")
                        .font(AppTypography.footnote())
                        .foregroundColor(AppColor.inkSecondary)
                        .multilineTextAlignment(.center)
                    
                    Button(action: { isShowingAddFriendSheet = true }) {
                        Text(loc: "friends_find_friends")
                    }
                    .buttonStyle(TimeTreePrimaryButtonStyle(isCompact: true))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, AppSpacing.xl)
            } else {
                VStack(spacing: AppSpacing.sm) {
                    ForEach(friendService.friends) { friend in
                        friendRow(friend: friend)
                    }
                }
            }
        }
    }
    
    private func friendRow(friend: JoeUser) -> some View {
        HStack(spacing: AppSpacing.md) {
            ZStack {
                Circle()
                    .fill(AppColor.accentLight)
                    .frame(width: 42, height: 42)
                
                Text(friend.displayName.prefix(1).uppercased())
                    .font(AppTypography.headline())
                    .foregroundColor(AppColor.accent)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(friend.displayName)
                    .font(AppTypography.headline())
                    .foregroundColor(AppColor.inkPrimary)
                
                if let joeId = friend.joeId {
                    Text("@\(joeId)")
                        .font(AppTypography.caption())
                        .foregroundColor(AppColor.inkTertiary)
                }
            }
            
            Spacer()
            
            Menu {
                Button(role: .destructive, action: {
                    Task {
                        try? await friendService.removeFriend(friendUid: friend.id)
                    }
                }) {
                    Label("friends_remove".localized(), systemImage: "person.badge.minus")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .foregroundColor(AppColor.inkTertiary)
                    .frame(width: 28, height: 28)
            }
        }
        .padding(AppSpacing.md)
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
    
    // MARK: - 3. Requests Section Content
    
    private var requestsSectionContent: some View {
        VStack(alignment: .leading, spacing: AppSpacing.lg) {
            // Incoming Requests
            VStack(alignment: .leading, spacing: AppSpacing.md) {
                HStack {
                    Text(loc: "friends_incoming_requests")
                        .font(AppTypography.headline())
                        .foregroundColor(AppColor.inkPrimary)
                    
                    Spacer()
                    
                    Text("\(friendService.pendingIncomingRequests.count)")
                        .font(AppTypography.captionMedium())
                        .foregroundColor(AppColor.inkSecondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(AppColor.surfaceSubtle)
                        .clipShape(Capsule())
                }
                
                if friendService.pendingIncomingRequests.isEmpty {
                    Text(loc: "friends_no_incoming_requests")
                        .font(AppTypography.footnote())
                        .foregroundColor(AppColor.inkTertiary)
                        .padding(.vertical, AppSpacing.sm)
                } else {
                    VStack(spacing: AppSpacing.sm) {
                        ForEach(friendService.pendingIncomingRequests) { item in
                            incomingRequestRow(item: item)
                        }
                    }
                }
            }
            
            // Outgoing Requests
            if !friendService.pendingOutgoingRequests.isEmpty {
                VStack(alignment: .leading, spacing: AppSpacing.md) {
                    HStack {
                        Text(loc: "friends_outgoing_requests")
                            .font(AppTypography.headline())
                            .foregroundColor(AppColor.inkPrimary)
                        
                        Spacer()
                        
                        Text("\(friendService.pendingOutgoingRequests.count)")
                            .font(AppTypography.captionMedium())
                            .foregroundColor(AppColor.inkSecondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(AppColor.surfaceSubtle)
                            .clipShape(Capsule())
                    }
                    
                    VStack(spacing: AppSpacing.sm) {
                        ForEach(friendService.pendingOutgoingRequests) { item in
                            outgoingRequestRow(item: item)
                        }
                    }
                }
            }
        }
    }
    
    private func incomingRequestRow(item: FriendRequestItem) -> some View {
        HStack(spacing: AppSpacing.md) {
            ZStack {
                Circle()
                    .fill(AppColor.accentLight)
                    .frame(width: 42, height: 42)
                
                Text(item.otherUser.displayName.prefix(1).uppercased())
                    .font(AppTypography.headline())
                    .foregroundColor(AppColor.accent)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(item.otherUser.displayName)
                    .font(AppTypography.headline())
                    .foregroundColor(AppColor.inkPrimary)
                
                if let joeId = item.otherUser.joeId {
                    Text("@\(joeId)")
                        .font(AppTypography.caption())
                        .foregroundColor(AppColor.inkTertiary)
                }
            }
            
            Spacer()
            
            HStack(spacing: AppSpacing.sm) {
                Button(action: {
                    Task {
                        try? await friendService.declineFriendRequest(friendshipId: item.friendship.id)
                    }
                }) {
                    Text(loc: "friends_decline")
                        .font(AppTypography.captionMedium())
                        .foregroundColor(AppColor.inkSecondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(AppColor.surfaceSubtle)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                
                Button(action: {
                    Task {
                        try? await friendService.acceptFriendRequest(friendshipId: item.friendship.id)
                    }
                }) {
                    Text(loc: "friends_accept")
                        .font(AppTypography.captionMedium())
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(AppColor.accent)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
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
    
    private func outgoingRequestRow(item: FriendRequestItem) -> some View {
        HStack(spacing: AppSpacing.md) {
            ZStack {
                Circle()
                    .fill(AppColor.surfaceSubtle)
                    .frame(width: 40, height: 40)
                
                Text(item.otherUser.displayName.prefix(1).uppercased())
                    .font(AppTypography.headline())
                    .foregroundColor(AppColor.inkSecondary)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(item.otherUser.displayName)
                    .font(AppTypography.bodyMedium())
                    .foregroundColor(AppColor.inkPrimary)
                
                if let joeId = item.otherUser.joeId {
                    Text("@\(joeId)")
                        .font(AppTypography.caption())
                        .foregroundColor(AppColor.inkTertiary)
                }
            }
            
            Spacer()
            
            HStack(spacing: 4) {
                Image(systemName: "clock")
                Text(loc: "friends_status_pending")
            }
            .font(AppTypography.captionMedium())
            .foregroundColor(AppColor.warning)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(AppColor.warning.opacity(0.12))
            .clipShape(Capsule())
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
