//
//  TrackScreen.swift
//  LineWatch
//
//  Created by Steven Nguyen on 4/18/26.
//

import SwiftUI

private struct TrackScreenModifier: ViewModifier {
    let name: String
    let properties: [String: Any]

    func body(content: Content) -> some View {
        content.onAppear {
            PostHogService.screen(name, properties: properties)
        }
    }
}

extension View {
    /// Fires a PostHog `$screen` event each time this view appears.
    /// PostHog derives time-on-screen from the interval between consecutive
    /// `$screen` / `$app_backgrounded` events — no manual timing required.
    func trackScreen(_ name: String, properties: [String: Any] = [:]) -> some View {
        modifier(TrackScreenModifier(name: name, properties: properties))
    }
}
