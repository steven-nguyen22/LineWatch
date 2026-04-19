//
//  LandingPage.swift
//  LineWatch
//
//  Created by Steven Nguyen on 3/9/26.
//

import SwiftUI

struct LandingPage: View {
    @Environment(OddsDataService.self) private var dataService
    @Environment(AuthService.self) private var authService
    @State private var showDisclaimer = false

    private var inSeasonSports: [SportCategory] { SportCategory.inSeason }
    private var offSeasonSports: [SportCategory] { SportCategory.offSeason }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Header
                VStack(spacing: 6) {
                    LineWatchLogo(size: 32)

                    Text("Compare the best odds")
                        .font(AppFonts.body)
                        .foregroundStyle(AppColors.textSecondary)
                }
                .padding(.top, 20)
                .padding(.bottom, 8)

                // Trial banner — visible only during an active free trial
                if authService.isOnTrial, let daysLeft = authService.trialDaysRemaining {
                    NavigationLink(value: AppRoute.paywall) {
                        HStack(spacing: 8) {
                            Image(systemName: "crown.fill")
                                .font(.system(size: 13, weight: .semibold))
                            Text("Free trial · \(daysLeft) day\(daysLeft == 1 ? "" : "s") left")
                                .font(.system(size: 13, weight: .semibold))
                            Image(systemName: "chevron.right")
                                .font(.system(size: 11, weight: .bold))
                                .opacity(0.7)
                        }
                        .foregroundStyle(AppColors.primaryGreen)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(
                            Capsule()
                                .fill(AppColors.primaryGreen.opacity(0.12))
                        )
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 20)
                }

                // Best EV section entry
                NavigationLink(value: authService.effectiveTier.canAccessBestEV ? AppRoute.bestEV : AppRoute.paywall) {
                    HStack(spacing: 16) {
                        ZStack {
                            Circle()
                                .fill(AppColors.primaryGreen)
                                .frame(width: 52, height: 52)

                            Image(systemName: "bolt.fill")
                                .font(.system(size: 24))
                                .foregroundStyle(AppColors.textOnGreen)
                        }

                        Text("Best EV")
                            .font(AppFonts.title)
                            .foregroundStyle(AppColors.textPrimary)

                        Spacer()

                        if !authService.effectiveTier.canAccessBestEV {
                            Image(systemName: "lock.fill")
                                .font(.system(size: 14))
                                .foregroundStyle(AppColors.textSecondary.opacity(0.5))
                        }

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
                .buttonStyle(.plain)
                .padding(.horizontal, 20)

                // In Season
                if !inSeasonSports.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        SectionHeader(title: "In Season", systemImage: "flame.fill")

                        ForEach(inSeasonSports) { sport in
                            NavigationLink(value: AppRoute.sportEvents(sport)) {
                                SportCard(sport: sport)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 20)
                }

                // Off Season
                if !offSeasonSports.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        SectionHeader(title: "Off Season", systemImage: "moon.zzz.fill")

                        ForEach(offSeasonSports) { sport in
                            OffSeasonCard(sport: sport)
                        }
                    }
                    .padding(.horizontal, 20)
                }
            }
            .padding(.bottom, 20)
        }
        .background(AppColors.backgroundPrimary)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                NavigationLink(value: AppRoute.paywall) {
                    Image(systemName: authService.subscriptionTier == .rookie ? "crown" : "crown.fill")
                        .foregroundStyle(AppColors.primaryGreen)
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showDisclaimer = true
                } label: {
                    Image(systemName: "info.circle")
                        .foregroundStyle(AppColors.textSecondary)
                }
            }
        }
        .alert("Disclaimer", isPresented: $showDisclaimer) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Sports betting availability varies by state. Not all sportsbooks are available in all states. Please check your local regulations before placing any bets. You must be 21+ to participate in sports betting.")
        }
        .navigationBarTitleDisplayMode(.inline)
        .trackScreen("landing")
    }
}

// MARK: - Section Header

private struct SectionHeader: View {
    let title: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(title == "In Season" ? AppColors.primaryGreen : AppColors.textSecondary)

            Text(title)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(AppColors.textPrimary)
        }
        .padding(.leading, 4)
    }
}

// MARK: - Sport Card (In Season)

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

// MARK: - Off Season Card (Grayed Out, Disabled)

private struct OffSeasonCard: View {
    let sport: SportCategory

    var body: some View {
        HStack(spacing: 16) {
            // Grayed-out icon circle
            ZStack {
                Circle()
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: 52, height: 52)

                Image(systemName: sport.iconName)
                    .font(.system(size: 24))
                    .foregroundStyle(.gray)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(sport.displayName)
                    .font(AppFonts.title)
                    .foregroundStyle(AppColors.textSecondary)

                Text("Off season")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.gray.opacity(0.7))
            }

            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 20)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(AppColors.backgroundCard)
        )
    }
}

#Preview {
    NavigationStack {
        LandingPage()
            .environment(previewDataService)
            .environment(AuthService())
    }
}
