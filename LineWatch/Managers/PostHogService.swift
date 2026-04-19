//
//  PostHogService.swift
//  LineWatch
//
//  Created by Steven Nguyen on 4/18/26.
//

import Foundation
import PostHog

/// Thin wrapper around the PostHog SDK so vendor calls live in one place.
/// Keeps event names and user-property shape consistent across the app.
enum PostHogService {
    /// Boot PostHog at app launch. Called from `LineWatchApp.init()`.
    static func configure() {
        let config = PostHogConfig(
            apiKey: "phc_CWJGqUjc3F5fNdYEtoL5VH98eWtHwQC9Z65Dr4k5Acb3",
            host: "https://us.i.posthog.com"
        )
        // Captures $app_opened / $app_backgrounded automatically.
        config.captureApplicationLifecycleEvents = true
        // We fire our own $screen events with readable names, so disable auto-capture.
        config.captureScreenViews = false
        // Session replay + autocapture stay off — cleaner data, safer on the free tier.
        PostHogSDK.shared.setup(config)
    }

    // MARK: - Identity

    /// Tie subsequent events to a specific user. Called after Supabase auth resolves.
    static func identify(userId: String, email: String?, tier: String) {
        PostHogSDK.shared.identify(
            userId,
            userProperties: [
                "email": email ?? "",
                "subscription_tier": tier
            ]
        )
    }

    /// Forget the current identity. Called on sign-out so the next user isn't attributed
    /// to the previous person.
    static func reset() {
        PostHogSDK.shared.reset()
    }

    // MARK: - Events

    /// Record a `$screen` event. Prefer the `.trackScreen(_:)` view modifier at call sites.
    static func screen(_ name: String, properties: [String: Any] = [:]) {
        PostHogSDK.shared.screen(name, properties: properties)
    }

    /// Record a custom event.
    static func capture(_ event: String, properties: [String: Any] = [:]) {
        PostHogSDK.shared.capture(event, properties: properties)
    }
}
