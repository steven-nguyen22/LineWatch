//
//  SubscriptionTier.swift
//  LineWatch
//
//  Created by Steven Nguyen on 4/8/26.
//

import Foundation

enum SubscriptionTier: String, Codable, CaseIterable, Comparable {
    case rookie = "rookie"
    case pro = "pro"
    case hallOfFame = "hall_of_fame"

    // MARK: - Display

    var displayName: String {
        switch self {
        case .rookie: return "Rookie"
        case .pro: return "Pro"
        case .hallOfFame: return "Hall of Fame"
        }
    }

    var monthlyPrice: Decimal? {
        switch self {
        case .rookie: return nil
        case .pro: return 5
        case .hallOfFame: return 10
        }
    }

    var annualPrice: Decimal? {
        switch self {
        case .rookie: return nil
        case .pro: return 40
        case .hallOfFame: return 80
        }
    }

    var monthlyPriceLabel: String {
        switch self {
        case .rookie: return "Free"
        case .pro: return "$4.99/mo"
        case .hallOfFame: return "$9.99/mo"
        }
    }

    var annualPriceLabel: String {
        switch self {
        case .rookie: return "Free"
        case .pro: return "$39.99/yr"
        case .hallOfFame: return "$79.99/yr"
        }
    }

    var annualSavingsPercent: Int? {
        switch self {
        case .rookie: return nil
        case .pro: return 33
        case .hallOfFame: return 33
        }
    }

    // MARK: - Feature Access

    var canAccessPlayerProps: Bool { self >= .pro }
    var canAccessBestEV: Bool { self >= .hallOfFame }
    var canAccessStats: Bool { self >= .hallOfFame }

    // MARK: - Comparable (rookie < pro < hallOfFame)

    private var ordinal: Int {
        switch self {
        case .rookie: return 0
        case .pro: return 1
        case .hallOfFame: return 2
        }
    }

    static func < (lhs: SubscriptionTier, rhs: SubscriptionTier) -> Bool {
        lhs.ordinal < rhs.ordinal
    }
}
