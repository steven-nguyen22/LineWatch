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
                            case .eventDetail(let event, let marketType, let prefillSearch, let initialProp):
                                BetPage(
                                    event: event,
                                    marketType: marketType,
                                    initialGolfSearch: prefillSearch ?? "",
                                    initialPlayerPropType: initialProp
                                )
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

            // First run only — on subsequent foregrounds we resume the existing schedule
            // so the countdown continues from where it left off instead of resetting.
            if dataService.nextRefreshAt == nil {
                dataService.nextRefreshAt = Date().addingTimeInterval(5 * 60)
            }

            while !Task.isCancelled {
                // Sleep until the scheduled refresh. If we're already past it (app was
                // backgrounded through the window), this is a no-op and we fetch immediately.
                if let next = dataService.nextRefreshAt {
                    let remaining = next.timeIntervalSinceNow
                    if remaining > 0 {
                        try? await Task.sleep(nanoseconds: UInt64(remaining * 1_000_000_000))
                    }
                }
                if Task.isCancelled { break }

                // Advance BEFORE the fetch so the countdown visibly rolls over to 5:00
                // the moment this cycle begins — no stuck 0:00 while the network call runs.
                dataService.nextRefreshAt = Date().addingTimeInterval(5 * 60)
                dataService.isRefreshing = true
                await dataService.fetchAndCacheAll()
                await dataService.refreshCachedPlayerProps()
                dataService.lastRefreshAt = Date()
                dataService.isRefreshing = false
            }
        }
        .onChange(of: authService.isAuthenticated) { _, isAuthed in
            // Sign-out should clear the countdown so a fresh sign-in starts clean.
            if !isAuthed {
                dataService.nextRefreshAt = nil
                dataService.lastRefreshAt = nil
                dataService.isRefreshing = false
            }
        }
    }
}

#Preview {
    ContentView()
        .environment(AuthService())
}
