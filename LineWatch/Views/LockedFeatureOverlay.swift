//
//  LockedFeatureOverlay.swift
//  LineWatch
//
//  Created by Steven Nguyen on 4/8/26.
//

import SwiftUI

/// A view modifier that overlays a lock icon and "Upgrade" prompt on locked content.
/// The child content is shown at reduced opacity with a semi-transparent overlay.
struct LockedFeatureOverlay: ViewModifier {
    let isLocked: Bool
    let requiredTier: SubscriptionTier
    let onUpgradeTap: () -> Void

    func body(content: Content) -> some View {
        if isLocked {
            content
                .opacity(0.35)
                .overlay {
                    Button(action: onUpgradeTap) {
                        VStack(spacing: 6) {
                            Image(systemName: "lock.fill")
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundStyle(AppColors.textSecondary)

                            Text(requiredTier.displayName)
                                .font(.system(size: 13, weight: .bold, design: .rounded))
                                .foregroundStyle(AppColors.textPrimary)

                            Text("Upgrade")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(AppColors.primaryGreen)
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(AppColors.backgroundCard.opacity(0.9))
                                .shadow(color: AppColors.cardShadow, radius: 4, x: 0, y: 2)
                        )
                    }
                    .buttonStyle(.plain)
                }
                .allowsHitTesting(true)
        } else {
            content
        }
    }
}

extension View {
    /// Apply a lock overlay when the feature requires a higher subscription tier.
    func lockedFeature(
        isLocked: Bool,
        requiredTier: SubscriptionTier,
        onUpgradeTap: @escaping () -> Void
    ) -> some View {
        modifier(LockedFeatureOverlay(
            isLocked: isLocked,
            requiredTier: requiredTier,
            onUpgradeTap: onUpgradeTap
        ))
    }
}
