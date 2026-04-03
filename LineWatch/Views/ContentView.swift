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
    @Environment(AuthService.self) private var authService

    var body: some View {
        ZStack {
            if isLoading {
                LoadingScreen {
                    withAnimation(.easeInOut(duration: 0.4)) {
                        isLoading = false
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
                            case .eventDetail(let event, let marketType):
                                BetPage(event: event, marketType: marketType)
                            }
                        }
                }
                .environment(dataService)
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.4), value: isLoading)
        .animation(.easeInOut(duration: 0.4), value: authService.isAuthenticated)
        .onAppear {
            dataService.loadLocalData()
        }
        .task {
            async let odds: () = dataService.fetchAndCacheAll()
            async let assets: () = dataService.fetchNBAAssets()
            _ = await (odds, assets)
        }
    }
}

#Preview {
    ContentView()
        .environment(AuthService())
}
