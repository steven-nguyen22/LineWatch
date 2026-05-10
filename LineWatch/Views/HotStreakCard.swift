//
//  HotStreakCard.swift
//  LineWatch
//
//  Created by Steven Nguyen on 5/9/26.
//
//  One row in the HotStreaksPage. Renders a single ranked streak with:
//   - medal icon (gold/silver/bronze) on the left
//   - team logo or player headshot
//   - display name + description (e.g. "Wins" / "Points Over 25.5")
//   - flame icon + streak count on the right
//
//  The visual chrome matches BestEVCard so Hot Streaks and Best EV feel
//  like siblings on the home screen — same rounded corners, shadow, and
//  green border accent.
//

import SwiftUI
import NukeUI

struct HotStreakCard: View {
    let streak: HotStreak
    @Environment(OddsDataService.self) private var dataService

    /// Gold / silver / bronze for ranks 1 / 2 / 3. Anything beyond falls
    /// back to muted gray (shouldn't happen — page only ever renders 3).
    private var medalColor: Color {
        switch streak.rank {
        case 1: return Color(red: 1.0, green: 0.84, blue: 0.0)    // gold
        case 2: return Color(white: 0.75)                          // silver
        case 3: return Color(red: 0.80, green: 0.50, blue: 0.20)   // bronze
        default: return AppColors.textSecondary
        }
    }

    var body: some View {
        HStack(spacing: 14) {
            // Medal column — rank indicator
            Image(systemName: "medal.fill")
                .font(.system(size: 28))
                .foregroundStyle(medalColor)
                .frame(width: 36)

            // Logo / headshot
            avatarView()
                .frame(width: 44, height: 44)

            // Name + description
            VStack(alignment: .leading, spacing: 2) {
                Text(streak.displayName)
                    .font(AppFonts.headline)
                    .foregroundStyle(AppColors.textPrimary)
                    .lineLimit(1)

                Text(streak.description)
                    .font(AppFonts.caption)
                    .foregroundStyle(AppColors.textSecondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            // Flame + streak count badge
            HStack(spacing: 4) {
                Image(systemName: "flame.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(.orange)

                Text("\(streak.streakCount)")
                    .font(AppFonts.title)
                    .foregroundStyle(AppColors.textPrimary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(AppColors.backgroundCard)
                .shadow(color: AppColors.cardShadow, radius: 6, x: 0, y: 3)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(AppColors.primaryGreen.opacity(0.2), lineWidth: 1)
        )
    }

    // MARK: - Avatar

    /// Branches between team-logo and player-headshot lookups. Image
    /// fetch reuses the URL maps already populated in OddsDataService —
    /// same paths BestEVCard uses for its matchup row.
    @ViewBuilder
    private func avatarView() -> some View {
        if streak.isPlayer, let name = streak.playerName {
            playerHeadshot(name: name)
        } else if let name = streak.teamName {
            teamLogo(name: name)
        } else {
            placeholderIcon()
        }
    }

    @ViewBuilder
    private func teamLogo(name: String) -> some View {
        if let urlStr = dataService.teamLogoURLs[name],
           let url = URL(string: urlStr) {
            LazyImage(url: url) { state in
                if let image = state.image {
                    image.resizable().scaledToFit()
                } else {
                    placeholderIcon()
                }
            }
        } else {
            placeholderIcon()
        }
    }

    @ViewBuilder
    private func playerHeadshot(name: String) -> some View {
        if let urlStr = dataService.playerHeadshotURLs[name],
           let url = URL(string: urlStr) {
            LazyImage(url: url) { state in
                if let image = state.image {
                    image.resizable().scaledToFill()
                } else {
                    Image(systemName: "person.circle.fill")
                        .font(.system(size: 36))
                        .foregroundStyle(AppColors.textSecondary.opacity(0.3))
                }
            }
            .clipShape(Circle())
        } else {
            Image(systemName: "person.circle.fill")
                .font(.system(size: 36))
                .foregroundStyle(AppColors.textSecondary.opacity(0.3))
        }
    }

    @ViewBuilder
    private func placeholderIcon() -> some View {
        Image(systemName: streak.isPlayer ? "person.circle.fill" : "shield.lefthalf.filled")
            .font(.system(size: 32))
            .foregroundStyle(AppColors.textSecondary.opacity(0.4))
    }
}
