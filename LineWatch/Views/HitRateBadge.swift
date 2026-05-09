//
//  HitRateBadge.swift
//  LineWatch
//
//  Small "X of last N" badge that renders next to a player's name on the
//  player props rows. Tapping the badge cycles the window through L5, L10,
//  and L15 so users can see how the trend looks at different timescales.
//
//  The badge is rendered behind both `Features.hitRatesEnabled` (kill
//  switch) and `authService.effectiveTier.canAccessHitRates` (tier gate).
//  Loading / no-data states render as a neutral "—" so the row layout
//  doesn't shift around.
//

import SwiftUI

struct HitRateBadge: View {
    let playerName: String
    let propType: PlayerPropType
    let sportKey: String

    @State private var rows: [HitRateRow]?
    @State private var lastN: Int = 5

    private static let availableWindows = [5, 10, 15]
    private static let supabase = SupabaseService()

    var body: some View {
        Button {
            cycleWindow()
        } label: {
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
            let summary = summarize(rows: rows, window: lastN)
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

    /// Slice the cached 15-row response down to the requested window.
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

    private func cycleWindow() {
        guard let idx = Self.availableWindows.firstIndex(of: lastN) else {
            lastN = Self.availableWindows[0]
            return
        }
        lastN = Self.availableWindows[(idx + 1) % Self.availableWindows.count]
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
