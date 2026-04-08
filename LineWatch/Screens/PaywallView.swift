//
//  PaywallView.swift
//  LineWatch
//
//  Created by Steven Nguyen on 4/8/26.
//

import SwiftUI

struct PaywallView: View {
    @Environment(AuthService.self) private var authService
    @State private var billingPeriod: BillingPeriod = .monthly
    @State private var selectedTier: SubscriptionTier = .pro

    enum BillingPeriod: String, CaseIterable {
        case monthly = "Monthly"
        case annual = "Annual"
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Header
                VStack(spacing: 8) {
                    Image(systemName: "crown.fill")
                        .font(.system(size: 44))
                        .foregroundStyle(AppColors.primaryGreen)
                        .padding(.top, 8)

                    Text("Choose Your Plan")
                        .font(AppFonts.largeTitle)
                        .foregroundStyle(AppColors.textPrimary)

                    Text("Unlock premium features to get an edge")
                        .font(AppFonts.body)
                        .foregroundStyle(AppColors.textSecondary)
                }
                .padding(.top, 12)

                // Billing toggle
                Picker("Billing", selection: $billingPeriod) {
                    ForEach(BillingPeriod.allCases, id: \.self) { period in
                        Text(period.rawValue).tag(period)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 40)

                // Horizontal tier cards
                HStack(spacing: 10) {
                    ForEach(SubscriptionTier.allCases, id: \.self) { tier in
                        compactTierCard(tier: tier)
                    }
                }
                .padding(.horizontal, 16)

                // Feature comparison (shared below cards)
                VStack(spacing: 0) {
                    featureComparisonHeader

                    featureComparisonRow("Moneyline, Spreads & Totals", rookie: true, pro: true, hof: true)
                    featureComparisonRow("Player Props", rookie: false, pro: true, hof: true)
                    featureComparisonRow("Best EV Bets", rookie: false, pro: false, hof: true)
                    featureComparisonRow("Team & Player Stats", rookie: false, pro: false, hof: true)
                }
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(AppColors.backgroundCard)
                        .shadow(color: AppColors.cardShadow, radius: 6, x: 0, y: 3)
                )
                .padding(.horizontal, 16)

                // CTA button
                if authService.subscriptionTier == selectedTier {
                    Text("Current Plan")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(AppColors.textSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(AppColors.backgroundPrimary)
                        )
                        .padding(.horizontal, 16)
                } else if selectedTier != .rookie {
                    Button {
                        // Placeholder — will integrate RevenueCat here
                    } label: {
                        Text("Coming Soon")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(AppColors.primaryGreen)
                            )
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 16)
                }

                // Footer note
                Text("Payment integration coming soon.\nPrices shown are planned pricing.")
                    .font(.system(size: 12))
                    .foregroundStyle(AppColors.textSecondary.opacity(0.6))
                    .multilineTextAlignment(.center)
                    .padding(.top, 4)
                    .padding(.bottom, 20)
            }
        }
        .background(AppColors.backgroundPrimary)
        .navigationTitle("Upgrade")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            selectedTier = authService.subscriptionTier == .rookie ? .pro : authService.subscriptionTier
        }
    }

    // MARK: - Compact Tier Card (Horizontal)

    @ViewBuilder
    private func compactTierCard(tier: SubscriptionTier) -> some View {
        let isCurrent = authService.subscriptionTier == tier
        let isSelected = selectedTier == tier

        Button {
            selectedTier = tier
        } label: {
            VStack(spacing: 8) {
                // Badge
                if isCurrent {
                    Text("Current")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(AppColors.primaryGreen))
                } else if tier == .pro {
                    Text("Popular")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.orange))
                } else if billingPeriod == .annual && tier == .hallOfFame {
                    Text("Best Value")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(AppColors.primaryGreen))
                } else {
                    Text(" ")
                        .font(.system(size: 9, weight: .bold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .opacity(0)
                }

                // Tier name
                Text(tier.displayName)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(AppColors.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                // Price
                Text(priceLabel(for: tier))
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundStyle(AppColors.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                // Annual savings
                if billingPeriod == .annual, let savings = tier.annualSavingsPercent {
                    Text("Save \(savings)%")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(AppColors.primaryGreen)
                } else {
                    Text(" ")
                        .font(.system(size: 10))
                        .opacity(0)
                }

                // Selection indicator
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(AppColors.primaryGreen)
                } else {
                    Image(systemName: "circle")
                        .font(.system(size: 18))
                        .foregroundStyle(AppColors.textSecondary.opacity(0.3))
                }
            }
            .padding(.vertical, 14)
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(AppColors.backgroundCard)
                    .shadow(color: AppColors.cardShadow, radius: 4, x: 0, y: 2)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(
                        isSelected ? AppColors.primaryGreen : AppColors.divider,
                        lineWidth: isSelected ? 2 : 1
                    )
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Feature Comparison Table

    private var featureComparisonHeader: some View {
        HStack(spacing: 0) {
            Text("Features")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(AppColors.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)

            ForEach(SubscriptionTier.allCases, id: \.self) { tier in
                Text(tier == .hallOfFame ? "HoF" : tier.displayName)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(AppColors.textSecondary)
                    .frame(width: 50)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(AppColors.backgroundPrimary.opacity(0.5))
    }

    @ViewBuilder
    private func featureComparisonRow(_ title: String, rookie: Bool, pro: Bool, hof: Bool) -> some View {
        let included = [rookie, pro, hof]

        VStack(spacing: 0) {
            Divider().foregroundStyle(AppColors.divider)

            HStack(spacing: 0) {
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(AppColors.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .lineLimit(2)

                ForEach(0..<3, id: \.self) { index in
                    Image(systemName: included[index] ? "checkmark" : "xmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(included[index] ? AppColors.primaryGreen : AppColors.textSecondary.opacity(0.3))
                        .frame(width: 50)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
    }

    // MARK: - Helpers

    private func priceLabel(for tier: SubscriptionTier) -> String {
        switch billingPeriod {
        case .monthly: return tier.monthlyPriceLabel
        case .annual: return tier.annualPriceLabel
        }
    }
}

#Preview {
    NavigationStack {
        PaywallView()
            .environment(AuthService())
    }
}
