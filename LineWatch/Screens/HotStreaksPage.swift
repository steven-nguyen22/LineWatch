//
//  HotStreaksPage.swift
//  LineWatch
//
//  Created by Steven Nguyen on 5/9/26.
//
//  Discovery surface ranking the top 3 hottest team/player streaks per
//  in-season sport. Reads from the `hot_streaks` table populated daily
//  by the `compute-hot-streaks` edge function (~13:30 UTC, after the
//  four post-game graders finish).
//
//  Streaks mix wins, spreads, and player props in a single per-sport
//  ranking. Tap behavior matches Best EV — the card resolves to the
//  team/player's earliest upcoming game and pushes BetPage with the
//  appropriate market preselected:
//    - "wins"   → MarketType.h2h        (Moneyline)
//    - "spread" → MarketType.spreads    (Spread)
//    - prop     → MarketType.playerProps + propType tab + search prefill
//
//  When no upcoming game exists in the current odds feed (e.g. team is
//  off, snapshot lag, or odds not yet published), tapping shows a small
//  alert instead of pushing.
//

import SwiftUI

struct HotStreaksPage: View {
    @Environment(OddsDataService.self) private var dataService

    /// Sport rendering order — fixed list of sports we have a hit-rate
    /// pipeline for. Sports with no rows in the cache are filtered out
    /// in the body, so off-season sports just don't appear.
    private let sportOrder: [SportCategory] = [.basketball, .baseball, .hockey, .football]

    /// Drives the "no upcoming game" alert. Set when a tap can't resolve
    /// to a current odds event; cleared by the alert dismiss.
    @State private var noGameAlertMessage: String?

    private var streaks: [HotStreak]? {
        dataService.hotStreaks
    }

    /// Groups the cached streaks by sport. Returns nil while still loading
    /// (so the body can render a spinner instead of an empty-state).
    private var streaksBySport: [SportCategory: [HotStreak]]? {
        guard let streaks else { return nil }
        var out: [SportCategory: [HotStreak]] = [:]
        for s in streaks {
            guard let sport = s.sportCategory else { continue }
            out[sport, default: []].append(s)
        }
        // Ensure each sport's array is rank-sorted (server already does
        // this, but defend against the order param being dropped).
        for (sport, rows) in out {
            out[sport] = rows.sorted { $0.rank < $1.rank }
        }
        return out
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                if streaksBySport == nil {
                    loadingState
                } else if let bySport = streaksBySport, bySport.values.allSatisfy(\.isEmpty) || bySport.isEmpty {
                    emptyState
                } else if let bySport = streaksBySport {
                    ForEach(sportOrder.filter { (bySport[$0]?.isEmpty == false) }, id: \.self) { sport in
                        sportSection(sport: sport, rows: bySport[sport] ?? [])
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 24)
        }
        .background(AppColors.backgroundPrimary)
        .navigationTitle("Hot Streaks")
        .navigationBarTitleDisplayMode(.large)
        .task {
            await dataService.fetchHotStreaksIfNeeded()
        }
        .alert(
            "No upcoming game",
            isPresented: Binding(
                get: { noGameAlertMessage != nil },
                set: { if !$0 { noGameAlertMessage = nil } }
            ),
            actions: {
                Button("OK", role: .cancel) { noGameAlertMessage = nil }
            },
            message: {
                Text(noGameAlertMessage ?? "")
            }
        )
        .trackScreen("hot_streaks")
    }

    // MARK: - Sections

    @ViewBuilder
    private func sportSection(sport: SportCategory, rows: [HotStreak]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: sport.iconName)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(AppColors.primaryGreen)

                Text(sport.displayName)
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(AppColors.textPrimary)
            }
            .padding(.leading, 4)

            VStack(spacing: 12) {
                ForEach(rows) { streak in
                    cardLink(for: streak)
                }
            }
        }
    }

    /// Resolves the streak's destination at render time. If we can find
    /// the team's/player's earliest upcoming event, render a NavigationLink
    /// that pushes BetPage with the appropriate market. Otherwise render
    /// a Button that triggers the "no upcoming game" alert.
    @ViewBuilder
    private func cardLink(for streak: HotStreak) -> some View {
        if let route = resolveRoute(for: streak) {
            NavigationLink(value: route) {
                HotStreakCard(streak: streak)
            }
            .buttonStyle(.plain)
        } else {
            Button {
                noGameAlertMessage = noGameMessage(for: streak)
            } label: {
                HotStreakCard(streak: streak)
            }
            .buttonStyle(.plain)
        }
    }

    private var loadingState: some View {
        VStack(spacing: 12) {
            ProgressView()
                .scaleEffect(1.2)
            Text("Loading hot streaks…")
                .font(AppFonts.caption)
                .foregroundStyle(AppColors.textSecondary)
        }
        .padding(.top, 80)
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "flame")
                .font(.system(size: 48))
                .foregroundStyle(AppColors.textSecondary.opacity(0.5))

            Text("No streaks yet")
                .font(AppFonts.title)
                .foregroundStyle(AppColors.textSecondary)

            Text("Check back after the next round of games — streaks update daily once results are graded.")
                .font(AppFonts.body)
                .foregroundStyle(AppColors.textSecondary.opacity(0.7))
                .multilineTextAlignment(.center)
        }
        .padding(.top, 80)
        .padding(.horizontal, 40)
    }

    // MARK: - Routing

    /// Resolves a HotStreak to the AppRoute that should be pushed when
    /// the card is tapped. Returns nil when no upcoming game exists for
    /// the streak's team or player (caller renders the alert path).
    ///
    /// Mapping:
    ///   - "wins"   → .h2h       (Moneyline page)
    ///   - "spread" → .spreads   (Spread page)
    ///   - prop     → .playerProps with prefilled search + prop tab
    private func resolveRoute(for streak: HotStreak) -> AppRoute? {
        guard let sport = streak.sportCategory,
              let event = earliestUpcomingEvent(for: streak, sport: sport)
        else { return nil }

        let market = marketType(for: streak)
        // Player streaks: prefill the BetPage search bar with the player
        // name so the user lands directly on their row in the prop list.
        let prefill: String? = streak.isPlayer ? streak.playerName : nil
        return AppRoute.eventDetail(event, market, prefill, streak.playerPropType)
    }

    private func marketType(for streak: HotStreak) -> MarketType {
        switch streak.streakType {
        case "wins":   return .h2h
        case "spread": return .spreads
        default:       return .playerProps
        }
    }

    /// Finds the earliest upcoming odds event involving the streak's team.
    /// Two-stage match — defensive against the team_name column being
    /// NULL on older hot_streaks rows that predate the edge-function
    /// change to populate team_name for player streaks:
    ///
    ///  1. If `streak.teamName` is set → match on `event.homeTeam` /
    ///     `awayTeam`. Works for both team streaks and (post-deploy)
    ///     player streaks. Fast and direct.
    ///
    ///  2. Fallback for player streaks with nil team_name → walk
    ///     `dataService.playerTeamsByEvent` and pick the first upcoming
    ///     event whose roster mapping includes this player. Slower but
    ///     resilient against stale cache rows.
    private func earliestUpcomingEvent(for streak: HotStreak, sport: SportCategory) -> ResponseBody? {
        let now = Date()
        let formatter = ISO8601DateFormatter()

        // Build (event, kickoff) tuples for all upcoming events in the sport,
        // sorted earliest-first — both lookup paths consume this list.
        let upcoming: [(event: ResponseBody, date: Date)] = dataService.events(for: sport)
            .compactMap { event in
                guard let iso = event.commenceTime,
                      let date = formatter.date(from: iso),
                      date >= now
                else { return nil }
                return (event, date)
            }
            .sorted { $0.date < $1.date }

        // ---- Path 1: team_name on the streak row (fast path) ----
        if let teamName = streak.teamName {
            if let hit = upcoming.first(where: {
                $0.event.homeTeam == teamName || $0.event.awayTeam == teamName
            }) {
                return hit.event
            }
        }

        // ---- Path 2: player streak with nil team_name → roster lookup ----
        if streak.isPlayer, let playerName = streak.playerName {
            for (event, _) in upcoming {
                if let roster = dataService.playerTeamsByEvent[event.id],
                   roster[playerName] != nil {
                    return event
                }
            }
        }

        return nil
    }

    private func noGameMessage(for streak: HotStreak) -> String {
        let who = streak.displayName
        return "\(who) has no upcoming game in the current odds feed. Check back later — odds are usually published 1–2 days before kickoff."
    }
}

#if DEBUG
#Preview {
    NavigationStack {
        HotStreaksPage()
            .environment(previewDataService)
    }
}
#endif
