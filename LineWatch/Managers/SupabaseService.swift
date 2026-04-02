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
