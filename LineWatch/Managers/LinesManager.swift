//
//  LinesManager.swift
//  LineWatch
//
//  Created by Steven Nguyen on 11/14/24.
//

import Foundation

// MARK: - Sport Categories

enum SportCategory: String, CaseIterable, Identifiable, Hashable {
    case basketball = "basketball_nba"
    case football = "americanfootball_nfl"
    case baseball = "baseball_mlb"
    case hockey = "icehockey_nhl"
    case soccer = "soccer_uefa_champs_league"
    case fighting = "fighting"
    case golf = "golf"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .basketball: return "Basketball"
        case .football: return "Football"
        case .baseball: return "Baseball"
        case .hockey: return "Hockey"
        case .soccer: return "Soccer"
        case .fighting: return "MMA / Boxing"
        case .golf: return "Golf"
        }
    }

    var iconName: String {
        switch self {
        case .basketball: return "basketball.fill"
        case .football: return "football.fill"
        case .baseball: return "baseball.fill"
        case .hockey: return "hockey.puck"
        case .soccer: return "soccerball"
        case .fighting: return "figure.boxing"
        case .golf: return "figure.golf"
        }
    }

    /// API sport keys for this category (combined categories return multiple keys)
    var sportKeys: [String] {
        switch self {
        case .basketball: return ["basketball_nba"]
        case .football: return ["americanfootball_nfl"]
        case .baseball: return ["baseball_mlb"]
        case .hockey: return ["icehockey_nhl"]
        case .soccer: return ["soccer_uefa_champs_league"]
        case .fighting: return ["mma_mixed_martial_arts", "boxing_boxing"]
        case .golf: return ["golf_masters_tournament_winner", "golf_pga_championship_winner", "golf_the_open_championship_winner", "golf_us_open_winner"]
        }
    }

    /// Local JSON filenames (one per sport key, without extension)
    var localFileNames: [String] {
        sportKeys
    }

    /// Season date range as (startMonth, startDay, endMonth, endDay).
    /// Returns nil for year-round sports (always in season).
    private var seasonRange: (startMonth: Int, startDay: Int, endMonth: Int, endDay: Int)? {
        switch self {
        case .basketball: return (10, 1, 6, 30)   // Oct 1 – Jun 30 (includes NBA playoffs/finals)
        case .football:   return (9, 1, 2, 15)    // Sep 1 – Feb 15 (includes NFL playoffs/Super Bowl)
        case .baseball:   return (3, 20, 11, 5)   // Mar 20 – Nov 5 (includes MLB postseason/World Series)
        case .hockey:     return (10, 1, 6, 30)   // Oct 1 – Jun 30 (includes NHL playoffs/Stanley Cup)
        case .soccer:     return (9, 1, 6, 15)    // Sep 1 – Jun 15 (UEFA CL group stage through final)
        case .fighting:   return nil               // Year-round
        case .golf:       return nil               // Year-round
        }
    }

    /// Whether this sport is currently in season (based on today's date).
    /// Year-round sports always return true.
    var isInSeason: Bool {
        guard let range = seasonRange else { return true }

        let calendar = Calendar.current
        let today = Date()
        let month = calendar.component(.month, from: today)
        let day = calendar.component(.day, from: today)
        let todayValue = month * 100 + day  // e.g., March 31 = 331, October 1 = 1001

        let startValue = range.startMonth * 100 + range.startDay
        let endValue = range.endMonth * 100 + range.endDay

        if startValue <= endValue {
            // Season doesn't wrap around year (e.g., baseball Mar–Nov)
            return todayValue >= startValue && todayValue <= endValue
        } else {
            // Season wraps around year (e.g., football Sep–Feb)
            return todayValue >= startValue || todayValue <= endValue
        }
    }

    /// Convenience: all sports currently in season
    static var inSeason: [SportCategory] {
        allCases.filter { $0.isInSeason }
    }

    /// Convenience: all sports currently off season
    static var offSeason: [SportCategory] {
        allCases.filter { !$0.isInSeason }
    }

    /// Available market types for this sport
    var availableMarkets: [MarketType] {
        switch self {
        case .basketball:
            return [.h2h, .spreads, .totals, .playerProps]
        case .baseball:
            return [.h2h, .spreads, .totals, .playerProps]
        case .hockey:
            return [.h2h, .spreads, .totals, .playerProps]
        case .football:
            return [.h2h, .spreads, .totals, .playerProps]
        case .soccer:
            return [.h2h, .spreads, .totals]
        case .fighting:
            return [.h2h]
        case .golf:
            return [.outrights]
        }
    }
}

// MARK: - Market Types

enum MarketType: String, CaseIterable, Identifiable, Hashable {
    case h2h = "h2h"
    case spreads = "spreads"
    case totals = "totals"
    case outrights = "outrights"
    case playerProps = "player_props"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .h2h: return "Moneyline"
        case .spreads: return "Spreads"
        case .totals: return "Totals"
        case .outrights: return "Outrights"
        case .playerProps: return "Player Props"
        }
    }

    /// Standard markets available for team sports (excludes outrights)
    static var standardMarkets: [MarketType] {
        [.h2h, .spreads, .totals]
    }

    /// Build the API query parameter value
    static func apiMarketsParam(_ types: [MarketType]) -> String {
        types.map(\.rawValue).joined(separator: ",")
    }
}

// MARK: - Player Prop Types

enum PlayerPropType: String, CaseIterable, Identifiable, Hashable {
    // Basketball
    case points = "player_points"
    case rebounds = "player_rebounds"
    case assists = "player_assists"
    // Baseball
    case hits = "batter_hits"
    case strikeouts = "pitcher_strikeouts"
    case homeRuns = "batter_home_runs"
    // Hockey
    case goals = "player_goals"
    case shotsOnGoal = "player_shots_on_goal"
    case hockeyPoints = "hockey_player_points" // unique raw value; API key is "player_points"
    // Football
    case passingYards = "player_pass_yds"
    case rushingYards = "player_rush_yds"
    case receivingYards = "player_reception_yds"

    var id: String { rawValue }

    /// The Odds API market key (differs from rawValue for hockeyPoints)
    var marketKey: String {
        switch self {
        case .hockeyPoints: return "player_points"
        default: return rawValue
        }
    }

    var displayName: String {
        switch self {
        case .points: return "Points"
        case .rebounds: return "Rebounds"
        case .assists: return "Assists"
        case .hits: return "Hits"
        case .strikeouts: return "Strikeouts"
        case .homeRuns: return "Home Runs"
        case .goals: return "Goals"
        case .shotsOnGoal: return "Shots on Goal"
        case .hockeyPoints: return "Points"
        case .passingYards: return "Passing Yards"
        case .rushingYards: return "Rushing Yards"
        case .receivingYards: return "Receiving Yards"
        }
    }

    /// Which sport this prop type belongs to
    var sport: SportCategory {
        switch self {
        case .points, .rebounds, .assists: return .basketball
        case .hits, .strikeouts, .homeRuns: return .baseball
        case .goals, .shotsOnGoal, .hockeyPoints: return .hockey
        case .passingYards, .rushingYards, .receivingYards: return .football
        }
    }

    /// Prop types for a specific sport
    static func cases(for sport: SportCategory) -> [PlayerPropType] {
        allCases.filter { $0.sport == sport }
    }

    /// Combined API markets parameter for all prop types
    static var apiMarketsParam: String {
        allCases.map(\.marketKey).joined(separator: ",")
    }

    /// API markets parameter for a specific sport
    static func apiMarketsParam(for sport: SportCategory) -> String {
        cases(for: sport).map(\.marketKey).joined(separator: ",")
    }
}

// MARK: - Player Prop Line (grouped per player)

struct PlayerPropLine: Identifiable {
    var id: String { playerName }
    let playerName: String
    let line: Double
    let teamName: String?
    let bookmakerOdds: [(bookmakerTitle: String, over: Int?, under: Int?)]
}

// MARK: - API Manager

class LinesManager {
    private let apiKey = "38362e374889c29da9e8c1692d5c133d"
    private let baseURL = "https://api.the-odds-api.com/v4/sports"

    func getOdds(for sport: SportCategory, markets: [MarketType] = MarketType.standardMarkets) async throws -> [ResponseBody] {
        // For single-key sports, use the rawValue. For multi-key, caller should use getOdds(forKey:) instead.
        return try await getOdds(forKey: sport.sportKeys[0], markets: markets)
    }

    /// Fetch player props for a specific event (returns a single ResponseBody, not array)
    func getPlayerProps(eventId: String, sportKey: String = "basketball_nba") async throws -> ResponseBody {
        let marketsParam = PlayerPropType.apiMarketsParam
        let endpoint = "\(baseURL)/\(sportKey)/events/\(eventId)/odds/?apiKey=\(apiKey)&regions=us&markets=\(marketsParam)&oddsFormat=american"

        guard let url = URL(string: endpoint) else {
            throw GHError.invalidURL
        }

        let (data, response) = try await URLSession.shared.data(from: url)

        guard let response = response as? HTTPURLResponse, response.statusCode == 200 else {
            throw GHError.invalidResponse
        }

        do {
            return try JSONDecoder().decode(ResponseBody.self, from: data)
        } catch {
            throw GHError.invalidData
        }
    }

    func getOdds(forKey sportKey: String, markets: [MarketType] = MarketType.standardMarkets) async throws -> [ResponseBody] {
        let marketsParam = MarketType.apiMarketsParam(markets)
        let endpoint = "\(baseURL)/\(sportKey)/odds/?apiKey=\(apiKey)&regions=us&markets=\(marketsParam)&oddsFormat=american"

        guard let url = URL(string: endpoint) else {
            throw GHError.invalidURL
        }

        let (data, response) = try await URLSession.shared.data(from: url)

        guard let response = response as? HTTPURLResponse, response.statusCode == 200 else {
            throw GHError.invalidResponse
        }

        do {
            return try JSONDecoder().decode([ResponseBody].self, from: data)
        } catch {
            throw GHError.invalidData
        }
    }
}

// MARK: - Models

struct ResponseBody: Codable, Identifiable {
    let id: String
    let sportKey: String
    let sportTitle: String
    let commenceTime: String?
    let homeTeam: String?
    let awayTeam: String?
    let bookmakers: [Bookmaker]

    enum CodingKeys: String, CodingKey {
        case id
        case sportKey = "sport_key"
        case sportTitle = "sport_title"
        case commenceTime = "commence_time"
        case homeTeam = "home_team"
        case awayTeam = "away_team"
        case bookmakers
    }

    /// Display name for the home side (falls back to sport title for outrights)
    var homeDisplay: String { homeTeam ?? sportTitle }
    /// Display name for the away side (falls back to empty for outrights)
    var awayDisplay: String { awayTeam ?? "" }
}

extension ResponseBody: Hashable {
    static func == (lhs: ResponseBody, rhs: ResponseBody) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

struct Bookmaker: Codable {
    let key, title: String
    let markets: [Market]
}

struct Market: Codable {
    let key: String
    let lastUpdate: String?
    let outcomes: [Outcome]

    enum CodingKeys: String, CodingKey {
        case key
        case lastUpdate = "last_update"
        case outcomes
    }
}

struct Outcome: Codable {
    let name: String
    let price: Int
    let point: Double?
    let description: String?  // Player name for player props (e.g., "Jayson Tatum")
}

enum GHError: Error {
    case invalidURL
    case invalidResponse
    case invalidData
}

