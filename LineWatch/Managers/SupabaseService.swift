//
//  SupabaseService.swift
//  LineWatch
//
//  Created by Steven Nguyen on 3/27/26.
//

import Foundation
import Supabase

class SupabaseService {
    private let baseURL = "https://voxokcdwctpvzbqigklw.supabase.co/rest/v1"
    private let apiKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InZveG9rY2R3Y3RwdnpicWlna2x3Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzQ2NTg4ODYsImV4cCI6MjA5MDIzNDg4Nn0.lGh1rKpR8kt3MPJnSe4VXdR_b1mmOT9x6xLvFmhiPnw"

    /// Fetches cached odds from Supabase for a given sport key.
    /// Returns the decoded array of events, or throws on failure.
    func fetchCachedOdds(sportKey: String) async throws -> [ResponseBody] {
        let endpoint = "\(baseURL)/cached_odds?sport_key=eq.\(sportKey)&select=data"

        guard let url = URL(string: endpoint) else {
            throw GHError.invalidURL
        }

        var request = URLRequest(url: url)
        request.setValue(apiKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw GHError.invalidResponse
        }

        // Supabase REST API returns an array of rows: [{ "data": [...events...] }]
        let rows = try JSONDecoder().decode([CachedOddsRow].self, from: data)
        guard let events = rows.first?.data else {
            return []
        }
        return events
    }

    /// Fetches the cached Kalshi-derived events for a given Odds API sport key.
    /// Pass the plain sport key (e.g. `"basketball_nba"`) — this prepends
    /// `"kalshi_"` internally to hit the parallel row written by fetch-kalshi-odds.
    /// Throws on network/decode errors; callers should catch and treat absence
    /// as "no Kalshi data" so a Kalshi outage never degrades the main odds feed.
    func fetchKalshiEvents(sportKey: String) async throws -> [KalshiEvent] {
        let endpoint = "\(baseURL)/cached_odds?sport_key=eq.kalshi_\(sportKey)&select=data"

        guard let url = URL(string: endpoint) else {
            throw GHError.invalidURL
        }

        var request = URLRequest(url: url)
        request.setValue(apiKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw GHError.invalidResponse
        }

        let rows = try JSONDecoder().decode([CachedKalshiRow].self, from: data)
        return rows.first?.data ?? []
    }

    /// Fetches cached player props from Supabase for a specific event.
    /// Returns the props data and a player-to-team mapping.
    func fetchCachedPlayerProps(eventId: String) async throws -> (props: ResponseBody, playerTeams: [String: String]) {
        let endpoint = "\(baseURL)/cached_player_props?event_id=eq.\(eventId)&select=data,player_teams"

        guard let url = URL(string: endpoint) else {
            throw GHError.invalidURL
        }

        var request = URLRequest(url: url)
        request.setValue(apiKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw GHError.invalidResponse
        }

        let rows = try JSONDecoder().decode([CachedPlayerPropsRow].self, from: data)
        guard let row = rows.first else {
            throw GHError.invalidData
        }
        return (props: row.data, playerTeams: row.playerTeams ?? [:])
    }

    /// Fetches all cached player props for a sport, returns dict keyed by event ID.
    func fetchAllCachedPlayerProps(sportKey: String) async throws -> [String: (props: ResponseBody, playerTeams: [String: String])] {
        let endpoint = "\(baseURL)/cached_player_props?sport_key=eq.\(sportKey)&select=event_id,data,player_teams"

        guard let url = URL(string: endpoint) else {
            throw GHError.invalidURL
        }

        var request = URLRequest(url: url)
        request.setValue(apiKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw GHError.invalidResponse
        }

        let rows = try JSONDecoder().decode([CachedPlayerPropsRowWithId].self, from: data)
        var result: [String: (props: ResponseBody, playerTeams: [String: String])] = [:]
        for row in rows {
            result[row.eventId] = (props: row.data, playerTeams: row.playerTeams ?? [:])
        }
        return result
    }
    // MARK: - NBA Assets (Logos & Headshots)

    /// Fetches all NBA team logo URLs.
    func fetchNBATeamLogos() async throws -> [NBATeamRow] {
        let endpoint = "\(baseURL)/nba_teams?select=team_name,logo_url"

        guard let url = URL(string: endpoint) else {
            throw GHError.invalidURL
        }

        var request = URLRequest(url: url)
        request.setValue(apiKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw GHError.invalidResponse
        }

        return try JSONDecoder().decode([NBATeamRow].self, from: data)
    }

    /// Fetches all NBA player headshot URLs.
    func fetchNBAPlayerHeadshots() async throws -> [NBAPlayerRow] {
        let endpoint = "\(baseURL)/nba_players?select=player_name,headshot_url,team_name"

        guard let url = URL(string: endpoint) else {
            throw GHError.invalidURL
        }

        var request = URLRequest(url: url)
        request.setValue(apiKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw GHError.invalidResponse
        }

        return try JSONDecoder().decode([NBAPlayerRow].self, from: data)
    }

    // MARK: - MLB Assets (Logos & Headshots)

    /// Fetches all MLB team logo URLs.
    func fetchMLBTeamLogos() async throws -> [MLBTeamRow] {
        let endpoint = "\(baseURL)/mlb_teams?select=team_name,logo_url"

        guard let url = URL(string: endpoint) else {
            throw GHError.invalidURL
        }

        var request = URLRequest(url: url)
        request.setValue(apiKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw GHError.invalidResponse
        }

        return try JSONDecoder().decode([MLBTeamRow].self, from: data)
    }

    /// Fetches all MLB player headshot URLs.
    func fetchMLBPlayerHeadshots() async throws -> [MLBPlayerRow] {
        let endpoint = "\(baseURL)/mlb_players?select=player_name,headshot_url,team_name"

        guard let url = URL(string: endpoint) else {
            throw GHError.invalidURL
        }

        var request = URLRequest(url: url)
        request.setValue(apiKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw GHError.invalidResponse
        }

        return try JSONDecoder().decode([MLBPlayerRow].self, from: data)
    }

    // MARK: - NHL Assets (Logos & Headshots)

    /// Fetches all NHL team logo URLs.
    func fetchNHLTeamLogos() async throws -> [NHLTeamRow] {
        let endpoint = "\(baseURL)/nhl_teams?select=team_name,logo_url"

        guard let url = URL(string: endpoint) else {
            throw GHError.invalidURL
        }

        var request = URLRequest(url: url)
        request.setValue(apiKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw GHError.invalidResponse
        }

        return try JSONDecoder().decode([NHLTeamRow].self, from: data)
    }

    /// Fetches all NHL player headshot URLs.
    func fetchNHLPlayerHeadshots() async throws -> [NHLPlayerRow] {
        let endpoint = "\(baseURL)/nhl_players?select=player_name,headshot_url,team_name"

        guard let url = URL(string: endpoint) else {
            throw GHError.invalidURL
        }

        var request = URLRequest(url: url)
        request.setValue(apiKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw GHError.invalidResponse
        }

        return try JSONDecoder().decode([NHLPlayerRow].self, from: data)
    }

    // MARK: - Soccer Assets (Logos & Headshots)

    /// Fetches all soccer team logo URLs.
    func fetchSoccerTeamLogos() async throws -> [SoccerTeamRow] {
        return try await fetchRows(path: "soccer_teams?select=team_name,logo_url")
    }

    /// Fetches all soccer player headshot URLs.
    func fetchSoccerPlayerHeadshots() async throws -> [SoccerPlayerRow] {
        return try await fetchRows(path: "soccer_players?select=player_name,headshot_url,team_name")
    }

    // MARK: - Fighting Assets

    /// Fetches all fighter headshot URLs (null entries are negative cache markers).
    func fetchFighterHeadshots() async throws -> [FighterHeadshotRow] {
        return try await fetchRows(path: "fighter_headshots?select=fighter_name,headshot_url")
    }

    // MARK: - Golf Assets

    /// Fetches all golfer headshot URLs.
    func fetchGolferHeadshots() async throws -> [GolferHeadshotRow] {
        return try await fetchRows(path: "golfer_headshots?select=golfer_name,headshot_url")
    }

    // MARK: - NFL Assets

    /// Fetches all NFL team logo URLs.
    func fetchNFLTeamLogos() async throws -> [NFLTeamRow] {
        return try await fetchRows(path: "nfl_teams?select=team_name,logo_url")
    }

    /// Fetches NFL player headshots from the unified `nfl_players` table
    /// (QBs, RBs, WRs, TEs all in one table). Position is stored as a
    /// column server-side but isn't needed for client-side headshot
    /// lookups — players are keyed by name.
    func fetchNFLPlayers() async throws -> [NFLPlayerRow] {
        return try await fetchRows(path: "nfl_players?select=player_name,headshot_url,team_name")
    }

    // MARK: - Team & Player Stats

    /// Fetches team stats (W-L, home/road, L10) for a specific sport.
    /// Uses the shared SupabaseClient so the user's session JWT is included,
    /// allowing the RLS policy to verify Hall of Fame tier server-side.
    func fetchTeamStats(sportKey: String) async throws -> [TeamStatsRow] {
        try await SupabaseManager.shared
            .from("team_stats")
            .select("team_name, stats")
            .eq("sport_key", value: sportKey)
            .execute()
            .value
    }

    /// Fetches player season averages for a specific sport.
    /// Uses the shared SupabaseClient so the user's session JWT is included,
    /// allowing the RLS policy to verify Hall of Fame tier server-side.
    func fetchPlayerStats(sportKey: String) async throws -> [PlayerStatsRow] {
        try await SupabaseManager.shared
            .from("player_stats")
            .select("player_name, team_name, stats")
            .eq("sport_key", value: sportKey)
            .execute()
            .value
    }

    private func fetchRows<T: Decodable>(path: String) async throws -> [T] {
        guard let url = URL(string: "\(baseURL)/\(path)") else {
            throw GHError.invalidURL
        }
        var request = URLRequest(url: url)
        request.setValue(apiKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw GHError.invalidResponse
        }
        return try JSONDecoder().decode([T].self, from: data)
    }

    // MARK: - Hit Rates (Recent Trends)

    /// Fetches the player's last 15 graded games for `propType` (only rows
    /// where the post-game job has filled in `actual_value`). The caller
    /// can slice locally to compute L5 / L10 / L15 hit rates without
    /// re-querying.
    ///
    /// `playerName` must be the canonical ESPN spelling (the same name
    /// shown in the BetPage UI). Snapshot rows are written under that
    /// name so a direct equality match works.
    func fetchHitRateRows(
        playerName: String,
        sportKey: String,
        propType: String
    ) async throws -> [HitRateRow] {
        // PostgREST: filter graded rows (hit not null), order by date desc, cap at 15.
        let nameEncoded = playerName.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? playerName
        let endpoint = "\(baseURL)/player_game_results"
            + "?player_name=eq.\(nameEncoded)"
            + "&sport_key=eq.\(sportKey)"
            + "&prop_type=eq.\(propType)"
            + "&hit=not.is.null"
            + "&order=game_date.desc"
            + "&limit=15"
            + "&select=hit,game_date,line_value,actual_value"

        guard let url = URL(string: endpoint) else { throw GHError.invalidURL }
        var request = URLRequest(url: url)
        request.setValue(apiKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw GHError.invalidResponse
        }
        return try JSONDecoder().decode([HitRateRow].self, from: data)
    }

    /// Fetches the team's last 15 graded games (only rows where the post-game
    /// job has filled in `covered` / `actual_margin`). The caller can slice
    /// locally to compute Wins L5/L10/L15 and Spreads L5/L10/L15 from the
    /// same array — no need for a second round-trip.
    ///
    /// `teamName` must match the canonical name written by the snapshot
    /// function (which sources it from `nba_teams.team_name`). For NBA this
    /// is the same string shown in BetPage / TeamStatsModal headers.
    func fetchTeamHitRateRows(
        teamName: String,
        sportKey: String
    ) async throws -> [TeamHitRateRow] {
        let nameEncoded = teamName.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? teamName
        let endpoint = "\(baseURL)/team_game_results"
            + "?team_name=eq.\(nameEncoded)"
            + "&sport_key=eq.\(sportKey)"
            + "&covered=not.is.null"
            + "&order=game_date.desc"
            + "&limit=15"
            + "&select=covered,game_date,spread_line,actual_margin"

        guard let url = URL(string: endpoint) else { throw GHError.invalidURL }
        var request = URLRequest(url: url)
        request.setValue(apiKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw GHError.invalidResponse
        }
        return try JSONDecoder().decode([TeamHitRateRow].self, from: data)
    }

    /// Fetches the top-3 hot streaks per in-season sport, populated daily
    /// by the `compute-hot-streaks` edge function at ~13:30 UTC. Returns
    /// at most 12 rows (3 × 4 sports) when all four are in season; fewer
    /// if a sport has no graded games yet (off-season).
    ///
    /// Ordering: by `sport_key` then `rank` so the caller can group by
    /// sport without sorting locally.
    func fetchHotStreaks() async throws -> [Streak] {
        try await fetchStreaks(from: "hot_streaks")
    }

    /// Fetches the top-3 cold streaks per in-season sport — populated by
    /// the same edge function as `fetchHotStreaks`. Identical shape and
    /// ordering; just reads from the parallel `cold_streaks` table.
    func fetchColdStreaks() async throws -> [Streak] {
        try await fetchStreaks(from: "cold_streaks")
    }

    /// Shared transport for the streak tables. Both have identical
    /// schemas and ordering semantics, so we route through one helper.
    private func fetchStreaks(from table: String) async throws -> [Streak] {
        let endpoint = "\(baseURL)/\(table)"
            + "?select=*"
            + "&order=sport_key.asc,rank.asc"

        guard let url = URL(string: endpoint) else { throw GHError.invalidURL }
        var request = URLRequest(url: url)
        request.setValue(apiKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw GHError.invalidResponse
        }
        return try JSONDecoder().decode([Streak].self, from: data)
    }
}

/// One graded row from `player_game_results`. The fields beyond `hit` are
/// kept around for future UI (e.g. a tap-through "show last 5 games" sheet).
struct HitRateRow: Codable {
    let hit: Bool
    let gameDate: String
    let lineValue: Double
    let actualValue: Double

    enum CodingKeys: String, CodingKey {
        case hit
        case gameDate = "game_date"
        case lineValue = "line_value"
        case actualValue = "actual_value"
    }
}

/// One graded row from `team_game_results`. Drives both the Wins History and
/// Spreads History sections in `TeamStatsModal` — wins are derived locally
/// from `actualMargin > 0` so we don't need a second column or query.
struct TeamHitRateRow: Codable {
    let covered: Bool          // grader: (actual_margin + spread_line) > 0
    let gameDate: String
    let spreadLine: Double
    let actualMargin: Double   // team_score - opp_score; >0 means win

    /// Derived locally — the post-game grader stores `actual_margin` and
    /// `covered`, but the win is just the sign of the margin, so we don't
    /// burn a column for it.
    var won: Bool { actualMargin > 0 }

    enum CodingKeys: String, CodingKey {
        case covered
        case gameDate = "game_date"
        case spreadLine = "spread_line"
        case actualMargin = "actual_margin"
    }
}

struct NBATeamRow: Codable {
    let teamName: String
    let logoUrl: String

    enum CodingKeys: String, CodingKey {
        case teamName = "team_name"
        case logoUrl = "logo_url"
    }
}

struct NBAPlayerRow: Codable {
    let playerName: String
    let headshotUrl: String
    let teamName: String

    enum CodingKeys: String, CodingKey {
        case playerName = "player_name"
        case headshotUrl = "headshot_url"
        case teamName = "team_name"
    }
}

struct MLBTeamRow: Codable {
    let teamName: String
    let logoUrl: String

    enum CodingKeys: String, CodingKey {
        case teamName = "team_name"
        case logoUrl = "logo_url"
    }
}

struct MLBPlayerRow: Codable {
    let playerName: String
    let headshotUrl: String
    let teamName: String

    enum CodingKeys: String, CodingKey {
        case playerName = "player_name"
        case headshotUrl = "headshot_url"
        case teamName = "team_name"
    }
}

struct NHLTeamRow: Codable {
    let teamName: String
    let logoUrl: String

    enum CodingKeys: String, CodingKey {
        case teamName = "team_name"
        case logoUrl = "logo_url"
    }
}

struct NHLPlayerRow: Codable {
    let playerName: String
    let headshotUrl: String
    let teamName: String

    enum CodingKeys: String, CodingKey {
        case playerName = "player_name"
        case headshotUrl = "headshot_url"
        case teamName = "team_name"
    }
}

struct SoccerTeamRow: Codable {
    let teamName: String
    let logoUrl: String

    enum CodingKeys: String, CodingKey {
        case teamName = "team_name"
        case logoUrl = "logo_url"
    }
}

struct SoccerPlayerRow: Codable {
    let playerName: String
    let headshotUrl: String
    let teamName: String

    enum CodingKeys: String, CodingKey {
        case playerName = "player_name"
        case headshotUrl = "headshot_url"
        case teamName = "team_name"
    }
}

struct FighterHeadshotRow: Codable {
    let fighterName: String
    let headshotUrl: String?

    enum CodingKeys: String, CodingKey {
        case fighterName = "fighter_name"
        case headshotUrl = "headshot_url"
    }
}

struct GolferHeadshotRow: Codable {
    let golferName: String
    let headshotUrl: String?

    enum CodingKeys: String, CodingKey {
        case golferName = "golfer_name"
        case headshotUrl = "headshot_url"
    }
}

struct NFLTeamRow: Codable {
    let teamName: String
    let logoUrl: String

    enum CodingKeys: String, CodingKey {
        case teamName = "team_name"
        case logoUrl = "logo_url"
    }
}

struct NFLPlayerRow: Codable {
    let playerName: String
    let headshotUrl: String
    let teamName: String

    enum CodingKeys: String, CodingKey {
        case playerName = "player_name"
        case headshotUrl = "headshot_url"
        case teamName = "team_name"
    }
}

/// Represents a single row from the cached_odds table (only the `data` column is selected).
private struct CachedOddsRow: Codable {
    let data: [ResponseBody]
}

/// One transformed Kalshi market cached as a pseudo-event. Matched against
/// the Odds API events by (away_team, home_team) + commence_date proximity,
/// then its `bookmaker` is appended to the matched event's bookmakers array.
struct KalshiEvent: Codable {
    let id: String
    let commenceDate: String
    let awayTeam: String
    let homeTeam: String
    let bookmaker: Bookmaker

    enum CodingKeys: String, CodingKey {
        case id, bookmaker
        case commenceDate = "commence_date"
        case awayTeam = "away_team"
        case homeTeam = "home_team"
    }
}

/// One row from cached_odds whose `data` column holds the Kalshi events array.
private struct CachedKalshiRow: Codable {
    let data: [KalshiEvent]
}

struct TeamStatsRow: Codable {
    let teamName: String
    let stats: [String: String]

    enum CodingKeys: String, CodingKey {
        case teamName = "team_name"
        case stats
    }
}

struct PlayerStatsRow: Codable {
    let playerName: String
    let teamName: String
    let stats: [String: String]

    enum CodingKeys: String, CodingKey {
        case playerName = "player_name"
        case teamName = "team_name"
        case stats
    }
}

/// Represents a single row from cached_player_props (data + player_teams).
private struct CachedPlayerPropsRow: Codable {
    let data: ResponseBody
    let playerTeams: [String: String]?

    enum CodingKeys: String, CodingKey {
        case data
        case playerTeams = "player_teams"
    }
}

/// Represents a row from cached_player_props with event_id, data, and player_teams.
private struct CachedPlayerPropsRowWithId: Codable {
    let eventId: String
    let data: ResponseBody
    let playerTeams: [String: String]?

    enum CodingKeys: String, CodingKey {
        case eventId = "event_id"
        case data
        case playerTeams = "player_teams"
    }
}
