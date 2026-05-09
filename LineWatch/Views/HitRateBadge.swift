//
//  HitRateBadge.swift
//  LineWatch
//
//  Small "X of last 5" preview badge that renders next to a player's name
//  on the player props rows. Tapping the badge invokes the caller-provided
//  `onTap` closure — typically used to open the PlayerStatsModal so the
//  user gets the full L5/L10/L15 + streak deep-dive.
//
//  The badge is rendered behind both `Features.hitRatesEnabled` (kill
//  switch) and `authService.effectiveTier.canAccessHitRates` (Hall of
//  Fame tier gate). Loading / no-data states render as a neutral "—"
//  so the row layout doesn't shift around.
//

import SwiftUI

struct HitRateBadge: View {
    let playerName: String
    let propType: PlayerPropType
    let sportKey: String
    let onTap: () -> Void

    @State private var rows: [HitRateRow]?

    /// The badge always previews the L5 hit rate. The deeper L10/L15/streak
    /// breakdown lives in the stats modal, opened on tap.
    private static let previewWindow = 5
    private static let supabase = SupabaseService()

    var body: some View {
        Button(action: onTap) {
            content
        }
        .buttonStyle(.plain)
        .task(id: playerName) {
            await load()
        }
    }

    @ViewBuilder
    private var content: some View {
        if let rows = rows {
            let summary = summarize(rows: rows, window: Self.previewWindow)
            if summary.hasData {
                badge(text: "\(summary.hits) of \(summary.total)", tint: tint(for: summary))
            } else {
                badge(text: "—", tint: AppColors.textSecondary.opacity(0.6))
            }
        } else {
            // Reserve space while loading so the row doesn't jump.
            badge(text: "···", tint: AppColors.textSecondary.opacity(0.4))
        }
    }

    private func badge(text: String, tint: Color) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .foregroundStyle(.white)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Capsule().fill(tint))
    }

    private func summarize(rows: [HitRateRow], window: Int) -> HitRateSummary {
        let slice = Array(rows.prefix(window))
        let hits = slice.reduce(0) { $0 + ($1.hit ? 1 : 0) }
        return HitRateSummary(hits: hits, total: slice.count, lastN: window)
    }

    /// Color the badge by streak strength.
    /// Green ≥60% hit rate, gray 40-60%, red <40%.
    private func tint(for summary: HitRateSummary) -> Color {
        guard let rate = summary.rate else { return AppColors.textSecondary.opacity(0.6) }
        if rate >= 0.6 { return AppColors.primaryGreen }
        if rate < 0.4 { return AppColors.alertRed }
        return AppColors.textSecondary.opacity(0.7)
    }

    private func load() async {
        // Pass through any error as "no data" — the hit-rate feature is
        // strictly additive, so a fetch failure should never block the
        // surrounding prop row from rendering.
        do {
            let fetched = try await Self.supabase.fetchHitRateRows(
                playerName: playerName,
                sportKey: sportKey,
                propType: propType.marketKey
            )
            rows = fetched
        } catch {
            rows = []
        }
    }
}
