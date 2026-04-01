//
//  OddsDataService.swift
//  LineWatch
//
//  Created by Steven Nguyen on 3/9/26.
//

import Foundation

@Observable
class OddsDataService {
    var eventsBySport: [SportCategory: [ResponseBody]] = [:]
    var playerPropsByEvent: [String: ResponseBody] = [:]
    var isLoading = false
    var error: Error?

    private let linesManager = LinesManager()
    private let supabaseService = SupabaseService()

    // Load from bundled JSON files (no API calls)
    func loadLocalData() {
        for sport in SportCategory.allCases {
            var allEvents: [ResponseBody] = []
            for fileName in sport.localFileNames {
                let events: [ResponseBody] = loadFromBundle(fileName)
                allEvents.append(contentsOf: events)
            }
            eventsBySport[sport] = allEvents
        }
    }

    // Fetch from API for a single sport and cache locally
    func fetchAndCache(sport: SportCategory) async {
        isLoading = true
        defer { isLoading = false }

        // Basketball: fetch from Supabase cache instead of the-odds-api directly
        if sport == .basketball {
            do {
                let events = try await supabaseService.fetchCachedOdds(sportKey: "basketball_nba")
                eventsBySport[sport] = events
                saveToDocuments(events, filename: "basketball_nba.json")
            } catch {
                self.error = error
                let local: [ResponseBody] = loadFromBundle("basketball_nba")
                eventsBySport[sport] = local
            }
            return
        }

        // All other sports: fetch from the-odds-api directly
        var allEvents: [ResponseBody] = []
        for (index, key) in sport.sportKeys.enumerated() {
            do {
                let events = try await linesManager.getOdds(forKey: key, markets: sport.availableMarkets)
                allEvents.append(contentsOf: events)
                saveToDocuments(events, filename: "\(sport.localFileNames[index]).json")
            } catch {
                self.error = error
                let local: [ResponseBody] = loadFromBundle(sport.localFileNames[index])
                allEvents.append(contentsOf: local)
            }
        }
        eventsBySport[sport] = allEvents
    }

    // Fetch all sports from API
    func fetchAndCacheAll() async {
        isLoading = true
        defer { isLoading = false }

        for sport in SportCategory.allCases {
            // Basketball: fetch from Supabase cache
            if sport == .basketball {
                do {
                    let events = try await supabaseService.fetchCachedOdds(sportKey: "basketball_nba")
                    eventsBySport[sport] = events
                    saveToDocuments(events, filename: "basketball_nba.json")
                } catch {
                    self.error = error
                    let local: [ResponseBody] = loadFromBundle("basketball_nba")
                    eventsBySport[sport] = local
                }
                continue
            }

            // All other sports: fetch from the-odds-api directly
            var allEvents: [ResponseBody] = []
            for (index, key) in sport.sportKeys.enumerated() {
                do {
                    let events = try await linesManager.getOdds(forKey: key, markets: sport.availableMarkets)
                    allEvents.append(contentsOf: events)
                    saveToDocuments(events, filename: "\(sport.localFileNames[index]).json")
                } catch {
                    self.error = error
                    let local: [ResponseBody] = loadFromBundle(sport.localFileNames[index])
                    allEvents.append(contentsOf: local)
                }
            }
            eventsBySport[sport] = allEvents
        }
    }

    func events(for sport: SportCategory) -> [ResponseBody] {
        eventsBySport[sport] ?? []
    }

    // MARK: - Player Props

    /// Fetch player props for a specific event (lazy-loaded on BetPage)
    func fetchPlayerProps(eventId: String) async {
        // Skip if already cached
        if playerPropsByEvent[eventId] != nil { return }

        do {
            let props = try await supabaseService.fetchCachedPlayerProps(eventId: eventId)
            await MainActor.run {
                playerPropsByEvent[eventId] = props
            }
        } catch {
            // Fallback: try loading from bundled sample data
            let sample: ResponseBody? = loadPlayerPropsFromBundle("player_props_sample.json")
            if let sample {
                await MainActor.run {
                    playerPropsByEvent[eventId] = sample
                }
            }
        }
    }

    /// Load player props sample from bundle
    private func loadPlayerPropsFromBundle(_ filename: String) -> ResponseBody? {
        guard let url = Bundle.main.url(forResource: filename, withExtension: nil) else { return nil }
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(ResponseBody.self, from: data)
    }

    // MARK: - Private Helpers

    private func saveToDocuments(_ events: [ResponseBody], filename: String) {
        guard let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?.appendingPathComponent(filename) else { return }
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        if let data = try? encoder.encode(events) {
            try? data.write(to: url)
        }
    }

    private func loadFromBundle(_ filename: String) -> [ResponseBody] {
        guard let url = Bundle.main.url(forResource: filename, withExtension: "json") else {
            return []
        }
        guard let data = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder().decode([ResponseBody].self, from: data)) ?? []
    }
}
