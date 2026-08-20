//
//  DiscoverView.swift
//  JoeCalendar
//
//  Created for JoeCalendar Phase 0 Foundation.
//  Discover tab showcasing curated local calendars (next-14-days window)
//  and sponsored highlights.
//

import SwiftUI

public struct DiscoverView: View {
    @EnvironmentObject private var localeManager: LocaleManager
    
    // Sample curated local calendars
    @State private var localCalendars: [LocalCalendar] = [
        LocalCalendar(
            title: "Tokyo Artisan Coffee & Bakeries",
            description: "Editorially curated popups, seasonal roasts, and pastry events in Shibuya & Daikanyama.",
            region: "Tokyo",
            tags: ["Coffee", "Gourmet", "Weekend"],
            subscriberCount: 1420
        ),
        LocalCalendar(
            title: "Kyoto Weekend Flea Markets & Crafts",
            description: "Traditional temple fairs, ceramics, and antique markets for the next 2 weeks.",
            region: "Kyoto",
            tags: ["Crafts", "Antiques", "Culture"],
            subscriberCount: 890
        ),
        LocalCalendar(
            title: "Taipei Indie Music & Livehouse",
            description: "Underground gigs, acoustic sessions, and showcase dates in Gongguan & Ximending.",
            region: "Taipei",
            tags: ["Music", "Live", "Night"],
            subscriberCount: 2150
        )
    ]
    
    @State private var followedCalendarIds: Set<String> = []
    
    public init() {}
    
    public var body: some View {
        NavigationStack {
            ZStack {
                AppColor.paper
                    .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: AppSpacing.lg) {
                        // Banner Header
                        VStack(alignment: .leading, spacing: AppSpacing.xs) {
                            Text(loc: "discover_local_calendars")
                                .font(AppTypography.title2())
                                .foregroundColor(AppColor.inkPrimary)
                            
                            Text(loc: "discover_local_subtitle")
                                .font(AppTypography.subheadline())
                                .foregroundColor(AppColor.inkSecondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        
                        // Curated Local Calendars List
                        VStack(spacing: AppSpacing.md) {
                            ForEach(localCalendars) { cal in
                                localCalendarCard(cal: cal)
                            }
                        }
                        
                        // Sponsored / Promoted Event Card (Ad unit monetization)
                        promotedCard
                        
                        // Phase 3 Notice
                        HStack(spacing: AppSpacing.md) {
                            Image(systemName: "sparkles")
                                .font(.system(size: 20))
                                .foregroundColor(AppColor.accent)
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text(loc: "discover_phase3_badge")
                                    .font(AppTypography.captionMedium())
                                    .foregroundColor(AppColor.inkPrimary)
                                Text(loc: "discover_coming_soon_hint")
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
            .navigationTitle(Text(loc: "discover_title"))
            .navigationBarTitleDisplayMode(.inline)
        }
    }
    
    private func localCalendarCard(cal: LocalCalendar) -> some View {
        let isFollowed = followedCalendarIds.contains(cal.id)
        
        return VStack(alignment: .leading, spacing: AppSpacing.sm) {
            HStack {
                // Region pill
                Text(cal.region)
                    .font(AppTypography.captionMedium())
                    .foregroundColor(AppColor.accent)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(AppColor.accentLight)
                    .clipShape(Capsule())
                
                Spacer()
                
                // 14-day badge
                HStack(spacing: 3) {
                    Image(systemName: "calendar.badge.clock")
                        .font(.system(size: 10))
                    Text(loc: "discover_14day_feed")
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
                    ForEach(cal.tags, id: \.self) { tag in
                        Text("#\(tag)")
                            .font(AppTypography.caption())
                            .foregroundColor(AppColor.inkTertiary)
                    }
                }
                
                Spacer()
                
                // Follow Button
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        if isFollowed {
                            followedCalendarIds.remove(cal.id)
                        } else {
                            followedCalendarIds.insert(cal.id)
                        }
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
            .padding(.top, 4)
        }
        .paperCard(padding: AppSpacing.md)
    }
    
    private var promotedCard: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            HStack {
                Text(loc: "discover_promotions")
                    .font(AppTypography.captionMedium())
                    .foregroundColor(AppColor.warning)
                
                Spacer()
                
                Text(loc: "calendar_type_promo")
                    .font(AppTypography.caption())
                    .foregroundColor(AppColor.inkTertiary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(AppColor.surfaceSubtle)
                    .clipShape(Capsule())
            }
            
            Text(loc: "discover_promo_title")
                .font(AppTypography.headline())
                .foregroundColor(AppColor.inkPrimary)
            
            Text(loc: "discover_promo_desc")
                .font(AppTypography.footnote())
                .foregroundColor(AppColor.inkSecondary)
        }
        .paperCard(padding: AppSpacing.md)
    }
}
