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
    static let backgroundPrimary = Color(red: 0.96, green: 0.96, blue: 0.96)
    static let backgroundCard = Color.white
    static let backgroundDark = Color(red: 0.12, green: 0.12, blue: 0.14)

    // Text
    static let textPrimary = Color(red: 0.13, green: 0.13, blue: 0.13)
    static let textSecondary = Color(red: 0.55, green: 0.55, blue: 0.55)
    static let textOnGreen = Color.white

    // Odds highlighting
    static let bestOdds = Color(red: 0.13, green: 0.55, blue: 0.13).opacity(0.25)
    static let worstOdds = Color(red: 0.85, green: 0.20, blue: 0.20).opacity(0.25)

    // Utility
    static let divider = Color.gray.opacity(0.3)
    static let cardShadow = Color.black.opacity(0.08)
}
