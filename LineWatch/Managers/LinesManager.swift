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
        case .basketball, .football, .baseball, .hockey, .soccer:
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

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .h2h: return "Moneyline"
        case .spreads: return "Spreads"
        case .totals: return "Totals"
        case .outrights: return "Outrights"
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

// MARK: - API Manager

class LinesManager {
    private let apiKey = "38362e374889c29da9e8c1692d5c133d"
    private let baseURL = "https://api.the-odds-api.com/v4/sports"

    func getOdds(for sport: SportCategory, markets: [MarketType] = MarketType.standardMarkets) async throws -> [ResponseBody] {
        // For single-key sports, use the rawValue. For multi-key, caller should use getOdds(forKey:) instead.
        return try await getOdds(forKey: sport.sportKeys[0], markets: markets)
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
}

enum GHError: Error {
    case invalidURL
    case invalidResponse
    case invalidData
}

