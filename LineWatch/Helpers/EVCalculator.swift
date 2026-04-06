//
//  EVCalculator.swift
//  LineWatch
//
//  Created by Steven Nguyen on 4/6/26.
//

import Foundation

// MARK: - Best EV Bet Model

struct BestEVBet {
    let event: ResponseBody
    let outcomeName: String        // e.g., "Boston Celtics"
    let bookmakerTitle: String     // e.g., "DraftKings"
    let odds: Int                  // e.g., +155
    let evPercent: Double          // e.g., 3.2
    let trueProbability: Double    // e.g., 0.418
    let impliedProbability: Double // e.g., 0.392 (what the bookmaker's odds imply)
    let consensusOdds: Int         // average American odds across all books
    let bookmakerCount: Int        // how many books were used in consensus
    let marketType: MarketType     // always .h2h for now
}

// MARK: - EV Calculator

enum EVCalculator {

    /// Find the single highest positive-EV moneyline bet across all events.
    /// Returns nil if no +EV opportunity exists.
    static func findBestEV(eventsBySport: [SportCategory: [ResponseBody]]) -> BestEVBet? {
        var best: BestEVBet?

        for (_, events) in eventsBySport {
            for event in events {
                // Skip golf outrights — too many outcomes, not a clean 2-way market
                guard !event.isGolf else { continue }

                // Collect all h2h markets across bookmakers
                let bookmakerMarkets: [(bookmakerTitle: String, outcomes: [Outcome])] = event.bookmakers.compactMap { bookmaker in
                    guard let market = bookmaker.markets.first(where: { $0.key == MarketType.h2h.rawValue }) else {
                        return nil
                    }
                    guard market.outcomes.count >= 2 else { return nil }
                    return (bookmaker.title, market.outcomes)
                }

                // Need at least 3 bookmakers for a reliable consensus
                guard bookmakerMarkets.count >= 3 else { continue }

                // Get all unique outcome names (e.g., ["Boston Celtics", "Miami Heat"])
                let outcomeNames = uniqueOutcomeNames(from: bookmakerMarkets.map(\.outcomes))
                guard outcomeNames.count >= 2 else { continue }

                // Step 1: Calculate average implied probability for each outcome
                var avgImplied: [String: Double] = [:]
                for name in outcomeNames {
                    var probabilities: [Double] = []
                    for (_, outcomes) in bookmakerMarkets {
                        if let outcome = outcomes.first(where: { $0.name == name }) {
                            probabilities.append(impliedProbability(americanOdds: outcome.price))
                        }
                    }
                    guard !probabilities.isEmpty else { continue }
                    avgImplied[name] = probabilities.reduce(0, +) / Double(probabilities.count)
                }

                // Step 2: Normalize to remove vig (sum to 1.0)
                let totalImplied = avgImplied.values.reduce(0, +)
                guard totalImplied > 0 else { continue }

                var trueProbabilities: [String: Double] = [:]
                for (name, prob) in avgImplied {
                    trueProbabilities[name] = prob / totalImplied
                }

                // Step 3: Calculate EV for each bookmaker × outcome combination
                for (bookmakerTitle, outcomes) in bookmakerMarkets {
                    for outcome in outcomes {
                        guard let trueProb = trueProbabilities[outcome.name] else { continue }

                        let decimalPayout = decimalOdds(americanOdds: outcome.price)
                        let ev = (trueProb * decimalPayout) - 1.0
                        let evPercent = ev * 100.0

                        // Only consider positive EV
                        guard evPercent > 0 else { continue }

                        // Calculate consensus odds for display
                        let consensusOdds = averageAmericanOdds(
                            for: outcome.name,
                            across: bookmakerMarkets.map(\.outcomes)
                        )

                        let candidate = BestEVBet(
                            event: event,
                            outcomeName: outcome.name,
                            bookmakerTitle: bookmakerTitle,
                            odds: outcome.price,
                            evPercent: evPercent,
                            trueProbability: trueProb,
                            impliedProbability: impliedProbability(americanOdds: outcome.price),
                            consensusOdds: consensusOdds,
                            bookmakerCount: bookmakerMarkets.count,
                            marketType: .h2h
                        )

                        if let current = best {
                            if evPercent > current.evPercent {
                                best = candidate
                            }
                        } else {
                            best = candidate
                        }
                    }
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
            // Favorite → negative odds
            return -Int((probability / (1.0 - probability)) * 100.0)
        } else {
            // Underdog → positive odds
            return Int(((1.0 - probability) / probability) * 100.0)
        }
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
        // Average via implied probability, then convert back (more accurate than averaging odds directly)
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
