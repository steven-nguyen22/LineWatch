//
//  PurchaseManager.swift
//  LineWatch
//
//  Created by Steven Nguyen on 4/18/26.
//

import Foundation
import RevenueCat

/// Product identifiers — must match the ones configured in App Store Connect + RevenueCat.
enum ProductID {
    static let proMonthly = "pro_monthly"
    static let proAnnual = "pro_annual"
    static let hofMonthly = "hof_monthly"
    static let hofAnnual = "hof_annual"
}

/// RevenueCat entitlement identifiers — must match the ones configured in the RC dashboard.
enum EntitlementID {
    static let pro = "pro"
    static let hallOfFame = "hall_of_fame"
}

@Observable
final class PurchaseManager {
    var currentOffering: Offering?
    var isLoading: Bool = false

    /// Fetch the default offering from RevenueCat so the paywall can show live prices.
    /// Idempotent — safe to call multiple times.
    func loadOffering() async {
        do {
            let offerings = try await Purchases.shared.offerings()
            await MainActor.run {
                self.currentOffering = offerings.current
            }
        } catch {
            // Silent — paywall will fall back to hardcoded labels
        }
    }

    /// Trigger the StoreKit purchase sheet for a specific package.
    /// Returns the derived tier on success, or throws on non-cancel errors.
    func purchase(package: Package) async throws -> SubscriptionTier {
        await MainActor.run { self.isLoading = true }
        defer { Task { @MainActor in self.isLoading = false } }

        let result = try await Purchases.shared.purchase(package: package)
        if result.userCancelled {
            // Raise a sentinel error the caller can swallow silently.
            throw PurchaseError.cancelled
        }
        return tier(from: result.customerInfo)
    }

    /// Restore previous purchases for this Apple ID.
    func restorePurchases() async throws -> SubscriptionTier {
        await MainActor.run { self.isLoading = true }
        defer { Task { @MainActor in self.isLoading = false } }

        let info = try await Purchases.shared.restorePurchases()
        return tier(from: info)
    }

    /// Map RevenueCat's active entitlements to our internal SubscriptionTier.
    /// Hall of Fame wins over Pro when both are somehow active.
    func tier(from info: CustomerInfo) -> SubscriptionTier {
        let active = info.entitlements.active
        if active[EntitlementID.hallOfFame] != nil {
            return .hallOfFame
        }
        if active[EntitlementID.pro] != nil {
            return .pro
        }
        return .rookie
    }

    /// Look up the Package matching a tier + billing period from the current offering.
    func package(for tier: SubscriptionTier, billing: BillingPeriod) -> Package? {
        guard let offering = currentOffering else { return nil }
        let productId = productIdentifier(tier: tier, billing: billing)
        return offering.availablePackages.first {
            $0.storeProduct.productIdentifier == productId
        }
    }

    /// Localized price string for a tier + billing period, or nil if the offering isn't loaded.
    func localizedPrice(for tier: SubscriptionTier, billing: BillingPeriod) -> String? {
        package(for: tier, billing: billing)?.storeProduct.localizedPriceString
    }

    private func productIdentifier(tier: SubscriptionTier, billing: BillingPeriod) -> String? {
        switch (tier, billing) {
        case (.pro, .monthly): return ProductID.proMonthly
        case (.pro, .annual): return ProductID.proAnnual
        case (.hallOfFame, .monthly): return ProductID.hofMonthly
        case (.hallOfFame, .annual): return ProductID.hofAnnual
        case (.rookie, _): return nil
        }
    }
}

/// Billing period selector shared between PaywallView and PurchaseManager.
enum BillingPeriod: String, CaseIterable {
    case monthly
    case annual

    var displayName: String {
        switch self {
        case .monthly: return "Monthly"
        case .annual: return "Annual"
        }
    }
}

enum PurchaseError: Error {
    case cancelled
    case packageNotFound
}
