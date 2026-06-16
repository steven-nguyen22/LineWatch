//
//  RankMedal.swift
//  LineWatch
//
//  A small reusable gold / silver / bronze rank medal. Used by the Hot Streaks
//  rows, the Best EV cards, and the onboarding preview so the 1st / 2nd / 3rd
//  medal styling lives in exactly one place.
//

import SwiftUI

struct RankMedal: View {
    let rank: Int
    var size: CGFloat = 28

    var body: some View {
        Image(systemName: "medal.fill")
            .font(.system(size: size))
            .foregroundStyle(Self.color(for: rank))
    }

    /// Gold / silver / bronze for ranks 1 / 2 / 3. Anything beyond falls back
    /// to muted gray (pages only ever render the top 3).
    static func color(for rank: Int) -> Color {
        switch rank {
        case 1: return Color(red: 1.0, green: 0.84, blue: 0.0)    // gold
        case 2: return Color(white: 0.75)                          // silver
        case 3: return Color(red: 0.80, green: 0.50, blue: 0.20)   // bronze
        default: return AppColors.textSecondary
        }
    }
}
