//
//  CreateGroupSheet.swift
//  JoeCalendar
//
//  Created for JoeCalendar Phase 2 Social Groups.
//  TimeTree-inspired Japanese calm group creation sheet:
//  Name, pastel color palette, SF symbol icon, and friends multi-select.
//

import SwiftUI

public struct CreateGroupSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var localeManager: LocaleManager
    @ObservedObject private var friendService = FriendService.shared
    
    @State private var groupName: String = ""
    @State private var selectedColorHex: String = AppColor.GroupPastel.sage.hexString
    @State private var selectedIcon: String = "person.2.fill"
    @State private var selectedMemberUids: Set<String> = []
    @State private var isCreating: Bool = false
    
    private let availableIcons: [String] = [
        "person.2.fill",
        "figure.run",
        "sportscourt.fill",
        "house.fill",
        "briefcase.fill",
        "heart.fill",
        "sparkles",
        "fork.knife",
        "cup.and.saucer.fill",
        "gamecontroller.fill",
        "airplane",
        "music.note"
    ]
    
    public init() {}
    
    public var body: some View {
        NavigationStack {
            ZStack {
                AppColor.paper
                    .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: AppSpacing.lg) {
                        // Group Preview Header
                        previewCard
                        
                        // Group Name Card
                        nameCard
                        
                        // Pastel Color Palette Card
                        colorPickerCard
                        
                        // Icon Picker Card
                        iconPickerCard
                        
                        // Select Members from Friends List Card
                        membersCard
                    }
                    .padding(.horizontal, AppSpacing.lg)
                    .padding(.vertical, AppSpacing.lg)
                }
            }
            .navigationTitle(Text(loc: "friends_create_group"))
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
                        createGroupAction()
                    }) {
                        if isCreating {
                            ProgressView()
                                .tint(AppColor.accent)
                        } else {
                            Text(loc: "action_create")
                                .font(AppTypography.headline())
                                .foregroundColor(groupName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? AppColor.inkTertiary : AppColor.accent)
                        }
                    }
                    .disabled(groupName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isCreating)
                }
            }
        }
    }
    
    // MARK: - Subviews
    
    private var previewCard: some View {
        VStack(spacing: AppSpacing.sm) {
            ZStack {
                Circle()
                    .fill(Color(hexString: selectedColorHex).opacity(0.2))
                    .frame(width: 64, height: 64)
                
                Image(systemName: selectedIcon)
                    .font(.system(size: 28))
                    .foregroundColor(Color(hexString: selectedColorHex))
            }
            
            Text(groupName.isEmpty ? "friends_group_name_placeholder".localized() : groupName)
                .font(AppTypography.title2())
                .foregroundColor(groupName.isEmpty ? AppColor.inkTertiary : AppColor.inkPrimary)
            
            Text("\(selectedMemberUids.count + 1) " + "friends_members_count".localized())
                .font(AppTypography.caption())
                .foregroundColor(AppColor.inkSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, AppSpacing.md)
    }
    
    private var nameCard: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            Text(loc: "friends_group_name")
                .font(AppTypography.captionMedium())
                .foregroundColor(AppColor.inkSecondary)
            
            TextField(
                "friends_group_name_placeholder".localized(),
                text: $groupName
            )
            .font(AppTypography.bodyMedium())
            .foregroundColor(AppColor.inkPrimary)
        }
        .paperCard(padding: AppSpacing.md)
    }
    
    private var colorPickerCard: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            Text(loc: "friends_group_color")
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
                                .frame(width: 30, height: 30)
                            
                            if selectedColorHex == pastel.hexString {
                                Circle()
                                    .stroke(Color.white, lineWidth: 2.5)
                                    .frame(width: 14, height: 14)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .paperCard(padding: AppSpacing.md)
    }
    
    private var iconPickerCard: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            Text(loc: "friends_group_icon")
                .font(AppTypography.captionMedium())
                .foregroundColor(AppColor.inkSecondary)
            
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 6), spacing: 12) {
                ForEach(availableIcons, id: \.self) { icon in
                    let isSelected = selectedIcon == icon
                    Button(action: {
                        selectedIcon = icon
                    }) {
                        ZStack {
                            RoundedRectangle(cornerRadius: AppRadius.sm, style: .continuous)
                                .fill(isSelected ? AppColor.accentLight : AppColor.surfaceSubtle)
                                .frame(height: 40)
                                .overlay(
                                    RoundedRectangle(cornerRadius: AppRadius.sm, style: .continuous)
                                        .stroke(isSelected ? AppColor.accent : Color.clear, lineWidth: 1.5)
                                )
                            
                            Image(systemName: icon)
                                .font(.system(size: 16))
                                .foregroundColor(isSelected ? AppColor.accent : AppColor.inkSecondary)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .paperCard(padding: AppSpacing.md)
    }
    
    private var membersCard: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            HStack {
                Text(loc: "friends_select_members")
                    .font(AppTypography.captionMedium())
                    .foregroundColor(AppColor.inkSecondary)
                
                Spacer()
                
                Text("\(selectedMemberUids.count) \("action_selected".localized())")
                    .font(AppTypography.caption())
                    .foregroundColor(AppColor.inkTertiary)
            }
            
            if friendService.friends.isEmpty {
                VStack(spacing: AppSpacing.xs) {
                    Text(loc: "friends_no_friends_to_add")
                        .font(AppTypography.footnote())
                        .foregroundColor(AppColor.inkTertiary)
                }
                .padding(.vertical, AppSpacing.sm)
            } else {
                VStack(spacing: AppSpacing.xs) {
                    ForEach(friendService.friends) { friend in
                        let isSelected = selectedMemberUids.contains(friend.id)
                        Button(action: {
                            if isSelected {
                                selectedMemberUids.remove(friend.id)
                            } else {
                                selectedMemberUids.insert(friend.id)
                            }
                        }) {
                            HStack(spacing: AppSpacing.md) {
                                // Avatar circle
                                ZStack {
                                    Circle()
                                        .fill(AppColor.accentLight)
                                        .frame(width: 34, height: 34)
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
                                    .font(.system(size: 20))
                                    .foregroundColor(isSelected ? AppColor.accent : AppColor.inkTertiary.opacity(0.5))
                            }
                            .padding(.vertical, 6)
                        }
                        .buttonStyle(.plain)
                        
                        if friend.id != friendService.friends.last?.id {
                            Divider()
                                .background(AppColor.inkBorderSubtle)
                        }
                    }
                }
            }
        }
        .paperCard(padding: AppSpacing.md)
    }
    
    // MARK: - Actions
    
    private func createGroupAction() {
        let trimmed = groupName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        
        isCreating = true
        Task {
            _ = try? await friendService.createGroup(
                name: trimmed,
                colorHex: selectedColorHex,
                iconName: selectedIcon,
                memberUids: Array(selectedMemberUids)
            )
            isCreating = false
            dismiss()
        }
    }
}
