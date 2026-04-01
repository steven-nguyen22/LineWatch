//
//  LineWatchApp.swift
//  LineWatch
//
//  Created by Steven Nguyen on 11/10/24.
//

import SwiftUI
import GoogleSignIn

@main
struct LineWatchApp: App {
    @State private var authService = AuthService()

    init() {
        // Configure Google Sign-In with both iOS + Web client IDs
        // The serverClientID ensures the id_token audience matches what Supabase expects
        GIDSignIn.sharedInstance.configuration = GIDConfiguration(
            clientID: "1090657770332-0avaak35vossmkpg8hqjkro33g0kjr6q.apps.googleusercontent.com",
            serverClientID: "1090657770332-8gdieq700jrlfgb6j5g8koc068hnncmd.apps.googleusercontent.com"
        )
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(authService)
                .onOpenURL { url in
                    GIDSignIn.sharedInstance.handle(url)
                }
                .task {
                    await authService.restoreSession()
                }
        }
    }
}
