//
//  BestEVCard.swift
//  LineWatch
//
//  Created by Steven Nguyen on 4/6/26.
//

import SwiftUI

struct BestEVCard: View {
    let bet: BestEVBet
    var sportLabel: String? = nil

    private var headerText: String {
        if let label = sportLabel {
            return "Best Value Bet - \(label)"
        }
        return "Best Value Bet"
    }

    var body: some View {
        NavigationLink(value: AppRoute.eventDetail(bet.event, bet.marketType, bet.marketType == .outrights ? bet.outcomeName : nil)) {
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

                // Matchup row: sport icon + teams
                HStack(spacing: 10) {
                    ZStack {
                        Circle()
                            .fill(AppColors.primaryGreen.opacity(0.15))
                            .frame(width: 36, height: 36)

                        Image(systemName: bet.sport.iconName)
                            .font(.system(size: 16))
                            .foregroundStyle(AppColors.primaryGreen)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        if let away = bet.event.awayTeam, let home = bet.event.homeTeam {
                            Text("\(away) \(bet.event.isFighting ? "vs" : "@") \(home)")
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

    private func formatOdds(_ odds: Int) -> String {
        odds > 0 ? "+\(odds)" : "\(odds)"
    }
}
