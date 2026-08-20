//
//  PaywallView.swift
//  JoeCalendar
//
//  Created for JoeCalendar Phase 3 Monetization.
//  StoreKit 2 powered Pro paywall with TimeTree-inspired Japanese calm aesthetic:
//  - 100% Ad-Free experience (removes all promo units)
//  - Unlimited Local Calendar follows
//  - Full access to 14-day curated editorial feeds
//  - Monthly vs Yearly plan selector with discount badge
//  - Restore purchases & App Store Connect fallback handling.
//

import SwiftUI
import StoreKit

public struct PaywallView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var subscriptionService = SubscriptionService.shared
    @EnvironmentObject private var localeManager: LocaleManager
    
    @State private var selectedPlan: SubscriptionPlanType = .yearly
    @State private var showingErrorAlert: Bool = false
    
    public init() {}
    
    public var body: some View {
        NavigationStack {
            ZStack {
                AppColor.paper
                    .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: AppSpacing.xl) {
                        // Header Badge & Hero
                        heroHeader
                        
                        // Feature Benefits Checklist
                        benefitsCard
                        
                        // Plan Selector (Monthly vs Yearly)
                        planSelector
                        
                        // Subscribe CTA Button
                        subscribeButton
                        
                        // Restore & Legal Footer
                        footerLinks
                    }
                    .padding(.horizontal, AppSpacing.lg)
                    .padding(.vertical, AppSpacing.lg)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 20))
                            .foregroundColor(AppColor.inkTertiary)
                    }
                }
            }
            .alert(isPresented: $subscriptionService.purchaseSuccessAlert) {
                Alert(
                    title: Text(loc: "paywall_success_title"),
                    message: Text(loc: "paywall_success_message"),
                    dismissButton: .default(Text(loc: "action_done")) {
                        dismiss()
                    }
                )
            }
            .alert(isPresented: $showingErrorAlert) {
                Alert(
                    title: Text(loc: "paywall_error_title"),
                    message: Text(subscriptionService.errorMessage ?? "An error occurred during purchase."),
                    dismissButton: .default(Text(loc: "action_done"))
                )
            }
            .onChange(of: subscriptionService.errorMessage) { _, newError in
                if newError != nil {
                    showingErrorAlert = true
                }
            }
        }
    }
    
    // MARK: - Hero Header
    
    private var heroHeader: some View {
        VStack(spacing: AppSpacing.sm) {
            ZStack {
                Circle()
                    .fill(AppColor.GroupPastel.yamabuki.bgSubtle)
                    .frame(width: 68, height: 68)
                
                Image(systemName: "crown.fill")
                    .font(.system(size: 32))
                    .foregroundColor(AppColor.warning)
            }
            
            Text(loc: "paywall_title")
                .font(AppTypography.largeTitle())
                .foregroundColor(AppColor.inkPrimary)
            
            Text(loc: "paywall_subtitle")
                .font(AppTypography.body())
                .foregroundColor(AppColor.inkSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, AppSpacing.md)
        }
        .padding(.top, AppSpacing.sm)
    }
    
    // MARK: - Pro Benefits Checklist
    
    private var benefitsCard: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            benefitRow(
                icon: "shield.slash.fill",
                color: AppColor.GroupPastel.akane.color,
                titleKey: "paywall_feature_adfree_title",
                descKey: "paywall_feature_adfree_desc"
            )
            
            Divider()
                .background(AppColor.inkBorderSubtle)
            
            benefitRow(
                icon: "infinity",
                color: AppColor.GroupPastel.sage.color,
                titleKey: "paywall_feature_unlimited_title",
                descKey: "paywall_feature_unlimited_desc"
            )
            
            Divider()
                .background(AppColor.inkBorderSubtle)
            
            benefitRow(
                icon: "sparkles",
                color: AppColor.GroupPastel.yamabuki.color,
                titleKey: "paywall_feature_curated_title",
                descKey: "paywall_feature_curated_desc"
            )
            
            Divider()
                .background(AppColor.inkBorderSubtle)
            
            benefitRow(
                icon: "heart.fill",
                color: AppColor.GroupPastel.sakura.color,
                titleKey: "paywall_feature_craft_title",
                descKey: "paywall_feature_craft_desc"
            )
        }
        .paperCard(padding: AppSpacing.lg)
    }
    
    private func benefitRow(icon: String, color: Color, titleKey: String, descKey: String) -> some View {
        HStack(alignment: .top, spacing: AppSpacing.md) {
            ZStack {
                RoundedRectangle(cornerRadius: AppRadius.sm, style: .continuous)
                    .fill(color.opacity(0.15))
                    .frame(width: 34, height: 34)
                
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(color)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(loc: titleKey)
                    .font(AppTypography.headline())
                    .foregroundColor(AppColor.inkPrimary)
                
                Text(loc: descKey)
                    .font(AppTypography.footnote())
                    .foregroundColor(AppColor.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
    
    // MARK: - Plan Selector
    
    private var planSelector: some View {
        VStack(spacing: AppSpacing.sm) {
            // Yearly Plan (Highlighted Best Value)
            let isYearlySelected = selectedPlan == .yearly
            Button(action: {
                withAnimation(.easeInOut(duration: 0.15)) {
                    selectedPlan = .yearly
                }
            }) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text(loc: "paywall_plan_yearly")
                                .font(AppTypography.headline())
                                .foregroundColor(AppColor.inkPrimary)
                            
                            Text(loc: "paywall_badge_save")
                                .font(AppTypography.captionMedium())
                                .foregroundColor(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(AppColor.success)
                                .clipShape(Capsule())
                        }
                        
                        Text(loc: "paywall_plan_yearly_desc")
                            .font(AppTypography.caption())
                            .foregroundColor(AppColor.inkSecondary)
                    }
                    
                    Spacer()
                    
                    VStack(alignment: .trailing, spacing: 1) {
                        Text(storeKitPrice(for: .yearly))
                            .font(AppTypography.title3())
                            .foregroundColor(AppColor.inkPrimary)
                        
                        Text(loc: "paywall_period_year")
                            .font(AppTypography.caption())
                            .foregroundColor(AppColor.inkTertiary)
                    }
                    
                    Image(systemName: isYearlySelected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 20))
                        .foregroundColor(isYearlySelected ? AppColor.accent : AppColor.inkBorder)
                        .padding(.leading, 6)
                }
                .padding(AppSpacing.md)
                .background(isYearlySelected ? AppColor.accentLight : AppColor.surface)
                .clipShape(RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous)
                        .stroke(isYearlySelected ? AppColor.accent : AppColor.inkBorder, lineWidth: isYearlySelected ? 2 : 1)
                )
            }
            .buttonStyle(.plain)
            
            // Monthly Plan
            let isMonthlySelected = selectedPlan == .monthly
            Button(action: {
                withAnimation(.easeInOut(duration: 0.15)) {
                    selectedPlan = .monthly
                }
            }) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(loc: "paywall_plan_monthly")
                            .font(AppTypography.headline())
                            .foregroundColor(AppColor.inkPrimary)
                        
                        Text(loc: "paywall_plan_monthly_desc")
                            .font(AppTypography.caption())
                            .foregroundColor(AppColor.inkSecondary)
                    }
                    
                    Spacer()
                    
                    VStack(alignment: .trailing, spacing: 1) {
                        Text(storeKitPrice(for: .monthly))
                            .font(AppTypography.title3())
                            .foregroundColor(AppColor.inkPrimary)
                        
                        Text(loc: "paywall_period_month")
                            .font(AppTypography.caption())
                            .foregroundColor(AppColor.inkTertiary)
                    }
                    
                    Image(systemName: isMonthlySelected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 20))
                        .foregroundColor(isMonthlySelected ? AppColor.accent : AppColor.inkBorder)
                        .padding(.leading, 6)
                }
                .padding(AppSpacing.md)
                .background(isMonthlySelected ? AppColor.accentLight : AppColor.surface)
                .clipShape(RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous)
                        .stroke(isMonthlySelected ? AppColor.accent : AppColor.inkBorder, lineWidth: isMonthlySelected ? 2 : 1)
                )
            }
            .buttonStyle(.plain)
        }
    }
    
    // MARK: - Subscribe Action Button
    
    private var subscribeButton: some View {
        VStack(spacing: AppSpacing.xs) {
            Button(action: {
                Task {
                    await handlePurchase()
                }
            }) {
                HStack(spacing: 8) {
                    if subscriptionService.isPurchasing {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Image(systemName: "crown.fill")
                            .font(.system(size: 14))
                        Text(loc: "paywall_cta_subscribe")
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, AppSpacing.md)
                .background(AppColor.accent)
                .foregroundColor(.white)
                .clipShape(RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous))
            }
            .disabled(subscriptionService.isPurchasing)
            
            if !subscriptionService.hasStoreKitProducts {
                Text(loc: "paywall_sandbox_note")
                    .font(AppTypography.caption())
                    .foregroundColor(AppColor.inkTertiary)
                    .multilineTextAlignment(.center)
                    .padding(.top, 2)
            }
        }
    }
    
    // MARK: - Restore Purchases & Legal Footer
    
    private var footerLinks: some View {
        VStack(spacing: AppSpacing.sm) {
            Button(action: {
                Task {
                    try? await subscriptionService.restorePurchases()
                }
            }) {
                if subscriptionService.isRestoring {
                    ProgressView()
                        .scaleEffect(0.8)
                } else {
                    Text(loc: "paywall_restore_purchases")
                        .font(AppTypography.subheadline())
                        .foregroundColor(AppColor.accent)
                }
            }
            
            Text(loc: "paywall_terms_notice")
                .font(AppTypography.caption())
                .foregroundColor(AppColor.inkTertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, AppSpacing.md)
        }
        .padding(.top, AppSpacing.sm)
    }
    
    // MARK: - Helpers
    
    private func storeKitPrice(for plan: SubscriptionPlanType) -> String {
        if let product = subscriptionService.products.first(where: { $0.id == plan.rawValue }) {
            return product.displayPrice
        }
        // Localized fallback price
        switch localeManager.effectiveLanguageCode {
        case "zh-Hant":
            return plan == .monthly ? "NT$90" : "NT$890"
        case "ja":
            return plan == .monthly ? "¥480" : "¥4,800"
        default:
            return plan == .monthly ? "$2.99" : "$29.99"
        }
    }
    
    private func handlePurchase() async {
        if let product = subscriptionService.products.first(where: { $0.id == selectedPlan.rawValue }) {
            _ = try? await subscriptionService.purchase(product)
        } else {
            // App Store Connect products not yet live -> simulate sandbox purchase cleanly
            await subscriptionService.simulateSandboxPurchase(plan: selectedPlan)
        }
    }
}
