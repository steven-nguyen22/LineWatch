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

    /// Hit-rate caches. Keyed lookups so each modal open is at-most one fetch
    /// per session — data only changes once daily after the 9am EDT grader,
    /// so the cache lifetime can match the app session (no auto-refresh).
    /// `nil` = not yet fetched, `[]` = fetched but no data, populated = render.
    var playerHitRatesByKey: [String: [HitRateRow]] = [:]   // key = "playerName|propTypeMarketKey"
    var teamHitRatesByName:  [String: [TeamHitRateRow]] = [:]

    /// Top-3 hot streaks per in-season sport, written daily by the
    /// `compute-hot-streaks` edge function. `nil` = not yet fetched (loading);
    /// `[]` = fetched but empty (off-season for all 4 sports — rare).
    /// Session-lifetime cache, same rationale as the hit-rate caches.
    var hotStreaks: [Streak]?

    /// Top-3 cold streaks per in-season sport, written by the same
    /// `compute-hot-streaks` edge function (which writes both tables in
    /// one run). Same caching semantics as `hotStreaks`.
    var coldStreaks: [Streak]?
    var isLoading = false
    var error: Error?

    /// Wall-clock time of the next scheduled background refresh. Updated by the
    /// 5-min refresh loop in ContentView; read by RefreshCountdownButton to
    /// render the countdown popover. `nil` means no refresh is currently scheduled
    /// (e.g. signed out or pre-initial-load). Persists across backgrounding so
    /// the countdown can resume from where it left off.
    var nextRefreshAt: Date?

    /// Wall-clock time of the most recent completed refresh. Used by the
    /// foreground stale-check: if the app was backgrounded past `nextRefreshAt`,
    /// we fetch immediately on return instead of waiting a new 5-min cycle.
    var lastRefreshAt: Date?

    /// True while the refresh loop is actively awaiting `fetchAndCacheAll` /
    /// `refreshCachedPlayerProps`. Drives the "Refreshing…" label in the
    /// countdown popover so the user sees explicit in-flight feedback.
    var isRefreshing: Bool = false

    private let supabaseService = SupabaseService()

    /// Sports where Kalshi moneyline markets are available. Kept as raw keys
    /// so the merge path can be gated without a SportCategory enum dependency.
    private static let kalshiSupportedKeys: Set<String> = [
        "basketball_nba",
        "americanfootball_nfl",
        "baseball_mlb",
        "icehockey_nhl",
    ]

    /// Append Kalshi's moneyline bookmaker to any event whose teams match.
    /// Matching is exact on (away_team, home_team) — the edge function already
    /// normalized Kalshi team names to The Odds API strings — with a ±1 day
    /// tolerance on commence_date to absorb timezone slack for late-night games.
    /// If a match isn't found, the event is passed through untouched.
    private func mergeKalshi(into events: [ResponseBody], from kalshi: [KalshiEvent]) -> [ResponseBody] {
        guard !kalshi.isEmpty else { return events }
        let isoFormatter = ISO8601DateFormatter()
        let dayFormatter = DateFormatter()
        dayFormatter.dateFormat = "yyyy-MM-dd"
        dayFormatter.timeZone = TimeZone(identifier: "UTC")

        return events.map { event in
            guard let away = event.awayTeam, let home = event.homeTeam else { return event }
            let eventDate: Date? = event.commenceTime.flatMap { isoFormatter.date(from: $0) }

            let match = kalshi.first { k in
                guard k.awayTeam == away, k.homeTeam == home else { return false }
                guard let d = eventDate, let kd = dayFormatter.date(from: k.commenceDate) else {
                    return true // no date to compare → accept the team-name match
                }
                return abs(d.timeIntervalSince(kd)) <= 86_400 * 1.5
            }

            guard let match else { return event }
            return ResponseBody(
                id: event.id,
                sportKey: event.sportKey,
                sportTitle: event.sportTitle,
                commenceTime: event.commenceTime,
                homeTeam: event.homeTeam,
                awayTeam: event.awayTeam,
                bookmakers: event.bookmakers + [match.bookmaker]
            )
        }
    }

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
            || sport == .football || sport == .golf {
            do {
                let events = try await supabaseService.fetchCachedOdds(sportKey: sport.rawValue)
                let merged = await mergeKalshiIfSupported(events: events, sportKey: sport.rawValue)
                await MainActor.run { eventsBySport[sport] = merged }
                saveToDocuments(events, filename: "\(sport.rawValue).json")
            } catch {
                self.error = error
                let local: [ResponseBody] = loadFromBundle(sport.rawValue)
                await MainActor.run { eventsBySport[sport] = local }
            }
            return
        }

        // Multi-key sports via Supabase cache: fighting (MMA + boxing) and
        // soccer (Champions League + FIFA World Cup). Neither is Kalshi-merged.
        if sport == .fighting || sport == .soccer {
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

    /// Merges Kalshi moneyline prices into the event list for the 4 supported
    /// leagues. A Kalshi fetch failure (network / decode / missing row) is
    /// swallowed — Kalshi is strictly additive and must never fail the main
    /// odds feed. Sports outside the supported set pass through unchanged.
    private func mergeKalshiIfSupported(events: [ResponseBody], sportKey: String) async -> [ResponseBody] {
        guard Self.kalshiSupportedKeys.contains(sportKey) else { return events }
        let kalshi = (try? await supabaseService.fetchKalshiEvents(sportKey: sportKey)) ?? []
        return mergeKalshi(into: events, from: kalshi)
    }

    // Fetch all sports from API
    func fetchAndCacheAll() async {
        isLoading = true
        defer { isLoading = false }

        for sport in SportCategory.allCases {
            // Single-key sports via Supabase cache
            if sport == .basketball || sport == .baseball || sport == .hockey
                || sport == .football || sport == .golf {
                do {
                    let events = try await supabaseService.fetchCachedOdds(sportKey: sport.rawValue)
                    let merged = await mergeKalshiIfSupported(events: events, sportKey: sport.rawValue)
                    await MainActor.run { eventsBySport[sport] = merged }
                    saveToDocuments(events, filename: "\(sport.rawValue).json")
                } catch {
                    self.error = error
                    let local: [ResponseBody] = loadFromBundle(sport.rawValue)
                    await MainActor.run { eventsBySport[sport] = local }
                }
                continue
            }

            // Multi-key sports via Supabase cache: fighting (MMA + boxing) and
            // soccer (Champions League + FIFA World Cup). Neither is Kalshi-merged.
            if sport == .fighting || sport == .soccer {
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

    /// Fetch team logos and player headshots from Supabase for NFL (run once on launch).
    /// Reads from the unified `nfl_players` table — see consolidation
    /// migration `20260510000000_consolidate_nfl_players.sql`.
    func fetchNFLAssets() async {
        do {
            async let teamsTask = supabaseService.fetchNFLTeamLogos()
            async let playersTask = supabaseService.fetchNFLPlayers()

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

    // MARK: - Hit Rates

    /// Lazy-loads + caches the player's last 15 graded games for a given prop.
    /// Mirrors `fetchPlayerProps(eventId:)` — first call fetches, subsequent
    /// calls return immediately. Cache lives for the app session; data only
    /// changes once per day after the 9am EDT grader so this is sufficient.
    func fetchPlayerHitRates(
        playerName: String,
        sportKey: String,
        propType: PlayerPropType
    ) async {
        let key = "\(playerName)|\(propType.marketKey)"
        guard playerHitRatesByKey[key] == nil else { return }   // already cached

        do {
            let rows = try await supabaseService.fetchHitRateRows(
                playerName: playerName,
                sportKey: sportKey,
                propType: propType.marketKey
            )
            await MainActor.run {
                playerHitRatesByKey[key] = rows
            }
        } catch {
            // Empty cache entry → modal renders "—". Distinct from `nil`
            // which still means "haven't fetched yet" (loading state).
            await MainActor.run {
                playerHitRatesByKey[key] = []
            }
        }
    }

    /// Lazy-loads + caches the team's last 15 graded games. Same pattern.
    /// One cache entry covers both Wins History (derived from `actualMargin`)
    /// and Spreads History (`covered`) — they're columns on the same row.
    func fetchTeamHitRates(teamName: String, sportKey: String) async {
        guard teamHitRatesByName[teamName] == nil else { return }

        do {
            let rows = try await supabaseService.fetchTeamHitRateRows(
                teamName: teamName,
                sportKey: sportKey
            )
            await MainActor.run {
                teamHitRatesByName[teamName] = rows
            }
        } catch {
            await MainActor.run {
                teamHitRatesByName[teamName] = []
            }
        }
    }

    /// Lazy-loads + caches the top-3-per-sport hot streaks. Powers the
    /// HotStreaksPage Hot tab. One round-trip per app session; data only
    /// changes once daily after the 13:30 UTC compute job.
    func fetchHotStreaksIfNeeded() async {
        guard hotStreaks == nil else { return }   // already cached this session

        do {
            let rows = try await supabaseService.fetchHotStreaks()
            await MainActor.run {
                hotStreaks = rows
            }
        } catch {
            // Empty cache → page renders "no streaks yet" placeholder.
            await MainActor.run {
                hotStreaks = []
            }
        }
    }

    /// Lazy-loads + caches the top-3-per-sport cold streaks. Powers the
    /// HotStreaksPage Cold tab. Same caching pattern as `fetchHotStreaksIfNeeded`.
    func fetchColdStreaksIfNeeded() async {
        guard coldStreaks == nil else { return }

        do {
            let rows = try await supabaseService.fetchColdStreaks()
            await MainActor.run {
                coldStreaks = rows
            }
        } catch {
            await MainActor.run {
                coldStreaks = []
            }
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
