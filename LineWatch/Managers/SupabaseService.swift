//
//  SupabaseService.swift
//  LineWatch
//
//  Created by Steven Nguyen on 3/27/26.
//

import Foundation

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

    // MARK: - Fighting Assets

    /// Fetches all fighter headshot URLs (null entries are negative cache markers).
    func fetchFighterHeadshots() async throws -> [FighterHeadshotRow] {
        return try await fetchRows(path: "fighter_headshots?select=fighter_name,headshot_url")
    }

    // MARK: - NFL Assets

    /// Fetches all NFL team logo URLs.
    func fetchNFLTeamLogos() async throws -> [NFLTeamRow] {
        return try await fetchRows(path: "nfl_teams?select=team_name,logo_url")
    }

    /// Fetches QB headshots.
    func fetchNFLQBs() async throws -> [NFLPlayerRow] {
        return try await fetchRows(path: "nfl_qbs?select=player_name,headshot_url,team_name")
    }

    /// Fetches RB headshots.
    func fetchNFLRBs() async throws -> [NFLPlayerRow] {
        return try await fetchRows(path: "nfl_rbs?select=player_name,headshot_url,team_name")
    }

    /// Fetches WR/TE headshots.
    func fetchNFLReceivers() async throws -> [NFLPlayerRow] {
        return try await fetchRows(path: "nfl_receivers?select=player_name,headshot_url,team_name")
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

struct FighterHeadshotRow: Codable {
    let fighterName: String
    let headshotUrl: String?

    enum CodingKeys: String, CodingKey {
        case fighterName = "fighter_name"
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
