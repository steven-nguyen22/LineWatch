//
//  BestEVCard.swift
//  LineWatch
//
//  Created by Steven Nguyen on 4/6/26.
//

import SwiftUI
import NukeUI

struct BestEVCard: View {
    let bet: BestEVBet
    var sportLabel: String? = nil

    @Environment(OddsDataService.self) private var dataService

    private var headerText: String {
        if let label = sportLabel {
            return "Best Value Bet - \(label)"
        }
        return "Best Value Bet"
    }

    /// Whether this bet features a specific player (props or golf outrights)
    private var isPlayerBet: Bool {
        (bet.marketType == .playerProps && bet.playerName != nil)
        || (bet.marketType == .outrights && bet.event.isGolf)
    }

    /// The player name to display (prop player or golf outright golfer)
    private var displayPlayerName: String? {
        if bet.marketType == .playerProps { return bet.playerName }
        if bet.marketType == .outrights && bet.event.isGolf { return bet.outcomeName }
        return nil
    }

    /// Text to prefill in BetPage's search bar — the golfer/outcome name for
    /// outrights, the player name for props, nothing otherwise.
    private var searchPrefill: String? {
        switch bet.marketType {
        case .outrights:   return bet.outcomeName
        case .playerProps: return bet.playerName
        default:           return nil
        }
    }

    var body: some View {
        NavigationLink(value: AppRoute.eventDetail(
            bet.event,
            bet.marketType,
            searchPrefill,
            bet.propType
        )) {
            VStack(alignment: .leading, spacing: 12) {
                // Top row: badge + EV%
                HStack {
                    HStack(spacing: 5) {
                        Image(systemName: "bolt.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(AppColors.primaryGreen)

                        Text(headerText)
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundStyle(AppColors.primaryGreen)
                    }

                    Spacer()

                    Text("+\(bet.evPercent, specifier: "%.1f")% EV")
                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(
                            Capsule()
                                .fill(AppColors.primaryGreen)
                        )
                }

                // Matchup row: logos + teams (or player headshot for props/golf)
                HStack(spacing: 10) {
                    if isPlayerBet, let playerName = displayPlayerName {
                        // Player prop or golf outright — show player headshot
                        playerHeadshotView(name: playerName)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(playerName)
                                .font(AppFonts.headline)
                                .foregroundStyle(AppColors.textPrimary)
                                .lineLimit(1)

                            Text(bet.betDescription)
                                .font(AppFonts.body)
                                .foregroundStyle(AppColors.textSecondary)
                                .lineLimit(1)
                        }
                    } else if bet.event.isFighting {
                        // Fighting — show fighter headshot for the bet outcome
                        fighterHeadshotView(name: bet.outcomeName)

                        VStack(alignment: .leading, spacing: 2) {
                            if let away = bet.event.awayTeam, let home = bet.event.homeTeam {
                                Text("\(away) vs \(home)")
                                    .font(AppFonts.headline)
                                    .foregroundStyle(AppColors.textPrimary)
                                    .lineLimit(1)
                            } else {
                                Text(bet.event.sportTitle)
                                    .font(AppFonts.headline)
                                    .foregroundStyle(AppColors.textPrimary)
                                    .lineLimit(1)
                            }

                            Text(bet.betDescription)
                                .font(AppFonts.body)
                                .foregroundStyle(AppColors.textSecondary)
                                .lineLimit(1)
                        }
                    } else {
                        // Standard team event — show team logos inline
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                if let away = bet.event.awayTeam {
                                    teamLogoView(name: away)
                                    Text(away)
                                        .font(AppFonts.headline)
                                        .foregroundStyle(AppColors.textPrimary)
                                        .lineLimit(1)
                                }

                                Text(bet.event.awayTeam != nil ? "@" : "")
                                    .font(AppFonts.caption)
                                    .foregroundStyle(AppColors.textSecondary)

                                if let home = bet.event.homeTeam {
                                    teamLogoView(name: home)
                                    Text(home)
                                        .font(AppFonts.headline)
                                        .foregroundStyle(AppColors.textPrimary)
                                        .lineLimit(1)
                                }
                            }

                            Text(bet.betDescription)
                                .font(AppFonts.body)
                                .foregroundStyle(AppColors.textSecondary)
                                .lineLimit(1)
                        }
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(AppColors.textSecondary.opacity(0.5))
                }

                // Transparency / insight row
                Divider()
                    .foregroundStyle(AppColors.divider)

                HStack(spacing: 0) {
                    Image(systemName: "chart.bar.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(AppColors.textSecondary)
                        .padding(.trailing, 5)

                    Text("\(bet.bookmakerCount) books avg: ")
                        .font(.system(size: 12))
                        .foregroundStyle(AppColors.textSecondary)

                    Text(formatOdds(bet.consensusOdds))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(AppColors.textPrimary)

                    Text(" · \(bet.bookmakerTitle): ")
                        .font(.system(size: 12))
                        .foregroundStyle(AppColors.textSecondary)

                    Text(formatOdds(bet.odds))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(AppColors.primaryGreen)

                    let edge = abs(bet.trueProbability - bet.impliedProbability) * 100
                    Text(" — \(edge, specifier: "%.1f")% edge")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(AppColors.primaryGreen)
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
                    .stroke(AppColors.primaryGreen.opacity(0.2), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Image Helpers

    @ViewBuilder
    private func teamLogoView(name: String) -> some View {
        if let logoURL = dataService.teamLogoURLs[name],
           let url = URL(string: logoURL) {
            LazyImage(url: url) { state in
                if let image = state.image {
                    image.resizable().scaledToFit()
                }
            }
            .frame(width: 20, height: 20)
        }
    }

    @ViewBuilder
    private func playerHeadshotView(name: String) -> some View {
        if let headshotURL = dataService.playerHeadshotURLs[name],
           let url = URL(string: headshotURL) {
            LazyImage(url: url) { state in
                if let image = state.image {
                    image.resizable().scaledToFill()
                } else {
                    Image(systemName: "person.circle.fill")
                        .font(.system(size: 32))
                        .foregroundStyle(AppColors.textSecondary.opacity(0.3))
                }
            }
            .frame(width: 36, height: 36)
            .clipShape(Circle())
        } else {
            Image(systemName: "person.circle.fill")
                .font(.system(size: 32))
                .foregroundStyle(AppColors.textSecondary.opacity(0.3))
                .frame(width: 36, height: 36)
        }
    }

    @ViewBuilder
    private func fighterHeadshotView(name: String) -> some View {
        if let headshotURL = dataService.playerHeadshotURLs[name],
           let url = URL(string: headshotURL) {
            LazyImage(url: url) { state in
                if let image = state.image {
                    image.resizable().scaledToFill()
                } else {
                    Image(systemName: "figure.boxing")
                        .font(.system(size: 16))
                        .foregroundStyle(AppColors.primaryGreen)
                }
            }
            .frame(width: 36, height: 36)
            .clipShape(Circle())
            .background(
                Circle()
                    .fill(AppColors.primaryGreen.opacity(0.15))
                    .frame(width: 36, height: 36)
            )
        } else {
            ZStack {
                Circle()
                    .fill(AppColors.primaryGreen.opacity(0.15))
                    .frame(width: 36, height: 36)
                Image(systemName: "figure.boxing")
                    .font(.system(size: 16))
                    .foregroundStyle(AppColors.primaryGreen)
            }
        }
    }

    private func formatOdds(_ odds: Int) -> String {
        odds > 0 ? "+\(odds)" : "\(odds)"
    }
}
