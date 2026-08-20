//
//  FriendsView.swift
//  JoeCalendar
//
//  Created for JoeCalendar Phase 0 Foundation.
//  Social & friend groups tab supporting distinct circles (e.g. workout vs family vs work).
//

import SwiftUI

public struct FriendsView: View {
    @EnvironmentObject private var localeManager: LocaleManager
    @State private var searchText: String = ""
    
    // Sample groups
    @State private var groups: [FriendGroup] = [
        FriendGroup(
            name: "Workout Friends",
            ownerUid: "me",
            memberUids: ["user1", "user2", "user3"],
            colorHex: AppColor.GroupPastel.sage.hexString,
            iconName: "figure.run"
        ),
        FriendGroup(
            name: "Family Circle",
            ownerUid: "me",
            memberUids: ["user4", "user5"],
            colorHex: AppColor.GroupPastel.sakura.hexString,
            iconName: "house.fill"
        ),
        FriendGroup(
            name: "Design Guild",
            ownerUid: "me",
            memberUids: ["user6", "user7", "user8", "user9"],
            colorHex: AppColor.GroupPastel.mist.hexString,
            iconName: "paintbrush.fill"
        )
    ]
    
    public init() {}
    
    public var body: some View {
        NavigationStack {
            ZStack {
                AppColor.paper
                    .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: AppSpacing.lg) {
                        // Search Bar
                        HStack(spacing: AppSpacing.sm) {
                            Image(systemName: "magnifyingglass")
                                .foregroundColor(AppColor.inkTertiary)
                            TextField(
                                String(localized: "friends_search_placeholder"),
                                text: $searchText
                            )
                            .font(AppTypography.body())
                            .foregroundColor(AppColor.inkPrimary)
                        }
                        .padding(.horizontal, AppSpacing.md)
                        .padding(.vertical, AppSpacing.sm + 2)
                        .background(AppColor.surface)
                        .clipShape(RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous)
                                .stroke(AppColor.inkBorder, lineWidth: 1)
                        )
                        
                        // Privacy & Value Explainer Card
                        VStack(alignment: .leading, spacing: AppSpacing.xs) {
                            HStack(spacing: 6) {
                                Image(systemName: "shield.lefthalf.filled")
                                    .foregroundColor(AppColor.accent)
                                    .font(.system(size: 13, weight: .semibold))
                                Text("Circle-based Privacy")
                                    .font(AppTypography.captionMedium())
                                    .foregroundColor(AppColor.accent)
                            }
                            
                            Text(loc: "friends_empty_groups_desc")
                                .font(AppTypography.footnote())
                                .foregroundColor(AppColor.inkSecondary)
                                .lineSpacing(3)
                        }
                        .paperCard(padding: AppSpacing.md)
                        
                        // Groups Section
                        VStack(alignment: .leading, spacing: AppSpacing.md) {
                            HStack {
                                Text(loc: "friends_groups_section")
                                    .font(AppTypography.headline())
                                    .foregroundColor(AppColor.inkPrimary)
                                
                                Spacer()
                                
                                Button(action: {}) {
                                    HStack(spacing: 4) {
                                        Image(systemName: "plus")
                                            .font(.system(size: 11, weight: .bold))
                                        Text(loc: "friends_create_group")
                                            .font(AppTypography.captionMedium())
                                    }
                                    .foregroundColor(AppColor.accent)
                                }
                            }
                            
                            VStack(spacing: AppSpacing.sm) {
                                ForEach(groups) { group in
                                    groupRow(group: group)
                                }
                            }
                        }
                        
                        // Coming Soon Card
                        HStack(spacing: AppSpacing.md) {
                            Image(systemName: "sparkles")
                                .font(.system(size: 20))
                                .foregroundColor(AppColor.accent)
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Phase 2 — Social Groups")
                                    .font(AppTypography.captionMedium())
                                    .foregroundColor(AppColor.inkPrimary)
                                Text(loc: "friends_coming_soon_hint")
                                    .font(AppTypography.footnote())
                                    .foregroundColor(AppColor.inkSecondary)
                            }
                            Spacer()
                        }
                        .paperCard(padding: AppSpacing.md)
                    }
                    .padding(.horizontal, AppSpacing.lg)
                    .padding(.vertical, AppSpacing.lg)
                }
            }
            .navigationTitle(Text(loc: "friends_title"))
            .navigationBarTitleDisplayMode(.inline)
        }
    }
    
    private func groupRow(group: FriendGroup) -> some View {
        HStack(spacing: AppSpacing.md) {
            ZStack {
                Circle()
                    .fill(Color(hexString: group.colorHex).opacity(0.18))
                    .frame(width: 42, height: 42)
                
                Image(systemName: group.iconName)
                    .foregroundColor(Color(hexString: group.colorHex))
                    .font(.system(size: 18))
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(group.name)
                    .font(AppTypography.headline())
                    .foregroundColor(AppColor.inkPrimary)
                
                Text("\(group.memberUids.count + 1) members")
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
}
