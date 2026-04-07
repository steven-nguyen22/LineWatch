//
//  TeamStatsModal.swift
//  LineWatch
//
//  Created by Steven Nguyen on 4/7/26.
//

import SwiftUI
import NukeUI

struct TeamStatsModal: View {
    let teamName: String
    let sport: SportCategory
    @Environment(OddsDataService.self) private var dataService

    private var stats: [String: String] {
        dataService.teamStatsByName[teamName] ?? [:]
    }

    /// Sport-specific stat display order
    private var statKeys: [String] {
        switch sport {
        case .basketball:
            return ["Record", "Home", "Road", "L10", "Streak", "Pt Diff"]
        case .baseball:
            return ["Record", "Home", "Road", "L10", "Streak", "RS", "RA"]
        case .hockey:
            return ["Record", "Home", "Road", "L10", "Points", "GF", "GA"]
        case .football:
            return ["Record", "Home", "Road", "Div", "PF", "PA", "Streak"]
        default:
            return Array(stats.keys.sorted())
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Drag indicator
            Capsule()
                .fill(Color.gray.opacity(0.4))
                .frame(width: 36, height: 5)
                .padding(.top, 10)

            // Team logo + name
            VStack(spacing: 10) {
                if let logoURL = dataService.teamLogoURLs[teamName],
                   let url = URL(string: logoURL) {
                    LazyImage(url: url) { state in
                        if let image = state.image {
                            image.resizable().scaledToFit()
                        }
                    }
                    .frame(width: 72, height: 72)
                } else {
                    Image(systemName: sport.iconName)
                        .font(.system(size: 40))
                        .foregroundStyle(AppColors.primaryGreen)
                        .frame(width: 72, height: 72)
                }

                Text(teamName)
                    .font(AppFonts.title)
                    .foregroundStyle(AppColors.textPrimary)
                    .multilineTextAlignment(.center)

                Text("\(sport.displayName) \u{2022} Team Stats")
                    .font(AppFonts.caption)
                    .foregroundStyle(AppColors.textSecondary)
            }
            .padding(.top, 16)
            .padding(.bottom, 20)

            // Stats rows
            if stats.isEmpty {
                Spacer()
                Text("Stats unavailable")
                    .font(AppFonts.body)
                    .foregroundStyle(AppColors.textSecondary)
                Spacer()
            } else {
                VStack(spacing: 0) {
                    ForEach(statKeys, id: \.self) { key in
                        if let value = stats[key] {
                            HStack {
                                Text(key)
                                    .font(AppFonts.body)
                                    .foregroundStyle(AppColors.textSecondary)
                                Spacer()
                                Text(value)
                                    .font(.system(size: 15, weight: .semibold, design: .monospaced))
                                    .foregroundStyle(AppColors.textPrimary)
                            }
                            .padding(.horizontal, 24)
                            .padding(.vertical, 10)

                            if key != statKeys.last {
                                Divider()
                                    .padding(.horizontal, 24)
                            }
                        }
                    }
                }
                .background(AppColors.backgroundCard)
                .cornerRadius(12)
                .padding(.horizontal, 16)
            }

            Spacer()
        }
        .background(AppColors.backgroundPrimary)
        .presentationDetents([.medium])
        .presentationDragIndicator(.hidden)
    }
}
