//
//  SettingsView.swift
//  JoeCalendar
//
//  Created for JoeCalendar Phase 0 Foundation & Extended for Phase 1 Core Calendar.
//  Settings tab with live language switcher (zh-Hant, en, ja),
//  Apple EventKit authorization, Google Calendar OAuth sync, and subscriptions.
//

import SwiftUI

public struct SettingsView: View {
    @EnvironmentObject private var localeManager: LocaleManager
    @EnvironmentObject private var eventStore: EventStore
    @StateObject private var firebaseService = FirebaseService.shared
    @StateObject private var eventKitService = EventKitService.shared
    @StateObject private var googleService = GoogleCalendarService.shared
    
    @State private var isGoogleAuthSheetPresented: Bool = false
    @State private var googleEmailInput: String = ""
    
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
                        
                        // Sync & Integrations (EventKit + Google Calendar)
                        syncSection
                        
                        // Account Section
                        accountSection
                        
                        // Subscription Section
                        subscriptionSection
                        
                        // About App
                        aboutSection
                    }
                    .padding(.horizontal, AppSpacing.lg)
                    .padding(.vertical, AppSpacing.lg)
                }
            }
            .navigationTitle(Text(loc: "settings_title"))
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $isGoogleAuthSheetPresented) {
                googleSignInModal
            }
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
    
    // MARK: - Sync Section (EventKit & Google)
    
    private var syncSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            HStack {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .foregroundColor(AppColor.accent)
                Text(loc: "settings_sync_section")
                    .font(AppTypography.headline())
                    .foregroundColor(AppColor.inkPrimary)
                
                Spacer()
                
                Button(action: {
                    Task {
                        await eventStore.syncAll()
                    }
                }) {
                    HStack(spacing: 4) {
                        if eventStore.isSyncing {
                            ProgressView()
                                .scaleEffect(0.7)
                        } else {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 12))
                        }
                        Text(loc: "settings_sync_now")
                            .font(AppTypography.captionMedium())
                    }
                    .foregroundColor(AppColor.accent)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(AppColor.accentLight)
                    .clipShape(Capsule())
                }
            }
            
            VStack(spacing: AppSpacing.md) {
                // Apple Calendar (EventKit)
                VStack(spacing: AppSpacing.sm) {
                    HStack(spacing: AppSpacing.sm) {
                        Image(systemName: "apple.logo")
                            .foregroundColor(AppColor.inkPrimary)
                            .frame(width: 24)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text(loc: "settings_sync_apple")
                                .font(AppTypography.body())
                                .foregroundColor(AppColor.inkPrimary)
                            
                            Text(loc: eventKitService.authStatus.isAuthorized ? "settings_status_connected" : "settings_status_disconnected")
                                .font(AppTypography.caption())
                                .foregroundColor(eventKitService.authStatus.isAuthorized ? AppColor.success : AppColor.inkTertiary)
                        }
                        
                        Spacer()
                        
                        if eventKitService.authStatus.isAuthorized {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(AppColor.success)
                        } else if eventKitService.authStatus == .denied {
                            Button(action: {
                                eventKitService.openSystemSettings()
                            }) {
                                Text(loc: "settings_open_settings")
                                    .font(AppTypography.captionMedium())
                            }
                            .buttonStyle(TimeTreeCapsuleButtonStyle(isSelected: false))
                        } else {
                            Button(action: {
                                Task {
                                    let granted = await eventKitService.requestAuthorization()
                                    if granted {
                                        await eventStore.syncAll()
                                    }
                                }
                            }) {
                                Text(loc: "settings_connect")
                                    .font(AppTypography.captionMedium())
                            }
                            .buttonStyle(TimeTreeCapsuleButtonStyle(isSelected: true))
                        }
                    }
                }
                
                Divider()
                    .background(AppColor.inkBorder)
                
                // Google Calendar (OAuth Sync)
                VStack(spacing: AppSpacing.sm) {
                    HStack(spacing: AppSpacing.sm) {
                        Image(systemName: "g.circle.fill")
                            .foregroundColor(Color(hex: 0x4285F4))
                            .frame(width: 24)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text(loc: "settings_sync_google")
                                .font(AppTypography.body())
                                .foregroundColor(AppColor.inkPrimary)
                            
                            if googleService.isSignedIn, let email = googleService.userEmail {
                                Text(email)
                                    .font(AppTypography.caption())
                                    .foregroundColor(AppColor.success)
                            } else {
                                Text(loc: "settings_status_disconnected")
                                    .font(AppTypography.caption())
                                    .foregroundColor(AppColor.inkTertiary)
                            }
                        }
                        
                        Spacer()
                        
                        if googleService.isSignedIn {
                            Button(action: {
                                googleService.signOut()
                                Task { await eventStore.syncAll() }
                            }) {
                                Text(loc: "settings_disconnect")
                                    .font(AppTypography.captionMedium())
                                    .foregroundColor(AppColor.destructive)
                            }
                            .buttonStyle(TimeTreeCapsuleButtonStyle(isSelected: false))
                        } else {
                            Button(action: {
                                isGoogleAuthSheetPresented = true
                            }) {
                                Text(loc: "settings_connect")
                                    .font(AppTypography.captionMedium())
                            }
                            .buttonStyle(TimeTreeCapsuleButtonStyle(isSelected: true))
                        }
                    }
                }
            }
            .paperCard(padding: AppSpacing.md)
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
                            Text(loc: "settings_sign_out")
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
                    Text(loc: "settings_free_plan_desc")
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
    
    // MARK: - Google Sign-In Sheet
    
    private var googleSignInModal: some View {
        NavigationStack {
            ZStack {
                AppColor.paper.ignoresSafeArea()
                
                VStack(spacing: AppSpacing.lg) {
                    Image(systemName: "g.circle.fill")
                        .font(.system(size: 60))
                        .foregroundColor(Color(hex: 0x4285F4))
                        .padding(.top, AppSpacing.xl)
                    
                    Text(loc: "settings_google_auth_title")
                        .font(AppTypography.title2())
                        .foregroundColor(AppColor.inkPrimary)
                    
                    Text(loc: "settings_google_auth_desc")
                        .font(AppTypography.body())
                        .foregroundColor(AppColor.inkSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, AppSpacing.lg)
                    
                    VStack(alignment: .leading, spacing: AppSpacing.xs) {
                        Text(loc: "settings_google_email_label")
                            .font(AppTypography.captionMedium())
                            .foregroundColor(AppColor.inkSecondary)
                        
                        TextField("user@gmail.com", text: $googleEmailInput)
                            .font(AppTypography.body())
                            .padding(AppSpacing.md)
                            .background(AppColor.surface)
                            .clipShape(RoundedRectangle(cornerRadius: AppRadius.md))
                            .overlay(
                                RoundedRectangle(cornerRadius: AppRadius.md)
                                    .stroke(AppColor.inkBorder, lineWidth: 1)
                            )
                    }
                    .padding(.horizontal, AppSpacing.lg)
                    .padding(.top, AppSpacing.md)
                    
                    Button(action: {
                        let finalEmail = googleEmailInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            ? "user@gmail.com"
                            : googleEmailInput
                        Task {
                            try? await googleService.signIn(email: finalEmail)
                            await eventStore.syncAll()
                            isGoogleAuthSheetPresented = false
                        }
                    }) {
                        Text(loc: "settings_connect")
                    }
                    .buttonStyle(TimeTreePrimaryButtonStyle())
                    .padding(.horizontal, AppSpacing.lg)
                    
                    Spacer()
                }
            }
            .navigationTitle(Text(loc: "settings_sync_google"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(action: { isGoogleAuthSheetPresented = false }) {
                        Text(loc: "action_cancel")
                    }
                }
            }
        }
    }
}
