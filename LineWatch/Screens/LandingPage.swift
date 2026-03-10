//
//  LandingPage.swift
//  LineWatch
//
//  Created by Steven Nguyen on 3/9/26.
//

import SwiftUI

struct LandingPage: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Header
                VStack(spacing: 6) {
                    Text("LineWatch")
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .foregroundStyle(AppColors.darkGreen)

                    Text("Compare the best odds")
                        .font(AppFonts.body)
                        .foregroundStyle(AppColors.textSecondary)
                }
                .padding(.top, 20)
                .padding(.bottom, 8)

                // Sport Category Cards
                VStack(spacing: 16) {
                    ForEach(SportCategory.allCases) { sport in
                        NavigationLink(value: AppRoute.sportEvents(sport)) {
                            SportCard(sport: sport)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 20)
            }
        }
        .background(AppColors.backgroundPrimary)
        .navigationBarHidden(true)
    }
}

// MARK: - Sport Card

private struct SportCard: View {
    let sport: SportCategory

    var body: some View {
        HStack(spacing: 16) {
            // Icon circle
            ZStack {
                Circle()
                    .fill(AppColors.primaryGreen)
                    .frame(width: 52, height: 52)

                Image(systemName: sport.iconName)
                    .font(.system(size: 24))
                    .foregroundStyle(AppColors.textOnGreen)
            }

            Text(sport.displayName)
                .font(AppFonts.title)
                .foregroundStyle(AppColors.textPrimary)

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(AppColors.textSecondary.opacity(0.5))
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 20)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(AppColors.backgroundCard)
                .shadow(color: AppColors.cardShadow, radius: 6, x: 0, y: 3)
        )
    }
}

#Preview {
    NavigationStack {
        LandingPage()
    }
}
