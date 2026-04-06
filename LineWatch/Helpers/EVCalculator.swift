//
//  EVCalculator.swift
//  LineWatch
//
//  Created by Steven Nguyen on 4/6/26.
//

import Foundation

// MARK: - Best EV Bet Model

struct BestEVBet: Identifiable {
    var id: String { "\(event.id)-\(bookmakerTitle)-\(outcomeName)-\(marketType.rawValue)-\(playerName ?? "")" }

    let event: ResponseBody
    let outcomeName: String        // e.g., "Boston Celtics", "Over", "Under"
    let bookmakerTitle: String     // e.g., "DraftKings"
    let odds: Int                  // e.g., +155
    let evPercent: Double          // e.g., 3.2
    let trueProbability: Double    // e.g., 0.418
    let impliedProbability: Double // e.g., 0.392 (what the bookmaker's odds imply)
    let consensusOdds: Int         // average American odds across all books
    let bookmakerCount: Int        // how many books were used in consensus
    let marketType: MarketType     // h2h, spreads, totals, outrights, playerProps
    let sport: SportCategory       // which sport this bet belongs to
    let point: Double?             // spread/total/prop line value
    let playerName: String?        // player name for props

    /// Human-readable description of the bet for the card UI
    var betDescription: String {
        let oddsStr = odds > 0 ? "+\(odds)" : "\(odds)"
        switch marketType {
        case .h2h:
            return "\(outcomeName) ML \(oddsStr) on \(bookmakerTitle)"
        case .spreads:
            if let pt = point {
                return "\(outcomeName) \(formatPt(pt)) (\(oddsStr)) on \(bookmakerTitle)"
            }
            return "\(outcomeName) \(oddsStr) on \(bookmakerTitle)"
        case .totals:
            if let pt = point {
                let ptStr = pt.truncatingRemainder(dividingBy: 1) == 0 ? "\(Int(pt))" : "\(pt)"
                return "\(outcomeName) \(ptStr) (\(oddsStr)) on \(bookmakerTitle)"
            }
            return "\(outcomeName) \(oddsStr) on \(bookmakerTitle)"
        case .outrights:
            return "\(outcomeName) \(oddsStr) on \(bookmakerTitle)"
        case .playerProps:
            if let name = playerName, let pt = point {
                let ptStr = pt.truncatingRemainder(dividingBy: 1) == 0 ? "\(Int(pt))" : "\(pt)"
                return "\(name) \(outcomeName) \(ptStr) (\(oddsStr)) on \(bookmakerTitle)"
            }
            return "\(outcomeName) \(oddsStr) on \(bookmakerTitle)"
        }
    }

    private func formatPt(_ pt: Double) -> String {
        let value = pt.truncatingRemainder(dividingBy: 1) == 0 ? "\(Int(pt))" : "\(pt)"
        return pt > 0 ? "+\(value)" : value
    }
}

// MARK: - EV Calculator

enum EVCalculator {

    // MARK: - Public API

    /// Find the single highest positive-EV bet across all events and all market types.
    static func findBestEV(
        eventsBySport: [SportCategory: [ResponseBody]],
        playerPropsByEvent: [String: ResponseBody] = [:]
    ) -> BestEVBet? {
        var best: BestEVBet?
        for (sport, events) in eventsBySport {
            if let candidate = findBestEV(for: sport, events: events, playerPropsByEvent: playerPropsByEvent) {
                if candidate.evPercent > (best?.evPercent ?? 0) {
                    best = candidate
                }
            }
        }
        return best
    }

    /// Find the best EV bet for a single sport across all market types.
    static func findBestEV(
        for sport: SportCategory,
        events: [ResponseBody],
        playerPropsByEvent: [String: ResponseBody] = [:]
    ) -> BestEVBet? {
        var best: BestEVBet?

        for event in events {
            // Evaluate each available market type for this sport
            for marketType in sport.availableMarkets {
                let candidate: BestEVBet?

                switch marketType {
                case .h2h:
                    candidate = evaluateMarket(key: "h2h", marketType: .h2h, event: event, sport: sport)
                case .spreads:
                    candidate = evaluateSpreads(event: event, sport: sport)
                case .totals:
                    candidate = evaluateTotals(event: event, sport: sport)
                case .outrights:
                    candidate = evaluateMarket(key: "outrights", marketType: .outrights, event: event, sport: sport)
                case .playerProps:
                    if let propsData = playerPropsByEvent[event.id] {
                        candidate = evaluatePlayerProps(event: event, propsData: propsData, sport: sport)
                    } else {
                        candidate = nil
                    }
                }

                if let candidate, candidate.evPercent > (best?.evPercent ?? 0) {
                    best = candidate
                }
            }
        }

        return best
    }

    /// Find best EV bet for each in-season sport (one per sport, ordered by sport).
    static func findBestEVPerSport(
        eventsBySport: [SportCategory: [ResponseBody]],
        playerPropsByEvent: [String: ResponseBody] = [:]
    ) -> [BestEVBet] {
        var results: [BestEVBet] = []
        for sport in SportCategory.inSeason {
            guard let events = eventsBySport[sport] else { continue }
            if let best = findBestEV(for: sport, events: events, playerPropsByEvent: playerPropsByEvent) {
                results.append(best)
            }
        }
        return results
    }

    // MARK: - Market Evaluators

    /// Evaluate a simple market (h2h or outrights) where outcomes are identified by name.
    private static func evaluateMarket(
        key: String,
        marketType: MarketType,
        event: ResponseBody,
        sport: SportCategory
    ) -> BestEVBet? {
        let bookmakerMarkets: [(title: String, outcomes: [Outcome])] = event.bookmakers.compactMap { bm in
            guard let m = bm.markets.first(where: { $0.key == key }) else { return nil }
            guard m.outcomes.count >= 2 else { return nil }
            return (bm.title, m.outcomes)
        }

        return bestEVFromOutcomes(
            bookmakerOutcomes: bookmakerMarkets,
            event: event,
            sport: sport,
            marketType: marketType
        )
    }

    /// Evaluate spreads market — only compare bookmakers offering the same point value.
    private static func evaluateSpreads(event: ResponseBody, sport: SportCategory) -> BestEVBet? {
        let bookmakerMarkets: [(title: String, outcomes: [Outcome])] = event.bookmakers.compactMap { bm in
            guard let m = bm.markets.first(where: { $0.key == "spreads" }) else { return nil }
            guard m.outcomes.count >= 2 else { return nil }
            return (bm.title, m.outcomes)
        }
        guard bookmakerMarkets.count >= 3 else { return nil }

        // Find the most common absolute point value (consensus line)
        let points = bookmakerMarkets.flatMap(\.outcomes).compactMap { $0.point }.map { abs($0) }
        guard let consensusPoint = mostCommon(points) else { return nil }

        // Filter to bookmakers at the consensus line
        let filtered: [(title: String, outcomes: [Outcome])] = bookmakerMarkets.compactMap { (title, outcomes) in
            let matching = outcomes.filter { abs($0.point ?? -999) == consensusPoint }
            guard matching.count >= 2 else { return nil }
            return (title, matching)
        }

        return bestEVFromOutcomes(
            bookmakerOutcomes: filtered,
            event: event,
            sport: sport,
            marketType: .spreads
        )
    }

    /// Evaluate totals market — only compare bookmakers offering the same total line.
    private static func evaluateTotals(event: ResponseBody, sport: SportCategory) -> BestEVBet? {
        let bookmakerMarkets: [(title: String, outcomes: [Outcome])] = event.bookmakers.compactMap { bm in
            guard let m = bm.markets.first(where: { $0.key == "totals" }) else { return nil }
            guard m.outcomes.count >= 2 else { return nil }
            return (bm.title, m.outcomes)
        }
        guard bookmakerMarkets.count >= 3 else { return nil }

        // Find the most common total point value
        let points = bookmakerMarkets.flatMap(\.outcomes).compactMap { $0.point }
        guard let consensusPoint = mostCommon(points) else { return nil }

        // Filter to bookmakers at the consensus line
        let filtered: [(title: String, outcomes: [Outcome])] = bookmakerMarkets.compactMap { (title, outcomes) in
            let matching = outcomes.filter { $0.point == consensusPoint }
            guard matching.count >= 2 else { return nil }
            return (title, matching)
        }

        return bestEVFromOutcomes(
            bookmakerOutcomes: filtered,
            event: event,
            sport: sport,
            marketType: .totals
        )
    }

    /// Evaluate all player prop markets for one event.
    private static func evaluatePlayerProps(
        event: ResponseBody,
        propsData: ResponseBody,
        sport: SportCategory
    ) -> BestEVBet? {
        var best: BestEVBet?

        let propTypes = PlayerPropType.cases(for: sport)

        for propType in propTypes {
            let marketKey = propType.marketKey

            // Collect this market from each bookmaker in the props data
            let bookmakerMarkets: [(title: String, outcomes: [Outcome])] = propsData.bookmakers.compactMap { bm in
                guard let m = bm.markets.first(where: { $0.key == marketKey }) else { return nil }
                return (bm.title, m.outcomes)
            }
            guard bookmakerMarkets.count >= 3 else { continue }

            // Find unique (player, point) pairs
            var playerLines = Set<String>()
            for (_, outcomes) in bookmakerMarkets {
                for o in outcomes {
                    if let desc = o.description, let pt = o.point {
                        playerLines.insert("\(desc)|\(pt)")
                    }
                }
            }

            for playerLine in playerLines {
                let parts = playerLine.split(separator: "|", maxSplits: 1)
                guard parts.count == 2,
                      let lineValue = Double(parts[1]) else { continue }
                let playerName = String(parts[0])

                // Filter outcomes for this player+point from each bookmaker
                let filtered: [(title: String, outcomes: [Outcome])] = bookmakerMarkets.compactMap { (title, outcomes) in
                    let matching = outcomes.filter { $0.description == playerName && $0.point == lineValue }
                    guard matching.count >= 2 else { return nil }
                    return (title, matching)
                }

                if let candidate = bestEVFromOutcomes(
                    bookmakerOutcomes: filtered,
                    event: event,
                    sport: sport,
                    marketType: .playerProps,
                    playerName: playerName
                ) {
                    if candidate.evPercent > (best?.evPercent ?? 0) {
                        best = candidate
                    }
                }
            }
        }

        return best
    }

    // MARK: - Core EV Engine

    /// Core EV evaluation: given the same bet from multiple bookmakers, find the highest +EV.
    private static func bestEVFromOutcomes(
        bookmakerOutcomes: [(title: String, outcomes: [Outcome])],
        event: ResponseBody,
        sport: SportCategory,
        marketType: MarketType,
        playerName: String? = nil
    ) -> BestEVBet? {
        guard bookmakerOutcomes.count >= 3 else { return nil }

        let outcomeNames = uniqueOutcomeNames(from: bookmakerOutcomes.map(\.outcomes))
        guard outcomeNames.count >= 2 else { return nil }

        // Step 1: Average implied probability for each outcome
        var avgImplied: [String: Double] = [:]
        for name in outcomeNames {
            var probs: [Double] = []
            for (_, outcomes) in bookmakerOutcomes {
                if let o = outcomes.first(where: { $0.name == name }) {
                    probs.append(impliedProbability(americanOdds: o.price))
                }
            }
            guard !probs.isEmpty else { continue }
            avgImplied[name] = probs.reduce(0, +) / Double(probs.count)
        }

        // Step 2: Normalize to remove vig
        let total = avgImplied.values.reduce(0, +)
        guard total > 0 else { return nil }

        var trueProbs: [String: Double] = [:]
        for (name, prob) in avgImplied {
            trueProbs[name] = prob / total
        }

        // Step 3: Find highest +EV
        var best: BestEVBet?
        for (bookTitle, outcomes) in bookmakerOutcomes {
            for outcome in outcomes {
                guard let trueProb = trueProbs[outcome.name] else { continue }

                let decimalPayout = decimalOdds(americanOdds: outcome.price)
                let ev = (trueProb * decimalPayout) - 1.0
                let evPct = ev * 100.0

                guard evPct > 0 else { continue }

                let consensus = averageAmericanOdds(
                    for: outcome.name,
                    across: bookmakerOutcomes.map(\.outcomes)
                )

                let candidate = BestEVBet(
                    event: event,
                    outcomeName: outcome.name,
                    bookmakerTitle: bookTitle,
                    odds: outcome.price,
                    evPercent: evPct,
                    trueProbability: trueProb,
                    impliedProbability: impliedProbability(americanOdds: outcome.price),
                    consensusOdds: consensus,
                    bookmakerCount: bookmakerOutcomes.count,
                    marketType: marketType,
                    sport: sport,
                    point: outcome.point,
                    playerName: playerName ?? outcome.description
                )

                if evPct > (best?.evPercent ?? 0) {
                    best = candidate
                }
            }
        }

        return best
    }

    // MARK: - Math Helpers

    /// Convert American odds to implied probability (0.0 – 1.0)
    static func impliedProbability(americanOdds: Int) -> Double {
        if americanOdds < 0 {
            let absOdds = Double(abs(americanOdds))
            return absOdds / (absOdds + 100.0)
        } else {
            return 100.0 / (Double(americanOdds) + 100.0)
        }
    }

    /// Convert American odds to decimal odds (payout multiplier including stake)
    static func decimalOdds(americanOdds: Int) -> Double {
        if americanOdds < 0 {
            return 1.0 + (100.0 / Double(abs(americanOdds)))
        } else {
            return 1.0 + (Double(americanOdds) / 100.0)
        }
    }

    /// Convert probability back to American odds for display
    static func probabilityToAmericanOdds(_ probability: Double) -> Int {
        guard probability > 0, probability < 1 else { return 0 }
        if probability >= 0.5 {
            return -Int((probability / (1.0 - probability)) * 100.0)
        } else {
            return Int(((1.0 - probability) / probability) * 100.0)
        }
    }

    /// Find the most common value in an array
    private static func mostCommon<T: Hashable>(_ values: [T]) -> T? {
        var counts: [T: Int] = [:]
        for v in values { counts[v, default: 0] += 1 }
        return counts.max(by: { $0.value < $1.value })?.key
    }

    /// Get unique outcome names across all bookmaker outcome arrays
    private static func uniqueOutcomeNames(from allOutcomes: [[Outcome]]) -> [String] {
        var seen = Set<String>()
        var names: [String] = []
        for outcomes in allOutcomes {
            for outcome in outcomes {
                if seen.insert(outcome.name).inserted {
                    names.append(outcome.name)
                }
            }
        }
        return names
    }

    /// Calculate average American odds for a specific outcome across bookmakers
    private static func averageAmericanOdds(for outcomeName: String, across allOutcomes: [[Outcome]]) -> Int {
        var probabilities: [Double] = []
        for outcomes in allOutcomes {
            if let outcome = outcomes.first(where: { $0.name == outcomeName }) {
                probabilities.append(impliedProbability(americanOdds: outcome.price))
            }
        }
        guard !probabilities.isEmpty else { return 0 }
        let avgProb = probabilities.reduce(0, +) / Double(probabilities.count)
        return probabilityToAmericanOdds(avgProb)
    }
}
