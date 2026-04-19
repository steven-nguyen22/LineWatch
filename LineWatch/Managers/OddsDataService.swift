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
    var teamStatsByName: [String: [String: String]] = [:]
    var playerStatsByName: [String: [String: String]] = [:]
    @ObservationIgnored private var statsFetchedForSports: Set<String> = []
    var isLoading = false
    var error: Error?

    /// Wall-clock time of the next scheduled background refresh. Updated by the
    /// 5-min refresh loop in ContentView; read by RefreshCountdownButton to
    /// render the countdown popover. `nil` means no refresh is currently scheduled
    /// (e.g. signed out, backgrounded, or pre-initial-load).
    var nextRefreshAt: Date?

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

        // Single-key sports via Supabase cache
        if sport == .basketball || sport == .baseball || sport == .hockey
            || sport == .football || sport == .soccer || sport == .golf {
            do {
                let events = try await supabaseService.fetchCachedOdds(sportKey: sport.rawValue)
                await MainActor.run { eventsBySport[sport] = events }
                saveToDocuments(events, filename: "\(sport.rawValue).json")
            } catch {
                self.error = error
                let local: [ResponseBody] = loadFromBundle(sport.rawValue)
                await MainActor.run { eventsBySport[sport] = local }
            }
            return
        }

        // Multi-key sports via Supabase cache (fighting only)
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
            let finalEvents = allEvents
            await MainActor.run { eventsBySport[sport] = finalEvents }
            return
        }
    }

    // Fetch all sports from API
    func fetchAndCacheAll() async {
        isLoading = true
        defer { isLoading = false }

        for sport in SportCategory.allCases {
            // Single-key sports via Supabase cache
            if sport == .basketball || sport == .baseball || sport == .hockey
                || sport == .football || sport == .soccer || sport == .golf {
                do {
                    let events = try await supabaseService.fetchCachedOdds(sportKey: sport.rawValue)
                    await MainActor.run { eventsBySport[sport] = events }
                    saveToDocuments(events, filename: "\(sport.rawValue).json")
                } catch {
                    self.error = error
                    let local: [ResponseBody] = loadFromBundle(sport.rawValue)
                    await MainActor.run { eventsBySport[sport] = local }
                }
                continue
            }

            // Multi-key sports via Supabase cache (fighting only)
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
                let finalEvents = allEvents
                await MainActor.run { eventsBySport[sport] = finalEvents }
                continue
            }
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

    // MARK: - Soccer Assets (Logos & Headshots)

    /// Fetch team logos and player headshots from Supabase for Soccer (run once on launch)
    func fetchSoccerAssets() async {
        do {
            async let teamsTask = supabaseService.fetchSoccerTeamLogos()
            async let playersTask = supabaseService.fetchSoccerPlayerHeadshots()

            let (teams, players) = try await (teamsTask, playersTask)

            await MainActor.run {
                for team in teams {
                    teamLogoURLs[team.teamName] = team.logoUrl
                }
                for player in players {
                    // Skip players with no headshot available (marked "none" by the Edge Function)
                    guard player.headshotUrl != "none" else { continue }
                    playerHeadshotURLs[player.playerName] = player.headshotUrl
                    // Also store under accent-stripped name so Odds API names
                    // like "Julian Alvarez" match ESPN's "Julián Álvarez"
                    let normalized = normalizedName(player.playerName)
                    if normalized != player.playerName {
                        playerHeadshotURLs[normalized] = player.headshotUrl
                    }
                }
            }
        } catch {
            // Silent failure — UI will show placeholder icons
        }
    }

    // MARK: - Golf Assets (Golfer Headshots)

    /// Fetch golfer headshots from Supabase (run once on launch)
    func fetchGolfAssets() async {
        do {
            let rows = try await supabaseService.fetchGolferHeadshots()
            await MainActor.run {
                for row in rows {
                    if let url = row.headshotUrl {
                        playerHeadshotURLs[row.golferName] = url
                    }
                }
            }
        } catch {
            // Silent failure — UI will show golf icon fallback
        }
    }

    // MARK: - Fighting Assets (Fighter Headshots)

    /// Fetch fighter headshots from Supabase (run once on launch)
    func fetchFightingAssets() async {
        do {
            let rows = try await supabaseService.fetchFighterHeadshots()
            await MainActor.run {
                for row in rows {
                    if let url = row.headshotUrl {
                        playerHeadshotURLs[row.fighterName] = url
                    }
                }
            }
        } catch {
            // Silent failure — UI will show silhouette fallback
        }
    }

    // MARK: - Team & Player Stats

    /// Whether the given sport supports team/player stats modals.
    static let statsSports: Set<SportCategory> = [.basketball, .baseball, .hockey, .football]

    /// Fetch team and player stats for a sport from Supabase (cached once per sport per session).
    func fetchStats(for sport: SportCategory) async {
        guard Self.statsSports.contains(sport) else { return }
        guard !statsFetchedForSports.contains(sport.rawValue) else { return }
        statsFetchedForSports.insert(sport.rawValue)

        do {
            async let teamsTask = supabaseService.fetchTeamStats(sportKey: sport.rawValue)
            async let playersTask = supabaseService.fetchPlayerStats(sportKey: sport.rawValue)

            let (teams, players) = try await (teamsTask, playersTask)

            await MainActor.run {
                for row in teams {
                    teamStatsByName[row.teamName] = row.stats
                }
                for row in players {
                    playerStatsByName[row.playerName] = row.stats
                }
            }
        } catch {
            // Silent failure — modals will show "Stats unavailable"
        }
    }

    // MARK: - Player Props

    /// Prefetch player props for all events (used by BestEVPage to scan all props for EV)
    func prefetchAllPlayerProps() async {
        await withTaskGroup(of: Void.self) { group in
            for sport in SportCategory.allCases where sport.availableMarkets.contains(.playerProps) {
                for event in events(for: sport) {
                    group.addTask {
                        await self.fetchPlayerProps(eventId: event.id)
                    }
                }
            }
        }
    }

    /// Re-fetch player props for every event already in the cache.
    /// Called by the 5-min background refresh loop so opened BetPages stay fresh.
    func refreshCachedPlayerProps() async {
        let eventIds = Array(playerPropsByEvent.keys)
        for eventId in eventIds {
            do {
                let result = try await supabaseService.fetchCachedPlayerProps(eventId: eventId)
                await MainActor.run {
                    playerPropsByEvent[eventId] = result.props
                    playerTeamsByEvent[eventId] = result.playerTeams
                }
            } catch {
                // Keep existing cached props on failure — don't wipe the UI
            }
        }
    }

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

    /// Strip diacritics/accents for fuzzy name matching (e.g. "Julián Álvarez" → "Julian Alvarez")
    private func normalizedName(_ name: String) -> String {
        name.applyingTransform(.stripDiacritics, reverse: false) ?? name
    }

    private func loadFromBundle(_ filename: String) -> [ResponseBody] {
        guard let url = Bundle.main.url(forResource: filename, withExtension: "json") else {
            return []
        }
        guard let data = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder().decode([ResponseBody].self, from: data)) ?? []
    }
}
