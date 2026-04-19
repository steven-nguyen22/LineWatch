//
//  InProgressBadge.swift
//  LineWatch
//
//  Created by Steven Nguyen on 4/19/26.
//

import SwiftUI

/// Red, gently-pulsing "In Progress" pill rendered wherever a live game's
/// header is shown. Matches the visual rhythm of the green sport-title pill
/// (capsule, .caption .semibold, 12×4 padding) — just red + blinking.
///
/// The pulse fades opacity 1.0 ↔ 0.45 over 1.5s with ease-in-out so it never
/// fully disappears and text stays readable at the dimmest point.
struct InProgressBadge: View {
    @State private var isPulsing = false

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "exclamationmark.circle.fill")
                .font(.system(size: 11, weight: .semibold))
            Text("In Progress")
                .font(AppFonts.caption)
                .fontWeight(.semibold)
        }
        .foregroundStyle(AppColors.alertRed)
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .background(
            Capsule().fill(AppColors.alertRed.opacity(0.15))
        )
        .opacity(isPulsing ? 0.45 : 1.0)
        .onAppear {
            withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                isPulsing = true
            }
        }
    }
}
