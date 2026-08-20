//
//  PromotedCardView.swift
//  JoeCalendar
//
//  Created for JoeCalendar Phase 3 Discover & Monetization.
//  Sponsored promotion ad unit rendered only for free-tier users.
//  Clearly labeled with Japanese-restrained styling, frequency capped to 1-2 per session.
//

import SwiftUI

public struct PromotedCardView: View {
    public let promotion: Promotion
    @State private var isDetailSheetPresented: Bool = false
    @Environment(\.openURL) private var openURL
    
    public init(promotion: Promotion) {
        self.promotion = promotion
    }
    
    public var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            // Header: Sponsor Badge + Sponsored Indicator
            HStack {
                HStack(spacing: 5) {
                    Image(systemName: "sparkle")
                        .font(.system(size: 11))
                        .foregroundColor(AppColor.warning)
                    Text(promotion.sponsorName)
                        .font(AppTypography.captionMedium())
                        .foregroundColor(AppColor.inkPrimary)
                }
                
                Spacer()
                
                Text(loc: "discover_sponsored_badge")
                    .font(AppTypography.caption())
                    .foregroundColor(AppColor.inkTertiary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(AppColor.surfaceSubtle)
                    .clipShape(Capsule())
            }
            
            // Promo Title
            Text(promotion.title)
                .font(AppTypography.headline())
                .foregroundColor(AppColor.inkPrimary)
            
            // Subtitle or description
            if let subtitle = promotion.subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(AppTypography.subheadline())
                    .foregroundColor(AppColor.accent)
            }
            
            Text(promotion.description)
                .font(AppTypography.footnote())
                .foregroundColor(AppColor.inkSecondary)
                .lineLimit(3)
            
            // Action Button
            HStack {
                Spacer()
                
                Button(action: {
                    if let urlStr = promotion.actionUrl, let url = URL(string: urlStr) {
                        openURL(url)
                    } else {
                        isDetailSheetPresented = true
                    }
                }) {
                    HStack(spacing: 4) {
                        Text(loc: "discover_promo_learn_more")
                            .font(AppTypography.captionMedium())
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 9, weight: .bold))
                    }
                    .foregroundColor(AppColor.accent)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(AppColor.accentLight)
                    .clipShape(Capsule())
                }
            }
            .padding(.top, 2)
        }
        .paperCard(padding: AppSpacing.md)
        .sheet(isPresented: $isDetailSheetPresented) {
            promotionDetailSheet
        }
    }
    
    // MARK: - Promo Detail Sheet
    
    private var promotionDetailSheet: some View {
        NavigationStack {
            ZStack {
                AppColor.paper.ignoresSafeArea()
                
                ScrollView {
                    VStack(alignment: .leading, spacing: AppSpacing.lg) {
                        HStack {
                            Text(loc: "discover_sponsored_badge")
                                .font(AppTypography.captionMedium())
                                .foregroundColor(AppColor.warning)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(AppColor.GroupPastel.yamabuki.bgSubtle)
                                .clipShape(Capsule())
                            
                            Spacer()
                            
                            Text(promotion.sponsorName)
                                .font(AppTypography.subheadline())
                                .foregroundColor(AppColor.inkSecondary)
                        }
                        
                        Text(promotion.title)
                            .font(AppTypography.title2())
                            .foregroundColor(AppColor.inkPrimary)
                        
                        if let sub = promotion.subtitle {
                            Text(sub)
                                .font(AppTypography.headline())
                                .foregroundColor(AppColor.accent)
                        }
                        
                        Text(promotion.description)
                            .font(AppTypography.body())
                            .foregroundColor(AppColor.inkPrimary)
                        
                        if let urlStr = promotion.actionUrl, let url = URL(string: urlStr) {
                            Button(action: {
                                openURL(url)
                                isDetailSheetPresented = false
                            }) {
                                HStack {
                                    Text(loc: "discover_promo_visit_sponsor")
                                    Image(systemName: "safari")
                                }
                            }
                            .buttonStyle(TimeTreePrimaryButtonStyle())
                            .padding(.top, AppSpacing.md)
                        }
                    }
                    .padding(AppSpacing.lg)
                }
            }
            .navigationTitle(Text(loc: "discover_promotions"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(action: { isDetailSheetPresented = false }) {
                        Text(loc: "action_done")
                    }
                }
            }
        }
    }
}
