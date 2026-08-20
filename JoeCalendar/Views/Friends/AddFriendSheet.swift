//
//  AddFriendSheet.swift
//  JoeCalendar
//
//  Created for JoeCalendar Phase 2 Social Groups.
//  TimeTree-inspired friend finder:
//  - Search by JoeID (@username), email, or name
//  - Share / copy own JoeID card
//  - Instant friend request dispatch
//

import SwiftUI

public struct AddFriendSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var localeManager: LocaleManager
    @ObservedObject private var friendService = FriendService.shared
    
    @State private var searchText: String = ""
    @State private var isCopied: Bool = false
    
    public init() {}
    
    public var body: some View {
        NavigationStack {
            ZStack {
                AppColor.paper
                    .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: AppSpacing.lg) {
                        // Own JoeID Card
                        myJoeIdCard
                        
                        // Search Bar Card
                        searchBarCard
                        
                        // Search Results Section
                        resultsSection
                    }
                    .padding(.horizontal, AppSpacing.lg)
                    .padding(.vertical, AppSpacing.lg)
                }
            }
            .navigationTitle(Text(loc: "friends_add_friend"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(action: { dismiss() }) {
                        Text(loc: "action_done")
                            .font(AppTypography.headline())
                            .foregroundColor(AppColor.accent)
                    }
                }
            }
            .onChange(of: searchText) { _, newValue in
                Task {
                    _ = await friendService.searchUsers(query: newValue)
                }
            }
        }
    }
    
    // MARK: - Subviews
    
    private var myJoeIdCard: some View {
        HStack(spacing: AppSpacing.md) {
            ZStack {
                Circle()
                    .fill(AppColor.accentLight)
                    .frame(width: 44, height: 44)
                
                Image(systemName: "person.crop.circle.badge.checkmark")
                    .font(.system(size: 20))
                    .foregroundColor(AppColor.accent)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(loc: "friends_your_joe_id")
                    .font(AppTypography.caption())
                    .foregroundColor(AppColor.inkSecondary)
                
                Text("@\(friendService.currentUser.joeId ?? "joe_tanaka")")
                    .font(AppTypography.headline())
                    .foregroundColor(AppColor.inkPrimary)
            }
            
            Spacer()
            
            Button(action: {
                #if canImport(UIKit)
                UIPasteboard.general.string = "@\(friendService.currentUser.joeId ?? "joe_tanaka")"
                #endif
                isCopied = true
                Task {
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                    isCopied = false
                }
            }) {
                HStack(spacing: 4) {
                    Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                    Text(loc: isCopied ? "action_copied" : "action_copy")
                }
                .font(AppTypography.captionMedium())
                .foregroundColor(AppColor.accent)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(AppColor.accentLight)
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
        .paperCard(padding: AppSpacing.md)
    }
    
    private var searchBarCard: some View {
        HStack(spacing: AppSpacing.sm) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(AppColor.inkTertiary)
            
            TextField(
                String(localized: "friends_search_placeholder"),
                text: $searchText
            )
            .font(AppTypography.body())
            .foregroundColor(AppColor.inkPrimary)
            .autocapitalization(.none)
            .disableAutocorrection(true)
            
            if !searchText.isEmpty {
                Button(action: {
                    searchText = ""
                    Task {
                        _ = await friendService.searchUsers(query: "")
                    }
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(AppColor.inkTertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, AppSpacing.md)
        .padding(.vertical, AppSpacing.sm + 2)
        .background(AppColor.surface)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous)
                .stroke(AppColor.inkBorder, lineWidth: 1)
        )
    }
    
    private var resultsSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            if searchText.isEmpty {
                VStack(spacing: AppSpacing.sm) {
                    Image(systemName: "person.badge.plus")
                        .font(.system(size: 32))
                        .foregroundColor(AppColor.inkTertiary)
                        .padding(.top, AppSpacing.lg)
                    
                    Text(loc: "friends_search_hint_title")
                        .font(AppTypography.headline())
                        .foregroundColor(AppColor.inkPrimary)
                    
                    Text(loc: "friends_search_hint_desc")
                        .font(AppTypography.footnote())
                        .foregroundColor(AppColor.inkSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, AppSpacing.lg)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, AppSpacing.xl)
            } else if friendService.searchResults.isEmpty {
                VStack(spacing: AppSpacing.sm) {
                    Image(systemName: "questionmark.folder")
                        .font(.system(size: 32))
                        .foregroundColor(AppColor.inkTertiary)
                        .padding(.top, AppSpacing.lg)
                    
                    Text(loc: "friends_no_results")
                        .font(AppTypography.headline())
                        .foregroundColor(AppColor.inkPrimary)
                    
                    Text(loc: "friends_no_results_desc")
                        .font(AppTypography.footnote())
                        .foregroundColor(AppColor.inkSecondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, AppSpacing.xl)
            } else {
                VStack(spacing: AppSpacing.xs) {
                    ForEach(friendService.searchResults) { user in
                        searchResultRow(user: user)
                    }
                }
            }
        }
    }
    
    private func searchResultRow(user: JoeUser) -> some View {
        let status = friendService.friendshipStatus(with: user.id)
        
        return HStack(spacing: AppSpacing.md) {
            ZStack {
                Circle()
                    .fill(AppColor.accentLight)
                    .frame(width: 40, height: 40)
                
                Text(user.displayName.prefix(1).uppercased())
                    .font(AppTypography.headline())
                    .foregroundColor(AppColor.accent)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(user.displayName)
                    .font(AppTypography.bodyMedium())
                    .foregroundColor(AppColor.inkPrimary)
                
                if let joeId = user.joeId {
                    Text("@\(joeId)")
                        .font(AppTypography.caption())
                        .foregroundColor(AppColor.inkTertiary)
                }
            }
            
            Spacer()
            
            // Status Action Button
            if status == .accepted {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark")
                    Text(loc: "friends_status_friends")
                }
                .font(AppTypography.captionMedium())
                .foregroundColor(AppColor.success)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(AppColor.success.opacity(0.12))
                .clipShape(Capsule())
            } else if status == .pending {
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
            } else {
                Button(action: {
                    Task {
                        try? await friendService.sendFriendRequest(to: user)
                    }
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "plus")
                        Text(loc: "friends_send_request")
                    }
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
}
