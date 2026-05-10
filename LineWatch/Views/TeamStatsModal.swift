//
//  TeamStatsModal.swift
//  LineWatch
//
//  Created by Steven Nguyen on 4/7/26.
//

import SwiftUI
import NukeUI

struct TeamStatsModal: View {
    let teamName: String
    let sport: SportCategory
    @Environment(OddsDataService.self) private var dataService

    private var stats: [String: String] {
        dataService.teamStatsByName[teamName] ?? [:]
    }

    /// Reads through to the app-level cache so re-opening the same team
    /// inside one session is instant. `nil` → not fetched yet (show "···"),
    /// `[]` → fetched, no data available ("—").
    private var teamRows: [TeamHitRateRow]? {
        dataService.teamHitRatesByName[teamName]
    }

    /// Sport-specific stat display order. NBA drops L10 and Streak — those
    /// numbers are now visualized more prominently in the Wins History grid
    /// below, so keeping them up here would just be redundant.
    private var statKeys: [String] {
        switch sport {
        case .basketball:
            return ["Record", "Home", "Road", "Pt Diff"]
        case .baseball:
            return ["Record", "Home", "Road", "L10", "Streak", "RS", "RA"]
        case .hockey:
            return ["Record", "Home", "Road", "L10", "Points", "GF", "GA"]
        case .football:
            return ["Record", "Home", "Road", "Div", "PF", "PA", "Streak"]
        default:
            return Array(stats.keys.sorted())
        }
    }

    /// Wins / Spreads history sections render only for NBA right now —
    /// other sports don't have a snapshot+grader pipeline writing to
    /// `team_game_results` yet. Gated by the same kill switch as player props.
    private var showHistorySections: Bool {
        Features.hitRatesEnabled && sport == .basketball
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                // Drag indicator
                Capsule()
                    .fill(Color.gray.opacity(0.4))
                    .frame(width: 36, height: 5)
                    .padding(.top, 10)

                // Team logo + name
                VStack(spacing: 10) {
                    if let logoURL = dataService.teamLogoURLs[teamName],
                       let url = URL(string: logoURL) {
                        LazyImage(url: url) { state in
                            if let image = state.image {
                                image.resizable().scaledToFit()
                            }
                        }
                        .frame(width: 72, height: 72)
                    } else {
                        Image(systemName: sport.iconName)
                            .font(.system(size: 40))
                            .foregroundStyle(AppColors.primaryGreen)
                            .frame(width: 72, height: 72)
                    }

                    Text(teamName)
                        .font(AppFonts.title)
                        .foregroundStyle(AppColors.textPrimary)
                        .multilineTextAlignment(.center)

                    Text("\(sport.displayName) \u{2022} Team Stats")
                        .font(AppFonts.caption)
                        .foregroundStyle(AppColors.textSecondary)
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

                if showHistorySections {
                    historySection(title: "Wins History",    predicate: \.won)
                    historySection(title: "Spreads History", predicate: \.covered)
                }
            }
            .padding(.bottom, 20)
        }
        .background(AppColors.backgroundPrimary)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.hidden)
        .trackScreen("team_stats_modal", properties: [
            "sport": sport.rawValue,
            "team": teamName
        ])
        .task(id: teamName) {
            await loadTeamRows()
        }
    }

    // MARK: - History Sections

    /// Generic 2×2 grid driven by a single `KeyPath<TeamHitRateRow, Bool>` so
    /// Wins and Spreads share all the layout/streak code and only differ on
    /// the boolean predicate they pull from each graded row.
    private func historySection(title: String, predicate: KeyPath<TeamHitRateRow, Bool>) -> some View {
        VStack(spacing: 12) {
            Text(title)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(AppColors.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.top, 24)

            VStack(spacing: 12) {
                HStack(spacing: 12) {
                    historyBox(label: "Last 5 Games",  value: fractionText(window: 5,  predicate: predicate))
                    historyBox(label: "Last 10 Games", value: fractionText(window: 10, predicate: predicate))
                }
                HStack(spacing: 12) {
                    historyBox(label: "Last 15 Games", value: fractionText(window: 15, predicate: predicate))
                    streakHistoryBox(predicate: predicate)
                }
            }
            .padding(.horizontal, 16)
        }
    }

    private func historyBox(label: String, value: String) -> some View {
        VStack(spacing: 6) {
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(AppColors.textSecondary)
            Text(value)
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundStyle(AppColors.textPrimary)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
        .background(AppColors.backgroundCard)
        .cornerRadius(12)
    }

    /// Streak box uses SF Symbols (flame.fill / snowflake) instead of emoji
    /// so the icon renders as a color glyph regardless of the surrounding
    /// font design — matches the player-props streak box convention.
    private func streakHistoryBox(predicate: KeyPath<TeamHitRateRow, Bool>) -> some View {
        VStack(spacing: 6) {
            Text("Streak")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(AppColors.textSecondary)
            Group {
                if let rows = teamRows {
                    if rows.isEmpty {
                        Text("—")
                            .font(.system(size: 24, weight: .bold, design: .rounded))
                            .foregroundStyle(AppColors.textPrimary)
                    } else {
                        let parts = streakParts(from: rows, predicate: predicate)
                        HStack(spacing: 5) {
                            Image(systemName: parts.symbol)
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundStyle(parts.color)
                            Text("\(parts.count)")
                                .font(.system(size: 24, weight: .bold, design: .rounded))
                                .foregroundStyle(AppColors.textPrimary)
                                .monospacedDigit()
                        }
                    }
                } else {
                    Text("···")
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundStyle(AppColors.textPrimary)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
        .background(AppColors.backgroundCard)
        .cornerRadius(12)
    }

    // MARK: - Computation

    /// "x/N" with N capped at the window size. Mirrors `PlayerStatsModal.fractionText`
    /// — partial windows are kept honest (a team with 7 graded games shows
    /// L10 and L15 as `x/7`, while L5 caps at `x/5`).
    private func fractionText(window: Int, predicate: KeyPath<TeamHitRateRow, Bool>) -> String {
        guard let rows = teamRows else { return "···" }
        if rows.isEmpty { return "—" }
        let slice = rows.prefix(window)
        let hits = slice.filter { $0[keyPath: predicate] }.count
        return "\(hits)/\(slice.count)"
    }

    /// Walks rows in date-descending order from the most-recent game and
    /// counts consecutive games sharing the same boolean as the most-recent.
    /// Hot streak → flame.fill (orange); cold streak → snowflake (cyan).
    private func streakParts(
        from rows: [TeamHitRateRow],
        predicate: KeyPath<TeamHitRateRow, Bool>
    ) -> StreakParts {
        guard let first = rows.first else {
            return StreakParts(symbol: "minus", color: AppColors.textSecondary, count: 0)
        }
        let firstHit = first[keyPath: predicate]
        var count = 0
        for row in rows {
            if row[keyPath: predicate] == firstHit { count += 1 } else { break }
        }
        return firstHit
            ? StreakParts(symbol: "flame.fill", color: .orange, count: count)
            : StreakParts(symbol: "snowflake",  color: .cyan,   count: count)
    }

    private struct StreakParts {
        let symbol: String
        let color: Color
        let count: Int
    }

    // MARK: - Loading

    /// Delegates to `OddsDataService.fetchTeamHitRates` which guards on
    /// cache state — re-opening the same team modal in one session is a
    /// no-op. The cached value is read back via the `teamRows` computed
    /// property above.
    private func loadTeamRows() async {
        guard showHistorySections else { return }
        await dataService.fetchTeamHitRates(
            teamName: teamName,
            sportKey: "basketball_nba"
        )
    }
}
