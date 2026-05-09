//
//  HitRateSummary.swift
//  LineWatch
//
//  Result of a hit-rate query: how many of the player's last N games hit
//  their prop. `total` is what we actually have data for (may be < lastN
//  if the player is new or just returned from injury). The badge renders
//  "X of last N" only when `total >= lastN`; otherwise it shows the
//  smaller window we have data for.
//

import Foundation

struct HitRateSummary: Equatable {
    let hits: Int
    let total: Int
    /// The window the user requested (5, 10, or 15). Used by the badge to
    /// render the right label even when `total < lastN` (sparse data).
    let lastN: Int

    /// True when we have at least one completed game on file.
    var hasData: Bool { total > 0 }

    /// Hit percentage, 0.0 to 1.0. `nil` when no data yet.
    var rate: Double? {
        guard total > 0 else { return nil }
        return Double(hits) / Double(total)
    }
}
