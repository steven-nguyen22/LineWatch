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
    /// Set when the modal is opened from a player-prop row. Drives the
    /// "Points / Rebounds / Assists History" section below the season
    /// averages. nil for non-prop entry points (e.g. moneyline rows).
    var propType: PlayerPropType? = nil

    @Environment(OddsDataService.self) private var dataService

    private var stats: [String: String] {
        dataService.playerStatsByName[playerName] ?? [:]
    }

    /// Cache key into `dataService.playerHitRatesByKey`. Nil when there's no
    /// propType (modal opened from a non-prop entry point).
    private var hitRateCacheKey: String? {
        guard let propType else { return nil }
        return "\(playerName)|\(propType.marketKey)"
    }

    /// Reads through to the app-level cache so re-opening the same modal
    /// inside one session is instant (no Supabase round-trip).
    /// `nil` → not yet fetched (show "···"), `[]` → fetched, no data ("—").
    private var hitRateRows: [HitRateRow]? {
        guard let key = hitRateCacheKey else { return nil }
        return dataService.playerHitRatesByKey[key]
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

    /// Whether to render the Hit Rate History section. Only when:
    /// - Feature is enabled
    /// - The modal was opened with a propType (via player-prop row tap)
    /// - The propType is one we have a backend pipeline for
    ///   (NBA points/reb/ast, MLB hits/strikeouts/home runs,
    ///    NHL goals/shots on goal/hockey points,
    ///    NFL passing/rushing/receiving yards)
    private var showHitRateSection: Bool {
        guard Features.hitRatesEnabled, let propType else { return false }
        return [.points, .rebounds, .assists,
                .hits, .strikeouts, .homeRuns,
                .goals, .shotsOnGoal, .hockeyPoints,
                .passingYards, .rushingYards, .receivingYards].contains(propType)
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

                if showHitRateSection {
                    HitRateHistoryGrid(
                        title: propTitleText,
                        rows: hitRateRows,
                        predicate: \.hit
                    )
                }
            }
            .padding(.bottom, 20)
        }
        .background(AppColors.backgroundPrimary)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.hidden)
        .trackScreen("player_stats_modal", properties: [
            "sport": sport.rawValue,
            "player": playerName
        ])
        .task(id: hitRateTaskKey) {
            await loadHitRateRows()
        }
    }

    // MARK: - Hit Rate History Section

    /// Distinct task ID so SwiftUI re-runs the load when player or prop changes.
    private var hitRateTaskKey: String {
        "\(playerName)|\(propType?.marketKey ?? "none")"
    }

    /// Section title varies by prop — passed through to `HitRateHistoryGrid`.
    private var propTitleText: String {
        guard let propType else { return "Recent History" }
        switch propType {
        case .points:        return "Points History"
        case .rebounds:      return "Rebounds History"
        case .assists:       return "Assists History"
        case .hits:          return "Hits History"
        case .strikeouts:    return "Strikeouts History"
        case .homeRuns:      return "Home Runs History"
        case .goals:         return "Goals History"
        case .shotsOnGoal:   return "Shots on Goal History"
        case .hockeyPoints:  return "Points History"
        case .passingYards:    return "Passing Yards History"
        case .rushingYards:    return "Rushing Yards History"
        case .receivingYards:  return "Receiving Yards History"
        default:             return "Recent History"
        }
    }

    /// Delegates to `OddsDataService.fetchPlayerHitRates` which guards on
    /// cache state — if the (player, propType) combo was already fetched
    /// this session, this call is a no-op. The cached value is read back
    /// via the `hitRateRows` computed property above.
    private func loadHitRateRows() async {
        guard showHitRateSection, let propType else { return }
        await dataService.fetchPlayerHitRates(
            playerName: playerName,
            sportKey: sport.rawValue,
            propType: propType
        )
    }
}
