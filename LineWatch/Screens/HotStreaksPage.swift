//
//  HotStreaksPage.swift
//  LineWatch
//
//  Created by Steven Nguyen on 5/9/26.
//
//  Discovery surface ranking the top 3 streaks per in-season sport in
//  both directions — hot and cold — via a segmented tab switcher.
//  Reads from the `hot_streaks` and `cold_streaks` tables populated
//  daily by the `compute-hot-streaks` edge function (~13:30 UTC, after
//  the four post-game graders finish).
//
//  Despite hosting both directions, the page is still called "Hot Streaks"
//  in the navigation title and on the home-screen tile — that's the
//  feature's branding. The two tabs are "Hot Streaks" / "Cold Streaks".
//
//  Streaks mix wins, spreads, and player props in a single per-sport
//  ranking. Tap behavior matches Best EV — the card resolves to the
//  team/player's earliest upcoming game and pushes BetPage with the
//  appropriate market preselected:
//    - "wins"   → MarketType.h2h        (Moneyline)
//    - "spread" → MarketType.spreads    (Spread)
//    - prop     → MarketType.playerProps + propType tab + search prefill
//
//  Tap behavior is direction-agnostic — clicking a cold streak still
//  routes to the next upcoming game. The discovery thesis is the same
//  in both directions: a player on a streak (in either direction) is a
//  player worth taking a position on.
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

    /// Active tab. Hot is the default since the page is branded "Hot Streaks".
    @State private var selectedDirection: StreakDirection = .hot

    /// Source array for the currently selected direction. `nil` while loading.
    private var streaks: [Streak]? {
        switch selectedDirection {
        case .hot:  return dataService.hotStreaks
        case .cold: return dataService.coldStreaks
        }
    }

    /// Groups the cached streaks by sport. Returns nil while still loading
    /// (so the body can render a spinner instead of an empty-state).
    private var streaksBySport: [SportCategory: [Streak]]? {
        guard let streaks else { return nil }
        var out: [SportCategory: [Streak]] = [:]
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
                directionPicker

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
            // Kick off both fetches in parallel. Each is cached for the
            // session, so subsequent visits or tab toggles are instant.
            async let hot:  Void = dataService.fetchHotStreaksIfNeeded()
            async let cold: Void = dataService.fetchColdStreaksIfNeeded()
            _ = await (hot, cold)
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
        .trackScreen(selectedDirection.screenTag)
    }

    // MARK: - Tab switcher

    /// Segmented control swapping between hot and cold data sources.
    /// Mirrors the player-prop sub-picker on BetPage for visual parity.
    private var directionPicker: some View {
        Picker("Streak Direction", selection: $selectedDirection) {
            Text(StreakDirection.hot.tabLabel).tag(StreakDirection.hot)
            Text(StreakDirection.cold.tabLabel).tag(StreakDirection.cold)
        }
        .pickerStyle(.segmented)
    }

    // MARK: - Sections

    @ViewBuilder
    private func sportSection(sport: SportCategory, rows: [Streak]) -> some View {
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
    private func cardLink(for streak: Streak) -> some View {
        if let route = resolveRoute(for: streak) {
            NavigationLink(value: route) {
                StreakCard(streak: streak, direction: selectedDirection)
            }
            .buttonStyle(.plain)
        } else {
            Button {
                noGameAlertMessage = noGameMessage(for: streak)
            } label: {
                StreakCard(streak: streak, direction: selectedDirection)
            }
            .buttonStyle(.plain)
        }
    }

    private var loadingState: some View {
        VStack(spacing: 12) {
            ProgressView()
                .scaleEffect(1.2)
            Text(selectedDirection.loadingCopy)
                .font(AppFonts.caption)
                .foregroundStyle(AppColors.textSecondary)
        }
        .padding(.top, 80)
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: selectedDirection.emptyStateIconName)
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

    /// Resolves a Streak to the AppRoute that should be pushed when
    /// the card is tapped. Returns nil when no upcoming game exists for
    /// the streak's team or player (caller renders the alert path).
    ///
    /// Direction-agnostic — clicking a hot or cold streak both route to
    /// the next upcoming game.
    ///
    /// Mapping:
    ///   - "wins"   → .h2h       (Moneyline page)
    ///   - "spread" → .spreads   (Spread page)
    ///   - prop     → .playerProps with prefilled search + prop tab
    private func resolveRoute(for streak: Streak) -> AppRoute? {
        guard let sport = streak.sportCategory,
              let event = earliestUpcomingEvent(for: streak, sport: sport)
        else { return nil }

        let market = marketType(for: streak)
        // Player streaks: prefill the BetPage search bar with the player
        // name so the user lands directly on their row in the prop list.
        let prefill: String? = streak.isPlayer ? streak.playerName : nil
        return AppRoute.eventDetail(event, market, prefill, streak.playerPropType)
    }

    private func marketType(for streak: Streak) -> MarketType {
        switch streak.streakType {
        case "wins":   return .h2h
        case "spread": return .spreads
        default:       return .playerProps
        }
    }

    /// Finds the earliest upcoming odds event involving the streak's team.
    /// Two-stage match — defensive against the team_name column being
    /// NULL on older rows that predate the edge-function change to
    /// populate team_name for player streaks:
    ///
    ///  1. If `streak.teamName` is set → match on `event.homeTeam` /
    ///     `awayTeam`. Works for both team streaks and (post-deploy)
    ///     player streaks. Fast and direct.
    ///
    ///  2. Fallback for player streaks with nil team_name → walk
    ///     `dataService.playerTeamsByEvent` and pick the first upcoming
    ///     event whose roster mapping includes this player. Slower but
    ///     resilient against stale cache rows.
    private func earliestUpcomingEvent(for streak: Streak, sport: SportCategory) -> ResponseBody? {
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

    private func noGameMessage(for streak: Streak) -> String {
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
