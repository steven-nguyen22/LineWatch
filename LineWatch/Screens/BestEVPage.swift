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

    private var bestBets: [BestEVBet] {
        EVCalculator.findBestEVPerSport(
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

                if bestBets.isEmpty && !isLoadingProps {
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
                    ForEach(bestBets) { bet in
                        BestEVCard(bet: bet, sportLabel: bet.sport.displayName)
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
        .alert("Disclaimer", isPresented: $showDisclaimer) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Sports betting availability varies by state. Not all sportsbooks are available in all states. Please check your local regulations before placing any bets. You must be 21+ to participate in sports betting.")
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
}

#Preview {
    NavigationStack {
        BestEVPage()
            .environment(previewDataService)
    }
}
