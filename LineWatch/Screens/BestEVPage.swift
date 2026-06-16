//
//  BestEVPage.swift
//  LineWatch
//
//  Created by Steven Nguyen on 4/6/26.
//

import SwiftUI

struct BestEVPage: View {
    @Environment(OddsDataService.self) private var dataService
    @State private var showDisclaimer = false
    @State private var isLoadingProps = false
    @State private var hasLoadedProps = false

    /// Top 3 EV bets per in-season sport, grouped for section rendering.
    private var topBySport: [(sport: SportCategory, bets: [BestEVBet])] {
        EVCalculator.findTopEVPerSport(
            eventsBySport: dataService.eventsBySport,
            playerPropsByEvent: dataService.playerPropsByEvent
        )
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if isLoadingProps {
                    VStack(spacing: 12) {
                        ProgressView()
                            .scaleEffect(1.2)
                        Text("Scanning all markets for value...")
                            .font(AppFonts.caption)
                            .foregroundStyle(AppColors.textSecondary)
                    }
                    .padding(.top, 40)
                }

                if topBySport.isEmpty && !isLoadingProps {
                    // Empty state
                    VStack(spacing: 16) {
                        Image(systemName: "chart.line.downtrend.xyaxis")
                            .font(.system(size: 48))
                            .foregroundStyle(AppColors.textSecondary.opacity(0.5))

                        Text("No value bets available")
                            .font(AppFonts.title)
                            .foregroundStyle(AppColors.textSecondary)

                        Text("No positive EV opportunities found right now. Check back later as odds shift throughout the day.")
                            .font(AppFonts.body)
                            .foregroundStyle(AppColors.textSecondary.opacity(0.7))
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, 80)
                    .padding(.horizontal, 40)
                } else {
                    ForEach(topBySport, id: \.sport) { entry in
                        sportSection(sport: entry.sport, bets: entry.bets)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
        }
        .background(AppColors.backgroundPrimary)
        .navigationTitle("Best Value Bets")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                RefreshCountdownButton()
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showDisclaimer = true
                } label: {
                    Image(systemName: "info.circle")
                        .foregroundStyle(AppColors.textSecondary)
                }
            }
        }
        .fullScreenCover(isPresented: $showDisclaimer) {
            DisclaimerCardView()
        }
        .task {
            if !hasLoadedProps {
                isLoadingProps = true
                await dataService.prefetchAllPlayerProps()
                isLoadingProps = false
                hasLoadedProps = true
            }
        }
        .trackScreen("best_ev")
    }

    // MARK: - Sections

    /// A per-sport section: header (icon + name) followed by up to 3 ranked
    /// Best EV cards. Mirrors HotStreaksPage.sportSection for visual parity.
    @ViewBuilder
    private func sportSection(sport: SportCategory, bets: [BestEVBet]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: sport.iconName)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(AppColors.primaryGreen)

                Text(sport.displayName)
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(AppColors.textPrimary)
            }
            .padding(.leading, 4)

            VStack(spacing: 12) {
                ForEach(Array(bets.enumerated()), id: \.element.id) { idx, bet in
                    BestEVCard(bet: bet, sportLabel: nil, rank: idx + 1)
                }
            }
        }
    }
}

#if DEBUG
#Preview {
    NavigationStack {
        BestEVPage()
            .environment(previewDataService)
    }
}
#endif
