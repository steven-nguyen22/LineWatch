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

                // Tier cards
                VStack(spacing: 16) {
                    tierCard(tier: .rookie)
                    tierCard(tier: .pro)
                    tierCard(tier: .hallOfFame)
                }
                .padding(.horizontal, 20)

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
    }

    // MARK: - Tier Card

    @ViewBuilder
    private func tierCard(tier: SubscriptionTier) -> some View {
        let isCurrent = authService.subscriptionTier == tier
        let isRecommended = tier == .pro

        VStack(spacing: 14) {
            // Tier name + badge
            HStack {
                Text(tier.displayName)
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(AppColors.textPrimary)

                if isCurrent {
                    Text("Current")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(
                            Capsule()
                                .fill(AppColors.primaryGreen)
                        )
                } else if isRecommended {
                    Text("Popular")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(
                            Capsule()
                                .fill(Color.orange)
                        )
                }

                Spacer()
            }

            // Price
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(priceLabel(for: tier))
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(AppColors.textPrimary)

                if billingPeriod == .annual, let savings = tier.annualSavingsPercent {
                    Text("Save \(savings)%")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(AppColors.primaryGreen)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(
                            Capsule()
                                .fill(AppColors.primaryGreen.opacity(0.12))
                        )
                }

                Spacer()
            }

            Divider()
                .foregroundStyle(AppColors.divider)

            // Feature list
            VStack(alignment: .leading, spacing: 8) {
                featureRow("Moneyline, Spreads & Totals", included: true)
                featureRow("Player Props", included: tier.canAccessPlayerProps)
                featureRow("Best EV Bets", included: tier.canAccessBestEV)
                featureRow("Team & Player Stats", included: tier.canAccessStats)
            }

            // CTA button
            if isCurrent {
                Text("Current Plan")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(AppColors.textSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(AppColors.backgroundPrimary)
                    )
            } else if tier == .rookie {
                // No button for free tier when user is already on a higher tier
                EmptyView()
            } else {
                Button {
                    // Placeholder — will integrate RevenueCat here
                } label: {
                    Text("Coming Soon")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(AppColors.primaryGreen)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(AppColors.backgroundCard)
                .shadow(color: AppColors.cardShadow, radius: 6, x: 0, y: 3)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(
                    isRecommended ? AppColors.primaryGreen : Color.clear,
                    lineWidth: 2
                )
        )
    }

    // MARK: - Feature Row

    @ViewBuilder
    private func featureRow(_ title: String, included: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: included ? "checkmark.circle.fill" : "lock.fill")
                .font(.system(size: 16))
                .foregroundStyle(included ? AppColors.primaryGreen : AppColors.textSecondary.opacity(0.4))

            Text(title)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(included ? AppColors.textPrimary : AppColors.textSecondary.opacity(0.5))
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
