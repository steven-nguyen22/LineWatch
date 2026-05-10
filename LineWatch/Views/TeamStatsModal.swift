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

    /// Sport-specific stat display order. NBA + MLB drop L10 and Streak —
    /// those numbers are now visualized more prominently in the Wins History
    /// grid below, so keeping them up here would just be redundant.
    private var statKeys: [String] {
        switch sport {
        case .basketball:
            return ["Record", "Home", "Road", "Pt Diff"]
        case .baseball:
            return ["Record", "Home", "Road", "RS", "RA"]
        case .hockey:
            return ["Record", "Home", "Road", "L10", "Points", "GF", "GA"]
        case .football:
            return ["Record", "Home", "Road", "Div", "PF", "PA", "Streak"]
        default:
            return Array(stats.keys.sorted())
        }
    }

    /// Wins / Spreads history sections render for sports with a snapshot+grader
    /// pipeline writing to `team_game_results`. Currently NBA and MLB. Other
    /// sports light up automatically once their backend pipeline lands and
    /// they're added here.
    private var showHistorySections: Bool {
        guard Features.hitRatesEnabled else { return false }
        return sport == .basketball || sport == .baseball
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
                    HitRateHistoryGrid(
                        title: "Wins History",
                        rows: teamRows,
                        predicate: \.won
                    )
                    HitRateHistoryGrid(
                        title: "Spreads History",
                        rows: teamRows,
                        predicate: \.covered
                    )
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

    /// Delegates to `OddsDataService.fetchTeamHitRates` which guards on
    /// cache state — re-opening the same team modal in one session is a
    /// no-op. The cached value is read back via the `teamRows` computed
    /// property above. Passes `sport.rawValue` through so the same call
    /// site works for any sport with a hit-rate pipeline.
    private func loadTeamRows() async {
        guard showHistorySections else { return }
        await dataService.fetchTeamHitRates(
            teamName: teamName,
            sportKey: sport.rawValue
        )
    }
}
