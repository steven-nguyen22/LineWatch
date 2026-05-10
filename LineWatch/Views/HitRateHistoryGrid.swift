//
//  HitRateHistoryGrid.swift
//  LineWatch
//
//  Reusable 2×2 grid showing Last 5 / Last 10 / Last 15 hit fractions and a
//  flame/snowflake streak box. Driven entirely by `[Row]?` and a
//  `KeyPath<Row, Bool>` so the same view works for any model with a boolean
//  outcome field — currently:
//
//    PlayerStatsModal:  HitRateHistoryGrid(title: "Points History",
//                                           rows: hitRateRows,
//                                           predicate: \.hit)
//
//    TeamStatsModal:    HitRateHistoryGrid(title: "Wins History",
//                                           rows: teamRows,
//                                           predicate: \.won)
//                       HitRateHistoryGrid(title: "Spreads History",
//                                           rows: teamRows,
//                                           predicate: \.covered)
//
//  `nil` rows  → loading state ("···"), `[]` → fetched-but-empty ("—"),
//  populated  → real fractions + streak.
//

import SwiftUI

struct HitRateHistoryGrid<Row>: View {
    let title: String
    let rows: [Row]?
    let predicate: KeyPath<Row, Bool>

    var body: some View {
        VStack(spacing: 12) {
            Text(title)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(AppColors.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.top, 24)

            VStack(spacing: 12) {
                HStack(spacing: 12) {
                    historyBox(label: "Last 5 Games",  value: fractionText(window: 5))
                    historyBox(label: "Last 10 Games", value: fractionText(window: 10))
                }
                HStack(spacing: 12) {
                    historyBox(label: "Last 15 Games", value: fractionText(window: 15))
                    streakHistoryBox
                }
            }
            .padding(.horizontal, 16)
        }
    }

    // MARK: - Boxes

    private func historyBox(label: String, value: String) -> some View {
        VStack(spacing: 6) {
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(AppColors.textSecondary)
            Text(value)
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundStyle(AppColors.textPrimary)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
        .background(AppColors.backgroundCard)
        .cornerRadius(12)
    }

    /// Streak box uses SF Symbols (flame.fill / snowflake) instead of emoji
    /// so the icon renders as a color glyph regardless of surrounding font.
    private var streakHistoryBox: some View {
        VStack(spacing: 6) {
            Text("Streak")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(AppColors.textSecondary)
            Group {
                if let rows = rows {
                    if rows.isEmpty {
                        Text("—")
                            .font(.system(size: 24, weight: .bold, design: .rounded))
                            .foregroundStyle(AppColors.textPrimary)
                    } else {
                        let parts = streakParts(from: rows)
                        HStack(spacing: 5) {
                            Image(systemName: parts.symbol)
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundStyle(parts.color)
                            Text("\(parts.count)")
                                .font(.system(size: 24, weight: .bold, design: .rounded))
                                .foregroundStyle(AppColors.textPrimary)
                                .monospacedDigit()
                        }
                    }
                } else {
                    Text("···")
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundStyle(AppColors.textPrimary)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
        .background(AppColors.backgroundCard)
        .cornerRadius(12)
    }

    // MARK: - Computation

    /// "x/N" with N capped at the window size. Sparse data is kept honest:
    /// a player/team with 7 graded games shows L10 and L15 as `x/7`, while
    /// L5 caps at `x/5`. Loading shows "···", empty shows "—".
    private func fractionText(window: Int) -> String {
        guard let rows = rows else { return "···" }
        if rows.isEmpty { return "—" }
        let slice = rows.prefix(window)
        let hits = slice.filter { $0[keyPath: predicate] }.count
        return "\(hits)/\(slice.count)"
    }

    /// Walks rows in date-descending order from the most-recent game and
    /// counts consecutive games sharing the same boolean as the most-recent.
    /// Hot streak → flame.fill (orange); cold streak → snowflake (cyan).
    private func streakParts(from rows: [Row]) -> StreakParts {
        guard let first = rows.first else {
            return StreakParts(symbol: "minus", color: AppColors.textSecondary, count: 0)
        }
        let firstHit = first[keyPath: predicate]
        var count = 0
        for row in rows {
            if row[keyPath: predicate] == firstHit { count += 1 } else { break }
        }
        return firstHit
            ? StreakParts(symbol: "flame.fill", color: .orange, count: count)
            : StreakParts(symbol: "snowflake",  color: .cyan,   count: count)
    }

    private struct StreakParts {
        let symbol: String
        let color: Color
        let count: Int
    }
}
