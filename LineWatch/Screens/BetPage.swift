//
//  BetPage.swift
//  LineWatch
//
//  Created by Steven Nguyen on 3/9/26.
//

import SwiftUI

struct BetPage: View {
    let event: ResponseBody

    var body: some View {
        let bookmakers = event.bookmakers
        let awayPrices = bookmakers.compactMap { $0.markets.first?.outcomes.first?.price }
        let homePrices = bookmakers.compactMap { $0.markets.first?.outcomes.last?.price }

        ScrollView {
            VStack(spacing: 0) {
                // Header
                VStack(spacing: 8) {
                    Text(event.sportTitle)
                        .font(AppFonts.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(AppColors.primaryGreen)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 4)
                        .background(
                            Capsule()
                                .fill(AppColors.primaryGreen.opacity(0.12))
                        )

                    Text("\(event.awayTeam)")
                        .font(AppFonts.title)
                        .foregroundStyle(AppColors.textPrimary)

                    Text("@")
                        .font(AppFonts.body)
                        .foregroundStyle(AppColors.textSecondary)

                    Text("\(event.homeTeam)")
                        .font(AppFonts.title)
                        .foregroundStyle(AppColors.textPrimary)

                    if let time = event.commenceTime {
                        Text(formatGameTime(time))
                            .font(AppFonts.caption)
                            .foregroundStyle(AppColors.textSecondary)
                    }
                }
                .padding(.vertical, 20)
                .frame(maxWidth: .infinity)
                .background(AppColors.backgroundCard)

                // Column Headers
                HStack(spacing: 0) {
                    Text("Sportsbook")
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Text(shortenTeamName(event.awayTeam))
                        .frame(width: 80, alignment: .center)

                    Text(shortenTeamName(event.homeTeam))
                        .frame(width: 80, alignment: .center)
                }
                .font(AppFonts.caption)
                .fontWeight(.semibold)
                .foregroundStyle(AppColors.textSecondary)
                .textCase(.uppercase)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(AppColors.backgroundPrimary)

                // Sportsbook Rows
                LazyVStack(spacing: 0) {
                    ForEach(Array(bookmakers.enumerated()), id: \.offset) { index, bookmaker in
                        let awayOdds = bookmaker.markets.first?.outcomes.first?.price
                        let homeOdds = bookmaker.markets.first?.outcomes.last?.price

                        HStack(spacing: 0) {
                            Text(bookmaker.title)
                                .font(AppFonts.body)
                                .foregroundStyle(AppColors.textPrimary)
                                .frame(maxWidth: .infinity, alignment: .leading)

                            Text(formatOdds(awayOdds))
                                .font(AppFonts.odds)
                                .foregroundStyle(AppColors.textPrimary)
                                .frame(width: 80, height: 36, alignment: .center)
                                .background(
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(oddsBackground(price: awayOdds, allPrices: awayPrices))
                                )

                            Text(formatOdds(homeOdds))
                                .font(AppFonts.odds)
                                .foregroundStyle(AppColors.textPrimary)
                                .frame(width: 80, height: 36, alignment: .center)
                                .background(
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(oddsBackground(price: homeOdds, allPrices: homePrices))
                                )
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(index % 2 == 0 ? AppColors.backgroundCard : AppColors.backgroundPrimary.opacity(0.5))

                        if index < bookmakers.count - 1 {
                            Divider()
                                .foregroundStyle(AppColors.divider)
                                .padding(.horizontal, 16)
                        }
                    }
                }

                // Legend
                HStack(spacing: 20) {
                    HStack(spacing: 6) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(AppColors.bestOdds)
                            .frame(width: 14, height: 14)
                        Text("Best Odds")
                            .font(AppFonts.caption)
                            .foregroundStyle(AppColors.textSecondary)
                    }

                    HStack(spacing: 6) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(AppColors.worstOdds)
                            .frame(width: 14, height: 14)
                        Text("Worst Odds")
                            .font(AppFonts.caption)
                            .foregroundStyle(AppColors.textSecondary)
                    }
                }
                .padding(.top, 20)
                .padding(.bottom, 12)
            }
        }
        .background(AppColors.backgroundPrimary)
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Helpers

    private func formatOdds(_ price: Int?) -> String {
        guard let price else { return "-" }
        return price > 0 ? "+\(price)" : "\(price)"
    }

    private func oddsBackground(price: Int?, allPrices: [Int]) -> Color {
        guard let price, allPrices.count > 1 else { return Color.clear }
        let sorted = allPrices.sorted()
        if price == sorted.last { return AppColors.bestOdds }
        if price == sorted.first { return AppColors.worstOdds }
        return Color.clear
    }

    private func shortenTeamName(_ name: String) -> String {
        let parts = name.split(separator: " ")
        if parts.count > 1 {
            return String(parts.last ?? Substring(name))
        }
        return name
    }

    private func formatGameTime(_ isoString: String) -> String {
        let formatter = ISO8601DateFormatter()
        guard let date = formatter.date(from: isoString) else { return isoString }
        let display = DateFormatter()
        display.dateFormat = "MMM d, h:mm a"
        return display.string(from: date)
    }
}

#Preview {
    NavigationStack {
        BetPage(event: previewBasketball[0])
    }
}
