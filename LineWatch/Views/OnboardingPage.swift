//
//  OnboardingPage.swift
//  LineWatch
//
//  Created by Steven Nguyen on 4/8/26.
//

import SwiftUI

struct OnboardingPage: View {
    let systemImage: String
    let title: String
    let description: String
    var tierBadge: SubscriptionTier? = nil

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            // Icon
            ZStack {
                Circle()
                    .fill(AppColors.primaryGreen.opacity(0.12))
                    .frame(width: 120, height: 120)

                Image(systemName: systemImage)
                    .font(.system(size: 52))
                    .foregroundStyle(AppColors.primaryGreen)
            }

            // Tier badge (if applicable)
            if let tier = tierBadge {
                Text(tier.displayName)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(tier == .pro ? Color.orange : AppColors.primaryGreen)
                    )
            }

            // Title
            Text(title)
                .font(AppFonts.largeTitle)
                .foregroundStyle(AppColors.textPrimary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            // Description
            Text(description)
                .font(AppFonts.body)
                .foregroundStyle(AppColors.textSecondary)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
                .padding(.horizontal, 40)

            Spacer()
            Spacer()
        }
    }
}

#Preview {
    OnboardingPage(
        systemImage: "bolt.fill",
        title: "Best EV Bets",
        description: "Instantly find the bets with the highest expected value across all sports and markets.",
        tierBadge: .hallOfFame
    )
}
