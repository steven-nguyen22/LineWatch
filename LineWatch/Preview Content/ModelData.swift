//
//  ModelData.swift
//  LineWatch
//
//  Created by Steven Nguyen on 11/14/24.
//

import Foundation

var previewBasketball: [ResponseBody] = load("basketball_nba.json")
var previewFootball: [ResponseBody] = load("americanfootball_nfl.json")
var previewBaseball: [ResponseBody] = load("baseball_mlb.json")
var previewHockey: [ResponseBody] = load("icehockey_nhl.json")
var previewSoccer: [ResponseBody] = load("soccer_uefa_champs_league.json")
var previewFighting: [ResponseBody] = loadOptional("mma_mixed_martial_arts.json") + loadOptional("boxing_boxing.json")
var previewGolf: [ResponseBody] = loadOptional("golf_masters_tournament_winner.json")
    + loadOptional("golf_pga_championship_winner.json")
    + loadOptional("golf_the_open_championship_winner.json")
    + loadOptional("golf_us_open_winner.json")

// Backward compatibility
var previewLines: [ResponseBody] = load("basketball_nba.json")

var previewPlayerProps: ResponseBody? = loadOptionalSingle("player_props_sample.json")

var previewDataService: OddsDataService = {
    let service = OddsDataService()
    service.eventsBySport[.basketball] = previewBasketball
    service.eventsBySport[.football] = previewFootball
    service.eventsBySport[.baseball] = previewBaseball
    service.eventsBySport[.hockey] = previewHockey
    service.eventsBySport[.soccer] = previewSoccer
    service.eventsBySport[.fighting] = previewFighting
    service.eventsBySport[.golf] = previewGolf

    // Populate player props for all basketball events (uses sample data for preview)
    let sampleTeamMap: [String: String] = [
        "Jaylen Brown": "Boston Celtics",
        "Jayson Tatum": "Boston Celtics",
        "Derrick White": "Boston Celtics",
        "Payton Pritchard": "Boston Celtics",
        "Sam Hauser": "Boston Celtics",
        "Neemias Queta": "Boston Celtics",
        "Baylor Scheierman": "Boston Celtics",
        "Bam Adebayo": "Miami Heat",
        "Tyler Herro": "Miami Heat",
        "Jaime Jaquez Jr": "Miami Heat",
        "Pelle Larsson": "Miami Heat",
        "Davion Mitchell": "Miami Heat",
        "Andrew Wiggins": "Miami Heat",
    ]

    if let props = previewPlayerProps {
        for event in previewBasketball {
            service.playerPropsByEvent[event.id] = props
            service.playerTeamsByEvent[event.id] = sampleTeamMap
        }
    }

    return service
}()

func load<T: Decodable>(_ filename: String) -> T {
    let data: Data

    guard let file = Bundle.main.url(forResource: filename, withExtension: nil)
        else {
            fatalError("Couldn't find \(filename) in main bundle.")
    }

    do {
        data = try Data(contentsOf: file)
    } catch {
        fatalError("Couldn't load \(filename) from main bundle:\n\(error)")
    }

    do {
        let decoder = JSONDecoder()
        return try decoder.decode(T.self, from: data)
    } catch {
        fatalError("Couldn't parse \(filename) as \(T.self):\n\(error)")
    }
}

/// Safe loader that returns an empty array if the file is missing
func loadOptional(_ filename: String) -> [ResponseBody] {
    guard let file = Bundle.main.url(forResource: filename, withExtension: nil) else {
        return []
    }
    guard let data = try? Data(contentsOf: file) else { return [] }
    return (try? JSONDecoder().decode([ResponseBody].self, from: data)) ?? []
}

/// Safe loader for a single object (e.g., player props per event)
func loadOptionalSingle(_ filename: String) -> ResponseBody? {
    guard let file = Bundle.main.url(forResource: filename, withExtension: nil) else {
        return nil
    }
    guard let data = try? Data(contentsOf: file) else { return nil }
    return try? JSONDecoder().decode(ResponseBody.self, from: data)
}
