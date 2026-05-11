//
//  SportsbookURLs.swift
//  LineWatch
//
//  Created by Steven Nguyen on 4/6/26.
//
//  Resolves the right URL to open when the user taps "Place Bet". Most
//  sportsbooks open in their iOS app automatically via Universal Links —
//  iOS sees an HTTPS URL pointing at their domain, fetches the site's
//  apple-app-site-association file, matches it to the installed app, and
//  routes there transparently with no special handling from us.
//
//  Kalshi is the exception: their AASA file sits behind a Vercel anti-bot
//  wall, so Apple's CDN can't fetch it and Universal Links never engages
//  — taps fall through to Safari even with the Kalshi app installed.
//  For sportsbooks in `sportsbookAppSchemes`, we try the custom URL scheme
//  first (gated by `canOpenURL`) and only fall back to the web URL if the
//  app isn't there.
//

import Foundation
import UIKit

/// Maps sportsbook display names (from the Odds API) to their website URLs.
/// Replace with affiliate links once partnership is established.
///
/// Domain notes for tricky cases:
/// - BetMGM: `sports.betmgm.com` doesn't serve an AASA file at all (returns
///   the website's HTML). The root `betmgm.com` does serve a valid AASA,
///   so we use that here — gives Universal Links a chance to fire.
/// - BetRivers: `www.betrivers.com` 404s on AASA. `app.betrivers.com` is the
///   only host serving one (with narrow path patterns); same site contents.
let sportsbookURLs: [String: String] = [
    "DraftKings":   "https://sportsbook.draftkings.com",
    "FanDuel":      "https://sportsbook.fanduel.com",
    "BetMGM":       "https://betmgm.com",
    "BetOnline.ag": "https://www.betonline.ag",
    "BetRivers":    "https://app.betrivers.com",
    "Bovada":       "https://www.bovada.lv",
    "MyBookie.ag":  "https://www.mybookie.ag",
    "LowVig.ag":    "https://www.lowvig.ag",
    "Kalshi":       "https://kalshi.com",
    "Caesars":      "https://www.caesars.com/sportsbook-and-casino",
    "Fanatics":     "https://sportsbook.fanatics.com",
    "BetUS":        "https://www.betus.com",
]

/// Custom URL schemes for sportsbooks whose Universal Links don't work,
/// so we need to detect-and-deeplink to the app explicitly. Every scheme
/// listed here MUST also be declared in `LSApplicationQueriesSchemes` in
/// Info.plist — without that, iOS sandboxes `canOpenURL` to always
/// return false (silent failure mode, looks identical to "app not
/// installed").
///
/// DraftKings, FanDuel, and Caesars are omitted intentionally — their
/// AASA files work, so Universal Links handles the app-routing handoff
/// transparently when the user taps the HTTPS URL.
///
/// The BetMGM / BetRivers / Fanatics entries below are unverified guesses
/// based on each app's brand name on the App Store. We can't test them
/// without the apps installed. The failure mode is safe: if a scheme is
/// wrong, `canOpenURL` returns false and `placeBetURL(for:)` falls through
/// to the HTTPS URL — identical to the current behavior. If a scheme is
/// right, the user gets the app handoff for free. Pure upside, no
/// regression risk.
let sportsbookAppSchemes: [String: String] = [
    "Kalshi":    "kalshi://",             // verified working on device
    "BetMGM":    "betmgm://",             // unverified; falls back to web if wrong
    "BetRivers": "betrivers://",          // unverified; falls back to web if wrong
    "Fanatics":  "fanaticssportsbook://", // unverified; falls back to web if wrong
]

/// Resolves the URL to open for a Place Bet tap. If we know an app scheme
/// for this sportsbook AND the app is installed, returns the scheme URL
/// (which launches the app). Otherwise returns the HTTPS URL — which
/// itself may open the app via Universal Links for sportsbooks with
/// working AASA setups, or open Safari otherwise.
///
/// Returns nil only when the sportsbook has neither a scheme nor a web
/// URL configured — the caller should hide the button in that case.
func placeBetURL(for bookmakerTitle: String) -> URL? {
    if let scheme = sportsbookAppSchemes[bookmakerTitle],
       let schemeURL = URL(string: scheme),
       UIApplication.shared.canOpenURL(schemeURL) {
        return schemeURL
    }
    if let webStr = sportsbookURLs[bookmakerTitle],
       let webURL = URL(string: webStr) {
        return webURL
    }
    return nil
}
