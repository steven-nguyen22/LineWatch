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

        // Session replay (mobile). Free tier = 2,500 mobile recordings/month;
        // a $0 billing limit on Mobile Session Replay in the PostHog dashboard
        // guarantees we never leave the free tier.
        config.sessionReplay = true
        // REQUIRED for SwiftUI — without screenshot mode, replays render blank.
        config.sessionReplayConfig.screenshotMode = true
        // Mask all text inputs (email/password fields, search box). Passwords are
        // always masked regardless. PII in SecureField/TextField never leaves the device.
        config.sessionReplayConfig.maskAllTextInputs = true
        // Team logos / player headshots are public, not PII — keep them visible so
        // replays are actually useful for spotting where users get stuck.
        config.sessionReplayConfig.maskAllImages = false
        // Autocapture stays off; our explicit $screen + custom events are unchanged
        // and replays attach to them automatically.

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
