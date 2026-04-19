//
//  RefreshCountdownButton.swift
//  LineWatch
//
//  Created by Steven Nguyen on 4/19/26.
//

import SwiftUI

/// Clock icon for the top-right toolbar. Tapping opens a popover with a live
/// mm:ss countdown to the next frontend data refresh. The `nextRefreshAt`
/// timestamp lives on `OddsDataService` so every page shows the same value.
struct RefreshCountdownButton: View {
    @Environment(OddsDataService.self) private var dataService
    @State private var showPopover = false

    var body: some View {
        Button {
            showPopover.toggle()
        } label: {
            Image(systemName: "clock")
                .foregroundStyle(AppColors.textSecondary)
        }
        .popover(isPresented: $showPopover) {
            CountdownPopover()
                .environment(dataService)
                .presentationCompactAdaptation(.popover)
        }
    }
}

private struct CountdownPopover: View {
    @Environment(OddsDataService.self) private var dataService

    var body: some View {
        // TimelineView re-renders once per second while the popover is visible —
        // no manual Timer, and zero overhead when the popover is closed.
        TimelineView(.periodic(from: .now, by: 1)) { context in
            VStack(spacing: 6) {
                Text("Next refresh in")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if shouldShowRefreshing(for: context.date) {
                    Text("Refreshing…")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(AppColors.primaryGreen)
                } else {
                    Text(display(for: context.date))
                        .font(.system(size: 28, weight: .semibold, design: .monospaced))
                        .monospacedDigit()
                }
            }
            .padding(20)
        }
    }

    private func display(for now: Date) -> String {
        guard let next = dataService.nextRefreshAt else { return "—" }
        let remaining = max(0, Int(next.timeIntervalSince(now)))
        return String(format: "%d:%02d", remaining / 60, remaining % 60)
    }

    /// True when we should show the "Refreshing…" label instead of a countdown.
    /// Covers both the in-flight fetch (`isRefreshing`) AND the brief gap between
    /// the display ticking to 0:00 and the refresh task flipping `isRefreshing` —
    /// `Task.sleep` wakeup isn't instantaneous, so without this the popover sits
    /// on "0:00" for 3–5s before the label changes. Gated on `nextRefreshAt != nil`
    /// so signed-out / pre-load state still shows "—".
    private func shouldShowRefreshing(for now: Date) -> Bool {
        if dataService.isRefreshing { return true }
        guard let next = dataService.nextRefreshAt else { return false }
        return next.timeIntervalSince(now) <= 0
    }
}
