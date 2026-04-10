//
//  OnboardingPage.swift
//  LineWatch
//
//  Created by Steven Nguyen on 4/8/26.
//

import SwiftUI
import NukeUI

struct OnboardingPage<Mockup: View>: View {
    let systemImage: String
    var appImage: String? = nil
    let title: String
    let description: String
    var tierBadge: SubscriptionTier? = nil
    @ViewBuilder var mockup: () -> Mockup

    var body: some View {
        VStack(spacing: 14) {
            Spacer()

            // Icon
            if let appImage = appImage {
                Image(appImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 64, height: 64)
                    .clipShape(Circle())
            } else {
                ZStack {
                    Circle()
                        .fill(AppColors.primaryGreen.opacity(0.12))
                        .frame(width: 64, height: 64)

                    Image(systemName: systemImage)
                        .font(.system(size: 28))
                        .foregroundStyle(AppColors.primaryGreen)
                }
            }

            // Title
            Text(title)
                .font(AppFonts.largeTitle)
                .foregroundStyle(AppColors.textPrimary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

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

            // Mini mockup preview
            mockup()
                .padding(.horizontal, 32)

            // Description
            Text(description)
                .font(AppFonts.body)
                .foregroundStyle(AppColors.textSecondary)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
                .padding(.horizontal, 40)

            Spacer()
        }
    }
}

// Convenience init for pages without a mockup
extension OnboardingPage where Mockup == EmptyView {
    init(systemImage: String, appImage: String? = nil, title: String, description: String, tierBadge: SubscriptionTier? = nil) {
        self.systemImage = systemImage
        self.appImage = appImage
        self.title = title
        self.description = description
        self.tierBadge = tierBadge
        self.mockup = { EmptyView() }
    }
}

// MARK: - Mini Mockup Views

/// Mock odds comparison card (for ML/Spreads/Totals page)
struct MockOddsCard: View {
    var body: some View {
        VStack(spacing: 0) {
            // Header with team logos
            HStack(spacing: 4) {
                LazyImage(url: URL(string: "https://a.espncdn.com/i/teamlogos/nba/500/13.png")) { state in
                    if let image = state.image { image.resizable().scaledToFit() }
                }
                .frame(width: 16, height: 16)
                Text("Lakers")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(AppColors.textPrimary)
                Text("@")
                    .font(.system(size: 9))
                    .foregroundStyle(AppColors.textSecondary)
                LazyImage(url: URL(string: "https://a.espncdn.com/i/teamlogos/nba/500/25.png")) { state in
                    if let image = state.image { image.resizable().scaledToFit() }
                }
                .frame(width: 16, height: 16)
                Text("Thunder")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(AppColors.textPrimary)
                Spacer()
                Text("Moneyline")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(AppColors.textSecondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(AppColors.backgroundPrimary.opacity(0.5))

            // Sportsbook rows — green = best, red = worst
            mockOddsRow("DraftKings", away: "+265", home: "-330", awayHighlight: .best, homeHighlight: .worst)
            Divider().foregroundStyle(AppColors.divider)
            mockOddsRow("FanDuel", away: "+250", home: "-310", homeHighlight: .best)
            Divider().foregroundStyle(AppColors.divider)
            mockOddsRow("BetMGM", away: "+240", home: "-320", awayHighlight: .worst)
        }
        .background(AppColors.backgroundCard)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .shadow(color: AppColors.cardShadow, radius: 4, x: 0, y: 2)
    }

    private enum OddsHighlight {
        case best, worst, none
        var color: Color {
            switch self {
            case .best: return AppColors.bestOdds
            case .worst: return AppColors.worstOdds
            case .none: return Color.clear
            }
        }
    }

    private func mockOddsRow(_ book: String, away: String, home: String, awayHighlight: OddsHighlight = .none, homeHighlight: OddsHighlight = .none) -> some View {
        HStack {
            Text(book)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(AppColors.textPrimary)
                .frame(width: 70, alignment: .leading)
            Spacer()
            Text(away)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(AppColors.textPrimary)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(awayHighlight.color)
                .clipShape(RoundedRectangle(cornerRadius: 4))
            Text(home)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(AppColors.textPrimary)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(homeHighlight.color)
                .clipShape(RoundedRectangle(cornerRadius: 4))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
    }
}

/// Mock player prop card (for Player Props page)
struct MockPlayerPropCard: View {
    var body: some View {
        VStack(spacing: 0) {
            // Player header with headshot
            HStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(AppColors.primaryGreen.opacity(0.12))
                        .frame(width: 36, height: 36)
                    LazyImage(url: URL(string: "https://a.espncdn.com/i/headshots/nba/players/full/1966.png")) { state in
                        if let image = state.image {
                            image.resizable().scaledToFill()
                        } else {
                            Image(systemName: "person.circle.fill")
                                .font(.system(size: 34))
                                .foregroundStyle(AppColors.textSecondary.opacity(0.4))
                        }
                    }
                    .frame(width: 36, height: 36)
                    .clipShape(Circle())
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text("LeBron James")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(AppColors.textPrimary)
                    Text("Points")
                        .font(.system(size: 9))
                        .foregroundStyle(AppColors.textSecondary)
                }
                Spacer()
                Text("O/U 25.5")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(AppColors.primaryGreen))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)

            Divider().foregroundStyle(AppColors.divider)

            // Sportsbook rows with green/red highlights
            mockPropRow("DraftKings", over: "-110", under: "-115")
            Divider().foregroundStyle(AppColors.divider)
            mockPropRow("FanDuel", over: "-105", under: "-120", overHighlight: true, underWorst: true)
            Divider().foregroundStyle(AppColors.divider)
            mockPropRow("BetMGM", over: "-115", under: "-108", underHighlight: true, overWorst: true)
        }
        .background(AppColors.backgroundCard)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .shadow(color: AppColors.cardShadow, radius: 4, x: 0, y: 2)
    }

    private func mockPropRow(_ book: String, over: String, under: String, overHighlight: Bool = false, underHighlight: Bool = false, overWorst: Bool = false, underWorst: Bool = false) -> some View {
        HStack {
            Text(book)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(AppColors.textPrimary)
            Spacer()
            HStack(spacing: 12) {
                VStack(spacing: 1) {
                    Text("Over")
                        .font(.system(size: 8))
                        .foregroundStyle(AppColors.textSecondary)
                    Text(over)
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(AppColors.textPrimary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(overHighlight ? AppColors.bestOdds : overWorst ? AppColors.worstOdds : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
                VStack(spacing: 1) {
                    Text("Under")
                        .font(.system(size: 8))
                        .foregroundStyle(AppColors.textSecondary)
                    Text(under)
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(AppColors.textPrimary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(underHighlight ? AppColors.bestOdds : underWorst ? AppColors.worstOdds : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }
}

/// Mock Best EV card (for Best EV page)
struct MockBestEVCard: View {
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                // Green accent
                RoundedRectangle(cornerRadius: 2)
                    .fill(AppColors.primaryGreen)
                    .frame(width: 4, height: 50)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 4) {
                        Image(systemName: "bolt.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(AppColors.primaryGreen)
                        Text("Best EV")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(AppColors.primaryGreen)
                    }
                    Text("Celtics @ Knicks")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(AppColors.textPrimary)
                    Text("Knicks ML  +145 on FanDuel")
                        .font(.system(size: 10))
                        .foregroundStyle(AppColors.textSecondary)
                }

                Spacer()

                VStack(spacing: 2) {
                    Text("+4.2%")
                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                        .foregroundStyle(AppColors.primaryGreen)
                    Text("EV")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(AppColors.textSecondary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            // EV breakdown row
            Divider().foregroundStyle(AppColors.divider).padding(.horizontal, 10)

            HStack(spacing: 0) {
                Image(systemName: "chart.bar.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(AppColors.textSecondary)
                    .padding(.trailing, 4)

                Text("6 books avg: ")
                    .font(.system(size: 10))
                    .foregroundStyle(AppColors.textSecondary)

                Text("+110")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(AppColors.textPrimary)

                Text(" · FanDuel: ")
                    .font(.system(size: 10))
                    .foregroundStyle(AppColors.textSecondary)

                Text("+145")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(AppColors.primaryGreen)

                Text(" — 4.2% edge")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(AppColors.primaryGreen)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .background(AppColors.backgroundCard)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .shadow(color: AppColors.cardShadow, radius: 4, x: 0, y: 2)
    }
}

/// Mock player stats card (for Team & Player Stats page)
struct MockStatsCard: View {
    var body: some View {
        VStack(spacing: 8) {
            // Player header with headshot
            VStack(spacing: 6) {
                ZStack {
                    Circle()
                        .fill(AppColors.primaryGreen.opacity(0.12))
                        .frame(width: 48, height: 48)
                    LazyImage(url: URL(string: "https://a.espncdn.com/i/headshots/nba/players/full/3136193.png")) { state in
                        if let image = state.image {
                            image.resizable().scaledToFill()
                        } else {
                            Image(systemName: "person.circle.fill")
                                .font(.system(size: 44))
                                .foregroundStyle(AppColors.textSecondary.opacity(0.4))
                        }
                    }
                    .frame(width: 48, height: 48)
                    .clipShape(Circle())
                }

                Text("Devin Booker")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(AppColors.textPrimary)

                Text("Phoenix Suns")
                    .font(.system(size: 9))
                    .foregroundStyle(AppColors.textSecondary)

                Text("Season Averages")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(AppColors.primaryGreen)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(
                        Capsule()
                            .fill(AppColors.primaryGreen.opacity(0.12))
                    )
            }
            .padding(.top, 10)

            Divider().foregroundStyle(AppColors.divider).padding(.horizontal, 10)

            // Stat rows
            VStack(spacing: 4) {
                mockStatRow("PPG", value: "27.1")
                mockStatRow("RPG", value: "4.5")
                mockStatRow("APG", value: "6.8")
                mockStatRow("FG%", value: "49.2")
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 8)
        }
        .background(AppColors.backgroundCard)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .shadow(color: AppColors.cardShadow, radius: 4, x: 0, y: 2)
    }

    private func mockStatRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(AppColors.textSecondary)
            Spacer()
            Text(value)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(AppColors.textPrimary)
        }
    }
}

/// Mock bet simulator panel (for Bet Simulator page)
struct MockBetSimulator: View {
    var body: some View {
        VStack(spacing: 8) {
            // Header
            HStack {
                Text("Bet Simulator")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(AppColors.textPrimary)
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.top, 8)

            Divider().foregroundStyle(AppColors.divider).padding(.horizontal, 10)

            // Bet row
            HStack(spacing: 6) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("DraftKings")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(AppColors.textSecondary)
                    Text("Thunder ML -330")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(AppColors.textPrimary)
                }

                Spacer()

                VStack(spacing: 2) {
                    Text("$50")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(AppColors.textPrimary)
                    Text("bet")
                        .font(.system(size: 8))
                        .foregroundStyle(AppColors.textSecondary)
                }

                Image(systemName: "arrow.right")
                    .font(.system(size: 10))
                    .foregroundStyle(AppColors.textSecondary)

                VStack(spacing: 2) {
                    Text("+$15.15")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(AppColors.primaryGreen)
                    Text("payout")
                        .font(.system(size: 8))
                        .foregroundStyle(AppColors.textSecondary)
                }

                // Place bet button
                Text("Place Bet")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(AppColors.primaryGreen)
                    )
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 8)
        }
        .background(AppColors.backgroundCard)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(AppColors.primaryGreen.opacity(0.3), lineWidth: 1)
        )
        .shadow(color: AppColors.cardShadow, radius: 4, x: 0, y: 2)
    }
}

#Preview("Odds") {
    OnboardingPage(
        systemImage: "chart.bar.fill",
        title: "Moneyline, Spreads & Totals",
        description: "View side-by-side odds from every sportsbook. Green highlights show you the best available line."
    ) {
        MockOddsCard()
    }
}

#Preview("Best EV") {
    OnboardingPage(
        systemImage: "bolt.fill",
        title: "Best EV Bets",
        description: "Instantly find the bets with the highest expected value across all sports and markets.",
        tierBadge: .hallOfFame
    ) {
        MockBestEVCard()
    }
}
