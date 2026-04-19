//
//  PlayerStatsModal.swift
//  LineWatch
//
//  Created by Steven Nguyen on 4/7/26.
//

import SwiftUI
import NukeUI

struct PlayerStatsModal: View {
    let playerName: String
    let sport: SportCategory
    @Environment(OddsDataService.self) private var dataService

    private var stats: [String: String] {
        dataService.playerStatsByName[playerName] ?? [:]
    }

    /// Team name from player props data or stats
    private var teamName: String? {
        // Try to find from any event's player_teams mapping
        for (_, mapping) in dataService.playerTeamsByEvent {
            if let team = mapping[playerName] {
                return team
            }
        }
        return nil
    }

    /// Sport-specific stat display order
    private var statKeys: [String] {
        switch sport {
        case .basketball:
            return ["PPG", "RPG", "APG", "FG%", "3P%", "FT%", "SPG", "BPG", "MPG"]
        case .baseball:
            // Detect pitcher vs batter by presence of ERA
            if stats["ERA"] != nil {
                return ["ERA", "W-L", "K", "WHIP", "IP"]
            } else {
                return ["AVG", "HR", "RBI", "OBP", "SLG", "R", "H", "SB"]
            }
        case .hockey:
            return ["G", "A", "PTS", "+/-", "PIM", "SOG", "TOI"]
        case .football:
            // Detect position from available stats
            if stats["Pass Yds"] != nil {
                return ["Pass Yds", "Pass TDs", "INTs", "Rating"]
            } else if stats["Rush Yds"] != nil {
                return ["Rush Yds", "Rush TDs", "YPC"]
            } else {
                return ["Rec Yds", "Rec TDs", "Rec"]
            }
        default:
            return Array(stats.keys.sorted())
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                // Drag indicator
                Capsule()
                    .fill(Color.gray.opacity(0.4))
                    .frame(width: 36, height: 5)
                    .padding(.top, 10)

                // Player headshot + name
                VStack(spacing: 10) {
                    if let headshotURL = dataService.playerHeadshotURLs[playerName],
                       let url = URL(string: headshotURL) {
                        LazyImage(url: url) { state in
                            if let image = state.image {
                                image.resizable().scaledToFill()
                            } else {
                                Image(systemName: "person.circle.fill")
                                    .font(.system(size: 50))
                                    .foregroundStyle(AppColors.textSecondary.opacity(0.3))
                            }
                        }
                        .frame(width: 72, height: 72)
                        .clipShape(Circle())
                    } else {
                        Image(systemName: "person.circle.fill")
                            .font(.system(size: 50))
                            .foregroundStyle(AppColors.textSecondary.opacity(0.3))
                            .frame(width: 72, height: 72)
                    }

                    Text(playerName)
                        .font(AppFonts.title)
                        .foregroundStyle(AppColors.textPrimary)
                        .multilineTextAlignment(.center)

                    if let team = teamName {
                        Text(team)
                            .font(AppFonts.caption)
                            .foregroundStyle(AppColors.textSecondary)
                    }

                    Text("Season Averages")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(AppColors.primaryGreen)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 3)
                        .background(
                            Capsule()
                                .fill(AppColors.primaryGreen.opacity(0.12))
                        )
                }
                .padding(.top, 16)
                .padding(.bottom, 20)

                // Stats rows
                if stats.isEmpty {
                    Text("Stats unavailable")
                        .font(AppFonts.body)
                        .foregroundStyle(AppColors.textSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 40)
                        .background(AppColors.backgroundCard)
                        .cornerRadius(12)
                        .padding(.horizontal, 16)
                } else {
                    VStack(spacing: 0) {
                        ForEach(statKeys, id: \.self) { key in
                            if let value = stats[key] {
                                HStack {
                                    Text(key)
                                        .font(AppFonts.body)
                                        .foregroundStyle(AppColors.textSecondary)
                                    Spacer()
                                    Text(value)
                                        .font(.system(size: 15, weight: .semibold, design: .monospaced))
                                        .foregroundStyle(AppColors.textPrimary)
                                }
                                .padding(.horizontal, 24)
                                .padding(.vertical, 10)

                                if key != statKeys.last {
                                    Divider()
                                        .padding(.horizontal, 24)
                                }
                            }
                        }
                    }
                    .background(AppColors.backgroundCard)
                    .cornerRadius(12)
                    .padding(.horizontal, 16)
                }
            }
            .padding(.bottom, 20)
        }
        .background(AppColors.backgroundPrimary)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.hidden)
    }
}
