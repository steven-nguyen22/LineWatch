//
//  LinesManager.swift
//  LineWatch
//
//  Created by Steven Nguyen on 11/14/24.
//

import Foundation
import CoreLocation

class LinesManager {
    func getCurrentLines() async throws -> [ResponseBody] {
        let endpoint = "https://api.the-odds-api.com/v4/sports/basketball_nba/odds/?apiKey=38362e374889c29da9e8c1692d5c133d&regions=us&markets=h2h&oddsFormat=american"
        
        guard let url = URL(string: endpoint) else {
            throw GHError.invalidURL
        }
        
        let (data, response) = try await URLSession.shared.data(from: url)
        
        
        guard let response = response as? HTTPURLResponse, response.statusCode == 200 else {
            throw GHError.invalidResponse
        }
        
        do {
            let decoder = JSONDecoder()
//            decoder.keyDecodingStrategy = .convertFromSnakeCase
//            return try decoder.decode(LinesTest.self, from: data)
            let temp: [ResponseBody] = try decoder.decode([ResponseBody].self, from: data)
//            let temp = try decoder.decode(LinesTest.self, from: data)
//            print(temp[0])
            return temp
//            let output = temp.lines[0]
//            return output
        } catch {
            throw GHError.invalidData
        }
    }
}
    


struct ResponseBody: Codable {
    let id: String
    let sportKey: String
    let sportTitle: String
    let homeTeam, awayTeam: String
    let bookmakers: [Bookmaker]
    
    enum CodingKeys: String, CodingKey {
            case id
            case sportKey = "sport_key"
            case sportTitle = "sport_title"
            case homeTeam = "home_team"
            case awayTeam = "away_team"
            case bookmakers
        }
}

struct Bookmaker: Codable {
    let key, title: String
    let markets: [Market]

    enum CodingKeys: String, CodingKey {
        case key, title
        case markets
    }
}

struct Market: Codable {
    let key: String
    let outcomes: [Outcome]

    enum CodingKeys: String, CodingKey {
        case key
        case outcomes
    }
}

struct Outcome: Codable {
    let name: String
    let price: Int
}

enum GHError: Error {
    case invalidURL
    case invalidResponse
    case invalidData
}

