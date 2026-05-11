//
//  Streak.swift
//  LineWatch
//
//  Created by Steven Nguyen on 5/9/26.
//
//  One row from either the `hot_streaks` or `cold_streaks` table — a
//  single ranked streak for a sport. The struct is direction-agnostic;
//  the caller knows which table the row came from based on which
//  property it pulled from OddsDataService (`hotStreaks` vs
//  `coldStreaks`). Direction is carried separately via `StreakDirection`
//  at the rendering layer.
//
//  Both tables are populated daily by the `compute-hot-streaks` edge
//  function at ~13:30 UTC (after the four post-game graders finish).
//
//  Display fields (`displayName`, `description`) are precomputed by the
//  edge function so the iOS card just renders strings — no formatting
//  logic on the client side.
//
//  Identity: exactly one of `(teamEspnId, teamName)` or
//  `(playerEspnId, playerName)` is non-nil per row. Use `isPlayer` to
//  branch the card UI between team-logo and player-headshot lookups.
//

import Foundation
import SwiftUI

/// Hot vs cold — drives icon, color, tab label, loading copy on the
/// streaks page. Caller pairs a `[Streak]` array with one of these to
/// know how to render and route.
enum StreakDirection: Hashable {
    case hot
    case cold

    /// SF Symbol for the streak count badge on the card.
    var iconName: String {
        switch self {
        case .hot:  return "flame.fill"
        case .cold: return "snowflake"
        }
    }

    /// Foreground color for the badge icon. Matches the per-player
    /// snowflake tile in HitRateHistoryGrid so the visual vocabulary
    /// stays consistent across the app.
    var iconColor: Color {
        switch self {
        case .hot:  return .orange
        case .cold: return .cyan
        }
    }

    /// Label shown in the segmented tab switcher on HotStreaksPage.
    var tabLabel: String {
        switch self {
        case .hot:  return "Hot Streaks"
        case .cold: return "Cold Streaks"
        }
    }

    /// SF Symbol used in the empty state.
    var emptyStateIconName: String {
        switch self {
        case .hot:  return "flame"
        case .cold: return "snowflake"
        }
    }

    /// PostHog screen tag.
    var screenTag: String {
        switch self {
        case .hot:  return "hot_streaks"
        case .cold: return "cold_streaks"
        }
    }

    /// Loading-state copy.
    var loadingCopy: String {
        switch self {
        case .hot:  return "Loading hot streaks…"
        case .cold: return "Loading cold streaks…"
        }
    }
}

struct Streak: Codable, Identifiable, Hashable {
    let id: Int
    let sportKey: String
    let rank: Int
    let streakCount: Int
    let streakType: String          // "wins" | "spread" | <prop_type>
    let teamEspnId: Int?
    let teamName: String?
    let playerEspnId: Int?
    let playerName: String?
    let displayName: String         // e.g. "Lakers" or "James Harden"
    let description: String         // e.g. "Wins" / "Spread" / "Points"
    let lastGameDate: String        // ISO date (YYYY-MM-DD)

    enum CodingKeys: String, CodingKey {
        case id
        case sportKey       = "sport_key"
        case rank
        case streakCount    = "streak_count"
        case streakType     = "streak_type"
        case teamEspnId     = "team_espn_id"
        case teamName       = "team_name"
        case playerEspnId   = "player_espn_id"
        case playerName     = "player_name"
        case displayName    = "display_name"
        case description
        case lastGameDate   = "last_game_date"
    }

    /// `nil` if the sport_key doesn't map to a known SportCategory (e.g.
    /// the backend started populating a sport the iOS client doesn't yet
    /// support). Caller should skip such rows when rendering.
    var sportCategory: SportCategory? {
        SportCategory(rawValue: sportKey)
    }

    /// True when the streak belongs to a player (player props), false
    /// when it belongs to a team (wins or spread).
    var isPlayer: Bool { playerEspnId != nil }

    /// Maps the streak's `streakType` (an Odds API market key like
    /// "player_points" stored on player rows) back to a `PlayerPropType`,
    /// scoped by sport. Sport scoping is required because two enum cases
    /// share the same market key — NBA `.points` and NHL `.hockeyPoints`
    /// both use "player_points" — so a global `init(rawValue:)` lookup
    /// would mismatch on NHL points streaks.
    ///
    /// Returns nil for team streaks (wins/spread) or unknown sport.
    var playerPropType: PlayerPropType? {
        guard isPlayer, let sport = sportCategory else { return nil }
        return PlayerPropType.cases(for: sport).first { $0.marketKey == streakType }
    }
}
