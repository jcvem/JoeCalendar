//
//  DiscoverView.swift
//  JoeCalendar
//
//  Created for JoeCalendar Phase 0 Foundation & Extended for Phase 3 Discover & Monetization.
//  Curated Local Calendars (next-14-days window), frequency-capped native promotions,
//  and Pro subscription integration with TimeTree-inspired Japanese calm aesthetic.
//

import SwiftUI

public struct DiscoverView: View {
    @ObservedObject private var discoverService = DiscoverService.shared
    @ObservedObject private var subscriptionService = SubscriptionService.shared
    @EnvironmentObject private var localeManager: LocaleManager
    
    @State private var showingPaywall: Bool = false
    
    // Available region filter tabs
    private let availableRegions = ["all", "Tokyo", "Kyoto", "Taipei", "Osaka"]
    
    public init() {}
    
    public var body: some View {
        NavigationStack {
            ZStack {
                AppColor.paper
                    .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: AppSpacing.lg) {
                        // 1. Search Bar & Region Filters
                        searchAndFilterSection
                        
                        // 2. Section A: Promoted Events (Sponsored ad unit — free tier only)
                        if !discoverService.activePromotions.isEmpty {
                            promotionsSection
                        }
                        
                        // 3. Section B: Followed Local Calendars & 14-Day Feed
                        followedFeedSection
                        
                        // 4. Section C: Curated Local Calendars List
                        curatedCalendarsSection
                        
                        // 5. Section D: Pro Status / Upgrade Banner
                        proBannerSection
                    }
                    .padding(.horizontal, AppSpacing.lg)
                    .padding(.vertical, AppSpacing.lg)
                }
                .refreshable {
                    await discoverService.refreshAll()
                }
            }
            .navigationTitle(Text(loc: "discover_title"))
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showingPaywall) {
                PaywallView()
            }
            .onChange(of: discoverService.showPaywallForLimit) { _, show in
                if show {
                    showingPaywall = true
                    discoverService.showPaywallForLimit = false
                }
            }
        }
    }
    
    // MARK: - Search & Region Filter Section
    
    private var searchAndFilterSection: some View {
        VStack(spacing: AppSpacing.md) {
            // Search Input
            HStack(spacing: AppSpacing.sm) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(AppColor.inkTertiary)
                
                TextField(
                    "discover_search_placeholder".localized(),
                    text: $discoverService.searchQuery
                )
                .font(AppTypography.body())
                
                if !discoverService.searchQuery.isEmpty {
                    Button(action: { discoverService.searchQuery = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(AppColor.inkTertiary)
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
            
            // Region Filter Chips
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: AppSpacing.sm) {
                    ForEach(availableRegions, id: \.self) { region in
                        let isSelected = discoverService.selectedRegion == region
                        Button(action: {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                discoverService.selectedRegion = region
                            }
                        }) {
                            Text(regionTitle(for: region))
                                .font(AppTypography.subheadline())
                                .foregroundColor(isSelected ? .white : AppColor.inkSecondary)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 7)
                                .background(isSelected ? AppColor.accent : AppColor.surface)
                                .clipShape(Capsule())
                                .overlay(
                                    Capsule()
                                        .stroke(isSelected ? AppColor.accent : AppColor.inkBorder, lineWidth: 1)
                                )
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - Section A: Promoted Events (Native Sponsored Ad Unit)
    
    private var promotionsSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            HStack {
                HStack(spacing: 4) {
                    Image(systemName: "megaphone.fill")
                        .font(.system(size: 12))
                        .foregroundColor(AppColor.warning)
                    Text(loc: "discover_promotions_header")
                        .font(AppTypography.headline())
                        .foregroundColor(AppColor.inkPrimary)
                }
                
                Spacer()
                
                Button(action: { showingPaywall = true }) {
                    Text(loc: "discover_hide_ads_pill")
                        .font(AppTypography.captionMedium())
                        .foregroundColor(AppColor.accent)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(AppColor.accentLight)
                        .clipShape(Capsule())
                }
            }
            
            VStack(spacing: AppSpacing.sm) {
                ForEach(discoverService.activePromotions) { promo in
                    PromotedCardView(promotion: promo)
                }
            }
        }
    }
    
    // MARK: - Section B: Followed Local Calendars & Feed
    
    private var followedFeedSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            HStack {
                HStack(spacing: 5) {
                    Image(systemName: "calendar.badge.clock")
                        .font(.system(size: 13))
                        .foregroundColor(AppColor.accent)
                    Text(loc: "discover_followed_feed_title")
                        .font(AppTypography.headline())
                        .foregroundColor(AppColor.inkPrimary)
                }
                
                Spacer()
                
                if !discoverService.followedCalendars.isEmpty {
                    Text("\(discoverService.followedCalendars.count) " + "discover_following_count".localized())
                        .font(AppTypography.caption())
                        .foregroundColor(AppColor.inkTertiary)
                }
            }
            
            if discoverService.followedCalendars.isEmpty {
                // Empty invitation state
                VStack(spacing: AppSpacing.sm) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 24))
                        .foregroundColor(AppColor.accent)
                    
                    Text(loc: "discover_empty_followed_title")
                        .font(AppTypography.headline())
                        .foregroundColor(AppColor.inkPrimary)
                    
                    Text(loc: "discover_empty_followed_desc")
                        .font(AppTypography.footnote())
                        .foregroundColor(AppColor.inkSecondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .paperCard(padding: AppSpacing.lg)
            } else {
                // Followed Calendars Chips
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: AppSpacing.sm) {
                        ForEach(discoverService.followedCalendars) { cal in
                            NavigationLink(destination: LocalCalendarDetailView(calendar: cal)) {
                                HStack(spacing: 5) {
                                    Circle()
                                        .fill(cal.color)
                                        .frame(width: 8, height: 8)
                                    Text(cal.title)
                                        .font(AppTypography.captionMedium())
                                        .foregroundColor(AppColor.inkPrimary)
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(AppColor.surface)
                                .clipShape(Capsule())
                                .overlay(
                                    Capsule().stroke(AppColor.inkBorder, lineWidth: 1)
                                )
                            }
                        }
                    }
                }
                
                // 14-day upcoming events from followed calendars
                let upcoming = discoverService.upcomingFollowedEvents
                if upcoming.isEmpty {
                    Text(loc: "discover_no_upcoming_followed_events")
                        .font(AppTypography.footnote())
                        .foregroundColor(AppColor.inkTertiary)
                        .paperCard(padding: AppSpacing.md)
                } else {
                    VStack(spacing: AppSpacing.xs) {
                        ForEach(upcoming.prefix(4)) { event in
                            followedEventRow(event: event)
                        }
                    }
                }
            }
        }
    }
    
    private func followedEventRow(event: CalendarEvent) -> some View {
        HStack(spacing: AppSpacing.md) {
            // Day badge
            VStack(spacing: 1) {
                Text(event.startDate, format: .dateTime.month(.abbreviated))
                    .font(AppTypography.caption())
                    .foregroundColor(AppColor.accent)
                Text(event.startDate, format: .dateTime.day())
                    .font(AppTypography.subheadline())
                    .foregroundColor(AppColor.inkPrimary)
            }
            .frame(width: 36)
            .padding(.vertical, 3)
            .background(AppColor.accentLight)
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.xs, style: .continuous))
            
            VStack(alignment: .leading, spacing: 2) {
                Text(event.title)
                    .font(AppTypography.subheadline())
                    .foregroundColor(AppColor.inkPrimary)
                    .lineLimit(1)
                
                if let loc = event.location {
                    Text(loc)
                        .font(AppTypography.caption())
                        .foregroundColor(AppColor.inkSecondary)
                        .lineLimit(1)
                }
            }
            
            Spacer()
        }
        .paperCard(padding: AppSpacing.sm)
    }
    
    // MARK: - Section C: Curated Local Calendars
    
    private var curatedCalendarsSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            HStack {
                Text(loc: "discover_local_calendars")
                    .font(AppTypography.headline())
                    .foregroundColor(AppColor.inkPrimary)
                
                Spacer()
                
                Text(loc: "discover_14day_window_badge")
                    .font(AppTypography.caption())
                    .foregroundColor(AppColor.accent)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(AppColor.accentLight)
                    .clipShape(Capsule())
            }
            
            if discoverService.filteredLocalCalendars.isEmpty {
                VStack(spacing: AppSpacing.sm) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 20))
                        .foregroundColor(AppColor.inkTertiary)
                    Text(loc: "discover_no_calendars_found")
                        .font(AppTypography.footnote())
                        .foregroundColor(AppColor.inkSecondary)
                }
                .frame(maxWidth: .infinity)
                .paperCard(padding: AppSpacing.lg)
            } else {
                VStack(spacing: AppSpacing.md) {
                    ForEach(discoverService.filteredLocalCalendars) { cal in
                        NavigationLink(destination: LocalCalendarDetailView(calendar: cal)) {
                            localCalendarCard(cal: cal)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
    
    private func localCalendarCard(cal: LocalCalendar) -> some View {
        let isFollowed = discoverService.isFollowing(cal.id)
        
        return VStack(alignment: .leading, spacing: AppSpacing.sm) {
            // Category Color Bar
            RoundedRectangle(cornerRadius: AppRadius.xs)
                .fill(cal.color)
                .frame(height: 3)
            
            HStack {
                // Region pill
                Text(cal.region)
                    .font(AppTypography.captionMedium())
                    .foregroundColor(AppColor.accent)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(AppColor.accentLight)
                    .clipShape(Capsule())
                
                // Category
                Text(cal.category)
                    .font(AppTypography.caption())
                    .foregroundColor(AppColor.inkSecondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(AppColor.surfaceSubtle)
                    .clipShape(Capsule())
                
                Spacer()
                
                // Subscribers count
                HStack(spacing: 3) {
                    Image(systemName: "person.2")
                        .font(.system(size: 10))
                    Text("\(cal.subscriberCount)")
                        .font(AppTypography.caption())
                }
                .foregroundColor(AppColor.inkTertiary)
            }
            
            Text(cal.title)
                .font(AppTypography.headline())
                .foregroundColor(AppColor.inkPrimary)
            
            Text(cal.description)
                .font(AppTypography.footnote())
                .foregroundColor(AppColor.inkSecondary)
                .lineLimit(2)
            
            HStack {
                // Tags
                HStack(spacing: 4) {
                    ForEach(cal.tags.prefix(3), id: \.self) { tag in
                        Text("#\(tag)")
                            .font(AppTypography.caption())
                            .foregroundColor(AppColor.inkTertiary)
                    }
                }
                
                Spacer()
                
                // Follow Button
                Button(action: {
                    let success = discoverService.toggleFollow(for: cal)
                    if !success {
                        showingPaywall = true
                    }
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: isFollowed ? "checkmark" : "plus")
                            .font(.system(size: 10, weight: .bold))
                        Text(loc: isFollowed ? "discover_subscribed" : "discover_subscribe")
                            .font(AppTypography.captionMedium())
                    }
                }
                .buttonStyle(TimeTreeCapsuleButtonStyle(isSelected: isFollowed))
            }
            .padding(.top, 2)
        }
        .paperCard(padding: AppSpacing.md)
    }
    
    // MARK: - Section D: Pro Status / Upgrade Banner
    
    private var proBannerSection: some View {
        Group {
            if subscriptionService.isAdFree {
                HStack(spacing: AppSpacing.md) {
                    Image(systemName: "crown.fill")
                        .font(.system(size: 20))
                        .foregroundColor(AppColor.warning)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(loc: "settings_pro_active_title")
                            .font(AppTypography.captionMedium())
                            .foregroundColor(AppColor.inkPrimary)
                        Text(loc: "discover_pro_active_desc")
                            .font(AppTypography.footnote())
                            .foregroundColor(AppColor.inkSecondary)
                    }
                    Spacer()
                }
                .paperCard(padding: AppSpacing.md)
            } else {
                Button(action: { showingPaywall = true }) {
                    HStack(spacing: AppSpacing.md) {
                        ZStack {
                            Circle()
                                .fill(AppColor.GroupPastel.yamabuki.bgSubtle)
                                .frame(width: 38, height: 38)
                            Image(systemName: "crown.fill")
                                .font(.system(size: 16))
                                .foregroundColor(AppColor.warning)
                        }
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text(loc: "discover_upgrade_banner_title")
                                .font(AppTypography.headline())
                                .foregroundColor(AppColor.inkPrimary)
                            Text(loc: "discover_upgrade_banner_desc")
                                .font(AppTypography.caption())
                                .foregroundColor(AppColor.inkSecondary)
                        }
                        
                        Spacer()
                        
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12))
                            .foregroundColor(AppColor.inkTertiary)
                    }
                    .paperCard(padding: AppSpacing.md)
                }
                .buttonStyle(.plain)
            }
        }
    }
    
    // MARK: - Helper
    
    private func regionTitle(for code: String) -> String {
        switch code.lowercased() {
        case "all":
            return String.localizedStringWithFormat(NSLocalizedString("discover_region_all", comment: ""))
        case "tokyo":
            return String.localizedStringWithFormat(NSLocalizedString("discover_region_tokyo", comment: ""))
        case "kyoto":
            return String.localizedStringWithFormat(NSLocalizedString("discover_region_kyoto", comment: ""))
        case "taipei":
            return String.localizedStringWithFormat(NSLocalizedString("discover_region_taipei", comment: ""))
        case "osaka":
            return String.localizedStringWithFormat(NSLocalizedString("discover_region_osaka", comment: ""))
        default:
            return code
        }
    }
}
