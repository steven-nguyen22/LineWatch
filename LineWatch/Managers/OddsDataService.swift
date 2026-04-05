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
    var playerTeamsByEvent: [String: [String: String]] = [:]
    var teamLogoURLs: [String: String] = [:]
    var playerHeadshotURLs: [String: String] = [:]
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

        // Basketball & Baseball: fetch from Supabase cache
        if sport == .basketball || sport == .baseball || sport == .hockey || sport == .football {
            do {
                let events = try await supabaseService.fetchCachedOdds(sportKey: sport.rawValue)
                eventsBySport[sport] = events
                saveToDocuments(events, filename: "\(sport.rawValue).json")
            } catch {
                self.error = error
                let local: [ResponseBody] = loadFromBundle(sport.rawValue)
                eventsBySport[sport] = local
            }
            return
        }

        // Fighting: fetch both leagues from Supabase cache
        if sport == .fighting {
            var allEvents: [ResponseBody] = []
            for key in sport.sportKeys {
                do {
                    let events = try await supabaseService.fetchCachedOdds(sportKey: key)
                    allEvents.append(contentsOf: events)
                    saveToDocuments(events, filename: "\(key).json")
                } catch {
                    self.error = error
                    let local: [ResponseBody] = loadFromBundle(key)
                    allEvents.append(contentsOf: local)
                }
            }
            eventsBySport[sport] = allEvents
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
            // Basketball & Baseball: fetch from Supabase cache
            if sport == .basketball || sport == .baseball || sport == .hockey || sport == .football {
                do {
                    let events = try await supabaseService.fetchCachedOdds(sportKey: sport.rawValue)
                    eventsBySport[sport] = events
                    saveToDocuments(events, filename: "\(sport.rawValue).json")
                } catch {
                    self.error = error
                    let local: [ResponseBody] = loadFromBundle(sport.rawValue)
                    eventsBySport[sport] = local
                }
                continue
            }

            // Fighting: fetch both leagues from Supabase cache
            if sport == .fighting {
                var allFightingEvents: [ResponseBody] = []
                for key in sport.sportKeys {
                    do {
                        let events = try await supabaseService.fetchCachedOdds(sportKey: key)
                        allFightingEvents.append(contentsOf: events)
                        saveToDocuments(events, filename: "\(key).json")
                    } catch {
                        self.error = error
                        let local: [ResponseBody] = loadFromBundle(key)
                        allFightingEvents.append(contentsOf: local)
                    }
                }
                eventsBySport[sport] = allFightingEvents
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

    // MARK: - NBA Assets (Logos & Headshots)

    /// Fetch team logos and player headshots from Supabase (run once on launch)
    func fetchNBAAssets() async {
        do {
            async let teamsTask = supabaseService.fetchNBATeamLogos()
            async let playersTask = supabaseService.fetchNBAPlayerHeadshots()

            let (teams, players) = try await (teamsTask, playersTask)

            await MainActor.run {
                for team in teams {
                    teamLogoURLs[team.teamName] = team.logoUrl
                }
                for player in players {
                    playerHeadshotURLs[player.playerName] = player.headshotUrl
                }
            }
        } catch {
            // Silent failure — UI will show placeholder icons
        }
    }

    // MARK: - MLB Assets (Logos & Headshots)

    /// Fetch team logos and player headshots from Supabase for MLB (run once on launch)
    func fetchMLBAssets() async {
        do {
            async let teamsTask = supabaseService.fetchMLBTeamLogos()
            async let playersTask = supabaseService.fetchMLBPlayerHeadshots()

            let (teams, players) = try await (teamsTask, playersTask)

            await MainActor.run {
                for team in teams {
                    teamLogoURLs[team.teamName] = team.logoUrl
                }
                for player in players {
                    playerHeadshotURLs[player.playerName] = player.headshotUrl
                }
            }
        } catch {
            // Silent failure — UI will show placeholder icons
        }
    }

    // MARK: - NHL Assets (Logos & Headshots)

    /// Fetch team logos and player headshots from Supabase for NHL (run once on launch)
    func fetchNHLAssets() async {
        do {
            async let teamsTask = supabaseService.fetchNHLTeamLogos()
            async let playersTask = supabaseService.fetchNHLPlayerHeadshots()

            let (teams, players) = try await (teamsTask, playersTask)

            await MainActor.run {
                for team in teams {
                    teamLogoURLs[team.teamName] = team.logoUrl
                }
                for player in players {
                    playerHeadshotURLs[player.playerName] = player.headshotUrl
                }
            }
        } catch {
            // Silent failure — UI will show placeholder icons
        }
    }

    // MARK: - NFL Assets (Logos & Headshots)

    /// Fetch team logos and player headshots from Supabase for NFL (run once on launch)
    func fetchNFLAssets() async {
        do {
            async let teamsTask = supabaseService.fetchNFLTeamLogos()
            async let qbsTask = supabaseService.fetchNFLQBs()
            async let rbsTask = supabaseService.fetchNFLRBs()
            async let receiversTask = supabaseService.fetchNFLReceivers()

            let (teams, qbs, rbs, receivers) = try await (teamsTask, qbsTask, rbsTask, receiversTask)

            await MainActor.run {
                for team in teams {
                    teamLogoURLs[team.teamName] = team.logoUrl
                }
                for player in qbs + rbs + receivers {
                    playerHeadshotURLs[player.playerName] = player.headshotUrl
                }
            }
        } catch {
            // Silent failure — UI will show placeholder icons
        }
    }

    // MARK: - Player Props

    /// Fetch player props for a specific event (lazy-loaded on BetPage)
    func fetchPlayerProps(eventId: String) async {
        // Skip if already cached
        if playerPropsByEvent[eventId] != nil { return }

        do {
            let result = try await supabaseService.fetchCachedPlayerProps(eventId: eventId)
            await MainActor.run {
                playerPropsByEvent[eventId] = result.props
                playerTeamsByEvent[eventId] = result.playerTeams
            }
        } catch {
            // Fallback: try loading from bundled sample data
            let sample: ResponseBody? = loadPlayerPropsFromBundle("player_props_sample.json")
            if let sample {
                await MainActor.run {
                    playerPropsByEvent[eventId] = sample
                    // Hardcoded fallback mapping for sample data
                    playerTeamsByEvent[eventId] = [
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
