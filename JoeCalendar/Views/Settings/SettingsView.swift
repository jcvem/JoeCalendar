//
//  SettingsView.swift
//  JoeCalendar
//
//  Created for JoeCalendar Phase 0 Foundation.
//  Settings tab with live language switcher (zh-Hant, en, ja),
//  auth placeholders, sync toggles, and subscription status.
//

import SwiftUI

public struct SettingsView: View {
    @EnvironmentObject private var localeManager: LocaleManager
    @StateObject private var firebaseService = FirebaseService.shared
    
    @State private var isAppleSyncEnabled: Bool = false
    @State private var isGoogleSyncEnabled: Bool = false
    
    public init() {}
    
    public var body: some View {
        NavigationStack {
            ZStack {
                AppColor.paper
                    .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: AppSpacing.lg) {
                        // Language Switcher Section (Working i18n switcher)
                        languageSection
                        
                        // Account Section
                        accountSection
                        
                        // Subscription Section
                        subscriptionSection
                        
                        // Sync & Integrations
                        syncSection
                        
                        // About App
                        aboutSection
                    }
                    .padding(.horizontal, AppSpacing.lg)
                    .padding(.vertical, AppSpacing.lg)
                }
            }
            .navigationTitle(Text(loc: "settings_title"))
            .navigationBarTitleDisplayMode(.inline)
        }
    }
    
    // MARK: - Language Section
    
    private var languageSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            HStack {
                Image(systemName: "globe")
                    .foregroundColor(AppColor.accent)
                Text(loc: "settings_language")
                    .font(AppTypography.headline())
                    .foregroundColor(AppColor.inkPrimary)
            }
            
            VStack(spacing: 0) {
                ForEach(AppLanguage.allCases) { language in
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            localeManager.selectedLanguage = language
                        }
                    }) {
                        HStack {
                            Text(language.displayName)
                                .font(AppTypography.body())
                                .foregroundColor(AppColor.inkPrimary)
                            
                            Spacer()
                            
                            if localeManager.selectedLanguage == language {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundColor(AppColor.accent)
                            }
                        }
                        .padding(.vertical, AppSpacing.md)
                        .padding(.horizontal, AppSpacing.md)
                    }
                    .buttonStyle(.plain)
                    
                    if language != AppLanguage.allCases.last {
                        Divider()
                            .background(AppColor.inkBorderSubtle)
                            .padding(.leading, AppSpacing.md)
                    }
                }
            }
            .background(AppColor.surface)
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous)
                    .stroke(AppColor.inkBorder, lineWidth: 1)
            )
        }
    }
    
    // MARK: - Account Section
    
    private var accountSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            HStack {
                Image(systemName: "person.crop.circle")
                    .foregroundColor(AppColor.accent)
                Text(loc: "settings_account")
                    .font(AppTypography.headline())
                    .foregroundColor(AppColor.inkPrimary)
            }
            
            VStack(spacing: AppSpacing.sm) {
                if firebaseService.isAuthenticated, let user = firebaseService.currentUser {
                    HStack(spacing: AppSpacing.md) {
                        Circle()
                            .fill(AppColor.accentLight)
                            .frame(width: 44, height: 44)
                            .overlay(
                                Image(systemName: "person.fill")
                                    .foregroundColor(AppColor.accent)
                            )
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text(user.displayName)
                                .font(AppTypography.headline())
                                .foregroundColor(AppColor.inkPrimary)
                            Text(user.email ?? "guest@joecalendar.app")
                                .font(AppTypography.caption())
                                .foregroundColor(AppColor.inkSecondary)
                        }
                        
                        Spacer()
                        
                        Button(action: {
                            firebaseService.signOut()
                        }) {
                            Text("Sign Out")
                                .font(AppTypography.captionMedium())
                                .foregroundColor(AppColor.destructive)
                        }
                    }
                    .paperCard(padding: AppSpacing.md)
                } else {
                    VStack(spacing: AppSpacing.sm) {
                        Button(action: {
                            Task { try? await firebaseService.signIn(with: .apple) }
                        }) {
                            HStack(spacing: 8) {
                                Image(systemName: "applelogo")
                                Text(loc: "settings_sign_in_apple")
                            }
                        }
                        .buttonStyle(TimeTreePrimaryButtonStyle())
                        
                        Button(action: {
                            Task { try? await firebaseService.signIn(with: .google) }
                        }) {
                            HStack(spacing: 8) {
                                Image(systemName: "g.circle.fill")
                                Text(loc: "settings_sign_in_google")
                            }
                        }
                        .buttonStyle(TimeTreeSecondaryButtonStyle())
                    }
                }
            }
        }
    }
    
    // MARK: - Subscription Section
    
    private var subscriptionSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            HStack {
                Image(systemName: "crown.fill")
                    .foregroundColor(AppColor.warning)
                Text(loc: "settings_subscription")
                    .font(AppTypography.headline())
                    .foregroundColor(AppColor.inkPrimary)
            }
            
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(loc: "settings_free_plan")
                        .font(AppTypography.headline())
                        .foregroundColor(AppColor.inkPrimary)
                    Text("Includes social sharing & local feeds with ads")
                        .font(AppTypography.footnote())
                        .foregroundColor(AppColor.inkSecondary)
                }
                
                Spacer()
                
                Button(action: {}) {
                    Text(loc: "settings_upgrade_ad_free")
                        .font(AppTypography.captionMedium())
                }
                .buttonStyle(TimeTreeCapsuleButtonStyle(isSelected: true))
            }
            .paperCard(padding: AppSpacing.md)
        }
    }
    
    // MARK: - Sync Section
    
    private var syncSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            HStack {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .foregroundColor(AppColor.accent)
                Text(loc: "settings_sync_section")
                    .font(AppTypography.headline())
                    .foregroundColor(AppColor.inkPrimary)
            }
            
            VStack(spacing: AppSpacing.md) {
                Toggle(isOn: $isAppleSyncEnabled) {
                    HStack(spacing: AppSpacing.sm) {
                        Image(systemName: "calendar")
                            .foregroundColor(AppColor.inkSecondary)
                        Text(loc: "settings_sync_apple")
                            .font(AppTypography.body())
                            .foregroundColor(AppColor.inkPrimary)
                    }
                }
                .tint(AppColor.accent)
                
                Divider()
                    .background(AppColor.inkBorder)
                
                Toggle(isOn: $isGoogleSyncEnabled) {
                    HStack(spacing: AppSpacing.sm) {
                        Image(systemName: "envelope.circle")
                            .foregroundColor(AppColor.inkSecondary)
                        Text(loc: "settings_sync_google")
                            .font(AppTypography.body())
                            .foregroundColor(AppColor.inkPrimary)
                    }
                }
                .tint(AppColor.accent)
            }
            .paperCard(padding: AppSpacing.md)
        }
    }
    
    // MARK: - About Section
    
    private var aboutSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            HStack {
                Image(systemName: "info.circle")
                    .foregroundColor(AppColor.inkSecondary)
                Text(loc: "settings_about")
                    .font(AppTypography.headline())
                    .foregroundColor(AppColor.inkPrimary)
            }
            
            VStack(spacing: 0) {
                HStack {
                    Text(loc: "settings_version")
                        .font(AppTypography.footnote())
                        .foregroundColor(AppColor.inkSecondary)
                    Spacer()
                }
                .padding(AppSpacing.md)
                
                Divider()
                    .background(AppColor.inkBorderSubtle)
                
                HStack {
                    Text(loc: "settings_privacy_policy")
                        .font(AppTypography.footnote())
                        .foregroundColor(AppColor.accent)
                    Spacer()
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 10))
                        .foregroundColor(AppColor.inkTertiary)
                }
                .padding(AppSpacing.md)
                
                Divider()
                    .background(AppColor.inkBorderSubtle)
                
                HStack {
                    Text(loc: "settings_terms_of_service")
                        .font(AppTypography.footnote())
                        .foregroundColor(AppColor.accent)
                    Spacer()
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 10))
                        .foregroundColor(AppColor.inkTertiary)
                }
                .padding(AppSpacing.md)
            }
            .background(AppColor.surface)
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous)
                    .stroke(AppColor.inkBorder, lineWidth: 1)
            )
        }
    }
}
