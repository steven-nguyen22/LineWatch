//
//  OnboardingView.swift
//  LineWatch
//
//  Created by Steven Nguyen on 4/8/26.
//

import SwiftUI

struct OnboardingView: View {
    let onComplete: () -> Void

    @State private var currentPage = 0
    private let totalPages = 6

    var body: some View {
        ZStack {
            AppColors.backgroundPrimary
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Pages
                TabView(selection: $currentPage) {
                    // 1. Welcome
                    OnboardingPage(
                        systemImage: "sportscourt.fill",
                        appImage: "AppLogo",
                        title: "Welcome to LineWatch",
                        description: "Compare odds across all major sportsbooks to find the best lines for every game.",
                        customTitleView: AnyView(
                            HStack(spacing: 0) {
                                Text("Welcome to ")
                                    .font(AppFonts.largeTitle)
                                    .foregroundStyle(AppColors.textPrimary)
                                Text("Line")
                                    .font(AppFonts.largeTitle)
                                    .foregroundStyle(.white)
                                Text("Watch")
                                    .font(AppFonts.largeTitle)
                                    .foregroundStyle(AppColors.primaryGreen)
                            }
                        )
                    )
                    .tag(0)

                    // 2. ML / Spreads / Totals
                    OnboardingPage(
                        systemImage: "chart.bar.fill",
                        title: "Moneyline, Spreads & Totals",
                        description: "View side-by-side odds from every sportsbook. Green highlights show you the best available line."
                    ) {
                        MockOddsCard()
                    }
                    .tag(1)

                    // 3. Player Props
                    OnboardingPage(
                        systemImage: "person.fill",
                        title: "Player Props",
                        description: "Dive into individual player betting markets — points, rebounds, assists, strikeouts and more.",
                        tierBadge: .pro
                    ) {
                        MockPlayerPropCard()
                    }
                    .tag(2)

                    // 4. Best EV
                    OnboardingPage(
                        systemImage: "bolt.fill",
                        title: "Best EV Bets",
                        description: "Instantly find the bets with the highest expected value across all sports and markets.",
                        tierBadge: .hallOfFame
                    ) {
                        MockBestEVCard()
                    }
                    .tag(3)

                    // 5. Team & Player Stats
                    OnboardingPage(
                        systemImage: "chart.line.uptrend.xyaxis",
                        title: "Team & Player Stats",
                        description: "Tap any team or player name to see their season stats — records, averages, and trends.",
                        tierBadge: .hallOfFame
                    ) {
                        MockStatsCard()
                    }
                    .tag(4)

                    // 6. Bet Simulator
                    OnboardingPage(
                        systemImage: "hand.tap.fill",
                        title: "Bet Simulator & Place Bets",
                        description: "Tap any odds to simulate your payout, then go directly to the sportsbook to place your bet."
                    ) {
                        MockBetSimulator()
                    }
                    .tag(5)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .animation(.easeInOut(duration: 0.3), value: currentPage)

                // Bottom section: page dots + button
                VStack(spacing: 20) {
                    // Page indicator dots
                    HStack(spacing: 8) {
                        ForEach(0..<totalPages, id: \.self) { index in
                            Circle()
                                .fill(index == currentPage ? AppColors.primaryGreen : AppColors.textSecondary.opacity(0.3))
                                .frame(width: 8, height: 8)
                                .scaleEffect(index == currentPage ? 1.2 : 1.0)
                                .animation(.easeInOut(duration: 0.2), value: currentPage)
                        }
                    }

                    // Next / Get Started button
                    Button {
                        if currentPage < totalPages - 1 {
                            currentPage += 1
                        } else {
                            onComplete()
                        }
                    } label: {
                        Text(currentPage < totalPages - 1 ? "Next" : "Get Started")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(
                                RoundedRectangle(cornerRadius: 14)
                                    .fill(AppColors.primaryGreen)
                            )
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 24)

                    if currentPage == totalPages - 1 {
                        Text("Start your 7 day Hall of Fame free trial now")
                            .font(AppFonts.body)
                            .foregroundStyle(AppColors.textSecondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 40)
                    }
                }
                .padding(.bottom, 40)
            }
        }
    }
}

#Preview {
    OnboardingView(onComplete: {})
}
