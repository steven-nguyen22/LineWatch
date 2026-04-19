//
//  AppColors.swift
//  LineWatch
//
//  Created by Steven Nguyen on 3/9/26.
//

import SwiftUI

enum AppColors {
    // Primary greens
    static let primaryGreen = Color(red: 0.13, green: 0.55, blue: 0.13)
    static let darkGreen = Color(red: 0.0, green: 0.35, blue: 0.15)
    static let lightGreen = Color(red: 0.56, green: 0.83, blue: 0.56)

    // Backgrounds
    static let backgroundPrimary = Color(red: 0.08, green: 0.09, blue: 0.11)
    static let backgroundCard = Color(red: 0.14, green: 0.15, blue: 0.18)
    static let backgroundDark = Color(red: 0.12, green: 0.12, blue: 0.14)

    // Text
    static let textPrimary = Color.white
    static let textSecondary = Color(red: 0.63, green: 0.65, blue: 0.70)
    static let textOnGreen = Color.white

    // Odds highlighting
    static let bestOdds = Color(red: 0.13, green: 0.55, blue: 0.13).opacity(0.25)
    static let worstOdds = Color(red: 0.85, green: 0.20, blue: 0.20).opacity(0.25)

    /// Red used for "In Progress" / live indicators. Matches the red base
    /// already used in `worstOdds`.
    static let alertRed = Color(red: 0.85, green: 0.20, blue: 0.20)

    // Utility
    static let divider = Color.white.opacity(0.12)
    static let cardShadow = Color.black.opacity(0.35)
}
