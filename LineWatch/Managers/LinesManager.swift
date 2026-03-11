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

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .basketball: return "Basketball"
        case .football: return "Football"
        case .baseball: return "Baseball"
        }
    }

    var iconName: String {
        switch self {
        case .basketball: return "basketball.fill"
        case .football: return "football.fill"
        case .baseball: return "baseball.fill"
        }
    }

    var localFileName: String {
        switch self {
        case .basketball: return "basketball_nba"
        case .football: return "americanfootball_nfl"
        case .baseball: return "baseball_mlb"
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
        let marketsParam = MarketType.apiMarketsParam(markets)
        let endpoint = "\(baseURL)/\(sport.rawValue)/odds/?apiKey=\(apiKey)&regions=us&markets=\(marketsParam)&oddsFormat=american"

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
    let homeTeam, awayTeam: String
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

