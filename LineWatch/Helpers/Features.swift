//
//  Features.swift
//  LineWatch
//
//  Compile-time feature flags. Use these to hide in-flight features behind
//  a kill switch so they can ship in code without being visible to users
//  until we're ready to enable them at the next App Store release.
//

import Foundation

enum Features {
    /// Hit-rate / "Recent Trends" badges on player prop rows.
    /// Backend (snapshot + post-game pipeline) is live, but the data
    /// accumulates over time — this stays off until 1.1 ships and we've
    /// collected ~2-3 weeks of NBA games for meaningful averages.
    static let hitRatesEnabled = true
}
