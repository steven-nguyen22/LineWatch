//
//  ContentView.swift
//  LineWatch
//
//  Created by Steven Nguyen on 11/10/24.
//

import SwiftUI

struct ContentView: View {
    @State private var isLoading = true
    @State private var dataService = OddsDataService()
    @State private var purchaseManager = PurchaseManager()
    @AppStorage("hasSeenOnboarding") private var hasSeenOnboarding = false
    @Environment(AuthService.self) private var authService
    @Environment(\.scenePhase) private var scenePhase

    private let backgroundRefreshInterval: UInt64 = 5 * 60 * 1_000_000_000 // 5 min in nanoseconds

    /// Changes whenever a condition that should start/stop the refresh loop flips.
    /// Using a combined id means the task restarts as soon as loading finishes or
    /// the user signs in — not only when scenePhase changes.
    private var refreshTaskId: String {
        "\(scenePhase)-\(isLoading)-\(authService.isAuthenticated)"
    }

    var body: some View {
        ZStack {
            if isLoading {
                LoadingScreen {
                    withAnimation(.easeInOut(duration: 0.4)) {
                        isLoading = false
                    }
                }
                .transition(.opacity)
            } else if !hasSeenOnboarding {
                OnboardingView {
                    withAnimation(.easeInOut(duration: 0.4)) {
                        hasSeenOnboarding = true
                    }
                }
                .transition(.opacity)
            } else if !authService.isAuthenticated {
                SignInView()
                    .transition(.opacity)
            } else {
                NavigationStack {
                    LandingPage()
                        .navigationDestination(for: AppRoute.self) { route in
                            switch route {
                            case .sportEvents(let sport):
                                SubPage(sport: sport)
                            case .eventDetail(let event, let marketType, let prefillSearch):
                                BetPage(event: event, marketType: marketType, initialGolfSearch: prefillSearch ?? "")
                            case .bestEV:
                                if authService.effectiveTier.canAccessBestEV {
                                    BestEVPage()
                                } else {
                                    PaywallView()
                                }
                            case .paywall:
                                PaywallView()
                            }
                        }
                }
                .environment(dataService)
                .transition(.opacity)
            }
        }
        .environment(purchaseManager)
        .animation(.easeInOut(duration: 0.4), value: isLoading)
        .animation(.easeInOut(duration: 0.4), value: hasSeenOnboarding)
        .animation(.easeInOut(duration: 0.4), value: authService.isAuthenticated)
        .fullScreenCover(isPresented: Binding(
            get: { authService.needsPostTrialPaywall },
            set: { _ in }
        )) {
            NavigationStack {
                PaywallView(presentationContext: .postTrial)
            }
            .environment(purchaseManager)
            .environment(authService)
        }
        .onAppear {
            dataService.loadLocalData()
        }
        .task {
            await purchaseManager.loadOffering()
            async let odds: () = dataService.fetchAndCacheAll()
            async let nbaAssets: () = dataService.fetchNBAAssets()
            async let mlbAssets: () = dataService.fetchMLBAssets()
            async let nhlAssets: () = dataService.fetchNHLAssets()
            async let nflAssets: () = dataService.fetchNFLAssets()
            async let fightingAssets: () = dataService.fetchFightingAssets()
            async let soccerAssets: () = dataService.fetchSoccerAssets()
            async let golfAssets: () = dataService.fetchGolfAssets()
            _ = await (odds, nbaAssets, mlbAssets, nhlAssets, nflAssets, fightingAssets, soccerAssets, golfAssets)

            // Prefetch team & player stats for supported sports (sequential to avoid
            // data race on statsFetchedForSports — each call is a quick Supabase read)
            for sport in OddsDataService.statsSports {
                await dataService.fetchStats(for: sport)
            }
        }
        .task(id: refreshTaskId) {
            // Auto-refresh odds + opened player props every 5 minutes while foregrounded.
            // refreshTaskId includes scenePhase + isLoading + isAuthenticated, so this task
            // restarts the moment loading finishes — not only on background/foreground.
            guard scenePhase == .active, !isLoading, authService.isAuthenticated else { return }

            // Advertise the first refresh 5 min out so the countdown popover can render
            // immediately. Cleared in defer when the task is cancelled (background, sign-out).
            dataService.nextRefreshAt = Date().addingTimeInterval(5 * 60)
            defer { dataService.nextRefreshAt = nil }

            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: backgroundRefreshInterval)
                if Task.isCancelled { break }
                await dataService.fetchAndCacheAll()
                await dataService.refreshCachedPlayerProps()
                dataService.nextRefreshAt = Date().addingTimeInterval(5 * 60)
            }
        }
    }
}

#Preview {
    ContentView()
        .environment(AuthService())
}
