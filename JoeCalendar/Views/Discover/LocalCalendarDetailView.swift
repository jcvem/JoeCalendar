//
//  LocalCalendarDetailView.swift
//  JoeCalendar
//
//  Created for JoeCalendar Phase 3 Discover & Monetization.
//  Curated Local Calendar detail view displaying next-30-days events feed,
//  follow/unfollow actions with free-tier limit checks, and back-office editorial notice.
//

import SwiftUI

public struct LocalCalendarDetailView: View {
    public let calendar: LocalCalendar
    @ObservedObject private var discoverService = DiscoverService.shared
    @ObservedObject private var subscriptionService = SubscriptionService.shared
    @EnvironmentObject private var localeManager: LocaleManager
    @Environment(\.openURL) private var openURL
    
    @State private var showingPaywallSheet: Bool = false
    
    public init(calendar: LocalCalendar) {
        self.calendar = calendar
    }
    
    public var body: some View {
        ZStack {
            AppColor.paper
                .ignoresSafeArea()
            
            ScrollView {
                VStack(spacing: AppSpacing.lg) {
                    // Header Banner Card
                    headerCard
                    
                    // 30-Day Sliding Window Notice
                    slidingWindowBanner
                    
                    // Upcoming Events Feed (Next 30 Days)
                    eventsSection
                    
                    // Editorial Operating Team Note (Per P3 Requirements)
                    editorialFooterNote
                }
                .padding(.horizontal, AppSpacing.lg)
                .padding(.vertical, AppSpacing.lg)
            }
        }
        .navigationTitle(calendar.title)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingPaywallSheet) {
            PaywallView()
        }
    }
    
    // MARK: - Header Card
    
    private var headerCard: some View {
        let isFollowed = discoverService.isFollowing(calendar.id)
        
        return VStack(alignment: .leading, spacing: AppSpacing.md) {
            // Category Color Bar
            RoundedRectangle(cornerRadius: AppRadius.xs)
                .fill(calendar.color)
                .frame(height: 4)
            
            HStack {
                // Region badge
                Text(calendar.region)
                    .font(AppTypography.captionMedium())
                    .foregroundColor(AppColor.accent)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(AppColor.accentLight)
                    .clipShape(Capsule())
                
                // Category pill
                Text(calendar.category)
                    .font(AppTypography.caption())
                    .foregroundColor(AppColor.inkSecondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(AppColor.surfaceSubtle)
                    .clipShape(Capsule())
                
                Spacer()
                
                // Followers count
                HStack(spacing: 3) {
                    Image(systemName: "person.2")
                        .font(.system(size: 11))
                    Text("\(calendar.subscriberCount) " + "discover_followers".localized())
                        .font(AppTypography.caption())
                }
                .foregroundColor(AppColor.inkTertiary)
            }
            
            Text(calendar.title)
                .font(AppTypography.title2())
                .foregroundColor(AppColor.inkPrimary)
            
            Text(calendar.description)
                .font(AppTypography.body())
                .foregroundColor(AppColor.inkSecondary)
            
            // Tags
            if !calendar.tags.isEmpty {
                HStack(spacing: 6) {
                    ForEach(calendar.tags, id: \.self) { tag in
                        Text("#\(tag)")
                            .font(AppTypography.caption())
                            .foregroundColor(AppColor.inkTertiary)
                    }
                }
            }
            
            Divider()
                .background(AppColor.inkBorderSubtle)
            
            // Follow Button with Pro limit check
            HStack {
                if isFollowed {
                    Text(loc: "discover_currently_following")
                        .font(AppTypography.caption())
                        .foregroundColor(AppColor.success)
                } else if !subscriptionService.isAdFree && discoverService.followedCalendarIds.count >= DiscoverService.freeTierFollowLimit {
                    HStack(spacing: 3) {
                        Image(systemName: "crown.fill")
                            .font(.system(size: 10))
                            .foregroundColor(AppColor.warning)
                        Text(loc: "discover_free_limit_hint")
                            .font(AppTypography.caption())
                            .foregroundColor(AppColor.inkSecondary)
                    }
                } else {
                    Text(loc: "discover_tap_to_follow_desc")
                        .font(AppTypography.caption())
                        .foregroundColor(AppColor.inkTertiary)
                }
                
                Spacer()
                
                Button(action: {
                    let success = discoverService.toggleFollow(for: calendar)
                    if !success {
                        showingPaywallSheet = true
                    }
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: isFollowed ? "checkmark" : "plus")
                            .font(.system(size: 11, weight: .bold))
                        Text(loc: isFollowed ? "discover_subscribed" : "discover_subscribe")
                            .font(AppTypography.subheadline())
                    }
                }
                .buttonStyle(TimeTreeCapsuleButtonStyle(isSelected: isFollowed))
            }
        }
        .paperCard(padding: AppSpacing.lg)
    }
    
    // MARK: - 14-Day Sliding Window Banner
    
    private var slidingWindowBanner: some View {
        HStack(spacing: AppSpacing.md) {
            Image(systemName: "calendar.badge.clock")
                .font(.system(size: 20))
                .foregroundColor(AppColor.accent)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(loc: "discover_14day_feed")
                    .font(AppTypography.captionMedium())
                    .foregroundColor(AppColor.inkPrimary)
                
                Text(loc: "discover_sliding_window_desc")
                    .font(AppTypography.caption())
                    .foregroundColor(AppColor.inkSecondary)
            }
            Spacer()
        }
        .paperCard(padding: AppSpacing.md)
    }
    
    // MARK: - Events List Section
    
    private var eventsSection: some View {
        let events = discoverService.events(for: calendar.id)
        
        return VStack(alignment: .leading, spacing: AppSpacing.sm) {
            Text(loc: "discover_upcoming_schedule")
                .font(AppTypography.headline())
                .foregroundColor(AppColor.inkPrimary)
            
            if events.isEmpty {
                VStack(spacing: AppSpacing.sm) {
                    Image(systemName: "calendar")
                        .font(.system(size: 28))
                        .foregroundColor(AppColor.inkTertiary)
                    
                    Text(loc: "discover_no_events_in_window")
                        .font(AppTypography.body())
                        .foregroundColor(AppColor.inkSecondary)
                }
                .frame(maxWidth: .infinity)
                .paperCard(padding: AppSpacing.xl)
            } else {
                VStack(spacing: AppSpacing.sm) {
                    ForEach(events) { event in
                        localEventRow(event: event)
                    }
                }
            }
        }
    }
    
    private func localEventRow(event: CalendarEvent) -> some View {
        HStack(alignment: .top, spacing: AppSpacing.md) {
            // Date column
            VStack(spacing: 1) {
                Text(event.startDate, format: .dateTime.month(.abbreviated))
                    .font(AppTypography.caption())
                    .foregroundColor(AppColor.accent)
                Text(event.startDate, format: .dateTime.day())
                    .font(AppTypography.title2())
                    .foregroundColor(AppColor.inkPrimary)
            }
            .frame(width: 44)
            .padding(.vertical, 4)
            .background(AppColor.accentLight)
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.sm, style: .continuous))
            
            // Details
            VStack(alignment: .leading, spacing: 3) {
                Text(event.title)
                    .font(AppTypography.headline())
                    .foregroundColor(AppColor.inkPrimary)
                    .lineLimit(2)
                
                if let loc = event.location {
                    HStack(spacing: 3) {
                        Image(systemName: "mappin.and.ellipse")
                            .font(.system(size: 10))
                        Text(loc)
                            .font(AppTypography.caption())
                            .lineLimit(1)
                    }
                    .foregroundColor(AppColor.inkSecondary)
                }
                
                if let notes = event.notes {
                    Text(notes)
                        .font(AppTypography.footnote())
                        .foregroundColor(AppColor.inkTertiary)
                        .lineLimit(2)
                }
            }
            
            Spacer(minLength: 4)
            
            // Right-side photo thumbnail with gradient overlay and action link
            eventPhotoThumbnail(event: event)
        }
        .paperCard(padding: AppSpacing.md)
    }
    
    @ViewBuilder
    private func eventPhotoThumbnail(event: CalendarEvent) -> some View {
        let validEventUrl: URL? = {
            guard let urlStr = event.eventUrl?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !urlStr.isEmpty,
                  let url = URL(string: urlStr) else {
                return nil
            }
            return url
        }()
        
        let content = ZStack(alignment: .bottom) {
            // Background Image / Gradient Placeholder
            if let coverUrlStr = event.coverImageUrl?.trimmingCharacters(in: .whitespacesAndNewlines),
               !coverUrlStr.isEmpty,
               let coverUrl = URL(string: coverUrlStr) {
                AsyncImage(url: coverUrl) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    case .failure:
                        brandGradientPlaceholder
                    case .empty:
                        ZStack {
                            brandGradientPlaceholder
                            ProgressView()
                                .tint(.white)
                                .scaleEffect(0.7)
                        }
                    @unknown default:
                        brandGradientPlaceholder
                    }
                }
            } else {
                brandGradientPlaceholder
            }
            
            // Tasteful Linear Gradient Overlay (Darker at bottom for label legibility)
            LinearGradient(
                colors: [
                    Color.clear,
                    AppColor.inkPrimary.opacity(0.15),
                    AppColor.inkPrimary.opacity(0.75)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            
            // Bottom Action Link if eventUrl is present
            if validEventUrl != nil {
                HStack(spacing: 2) {
                    Text(loc: "view_event")
                        .font(.system(size: 9, weight: .medium))
                    Text("↗")
                        .font(.system(size: 8, weight: .bold))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Color.black.opacity(0.35))
                .clipShape(Capsule())
                .padding(5)
            }
        }
        .frame(width: 88, height: 88)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.sm, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppRadius.sm, style: .continuous)
                .stroke(AppColor.inkBorderSubtle, lineWidth: 0.5)
        )
        
        if let url = validEventUrl {
            Button(action: {
                openURL(url)
            }) {
                content
            }
            .buttonStyle(.plain)
        } else {
            content
        }
    }
    
    private var brandGradientPlaceholder: some View {
        LinearGradient(
            colors: [
                AppColor.accent,
                Color(hex: 0x1B3845)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .overlay(
            Image(systemName: "photo")
                .font(.system(size: 18))
                .foregroundColor(Color.white.opacity(0.3))
        )
    }
    
    // MARK: - Editorial Back-Office Note
    
    private var editorialFooterNote: some View {
        VStack(spacing: AppSpacing.xs) {
            HStack(spacing: 4) {
                Image(systemName: "shield.lefthalf.filled")
                    .font(.system(size: 11))
                Text(loc: "discover_curated_by_team")
                    .font(AppTypography.captionMedium())
            }
            .foregroundColor(AppColor.inkSecondary)
            
            Text(loc: "discover_curation_admin_notice")
                .font(AppTypography.caption())
                .foregroundColor(AppColor.inkTertiary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, AppSpacing.sm)
    }
}
