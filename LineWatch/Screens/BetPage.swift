//
//  BetPage.swift
//  LineWatch
//
//  Created by Steven Nguyen on 3/9/26.
//

import SwiftUI

struct BetPage: View {
    let event: ResponseBody
    let marketType: MarketType

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                // Header
                headerSection

                // Market type badge
                Text(marketType.displayName)
                    .font(AppFonts.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(AppColors.darkGreen)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(AppColors.lightGreen.opacity(0.3))
                    )
                    .padding(.top, 8)
                    .padding(.bottom, 12)

                // Column Headers
                columnHeaders

                // Sportsbook Rows
                bookmakerRows

                // Legend
                legend
            }
        }
        .background(AppColors.backgroundPrimary)
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Header

    private var headerSection: some View {
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

            Text(event.awayTeam)
                .font(AppFonts.title)
                .foregroundStyle(AppColors.textPrimary)

            Text("@")
                .font(AppFonts.body)
                .foregroundStyle(AppColors.textSecondary)

            Text(event.homeTeam)
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
    }

    // MARK: - Column Headers

    private var columnHeaders: some View {
        HStack(spacing: 0) {
            Text("Sportsbook")
                .frame(maxWidth: .infinity, alignment: .leading)

            switch marketType {
            case .h2h:
                Text(shortenTeamName(event.awayTeam))
                    .frame(width: 80, alignment: .center)
                Text(shortenTeamName(event.homeTeam))
                    .frame(width: 80, alignment: .center)

            case .spreads:
                Text(shortenTeamName(event.awayTeam))
                    .frame(width: 100, alignment: .center)
                Text(shortenTeamName(event.homeTeam))
                    .frame(width: 100, alignment: .center)

            case .totals:
                Text("Over")
                    .frame(width: 100, alignment: .center)
                Text("Under")
                    .frame(width: 100, alignment: .center)

            case .outrights:
                Text("Odds")
                    .frame(width: 80, alignment: .center)
            }
        }
        .font(AppFonts.caption)
        .fontWeight(.semibold)
        .foregroundStyle(AppColors.textSecondary)
        .textCase(.uppercase)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(AppColors.backgroundPrimary)
    }

    // MARK: - Bookmaker Rows

    private var bookmakerRows: some View {
        let bookmakers = event.bookmakers

        return LazyVStack(spacing: 0) {
            ForEach(Array(bookmakers.enumerated()), id: \.offset) { index, bookmaker in
                let mkt = marketForBookmaker(bookmaker)

                HStack(spacing: 0) {
                    Text(bookmaker.title)
                        .font(AppFonts.body)
                        .foregroundStyle(AppColors.textPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    switch marketType {
                    case .h2h:
                        h2hCells(market: mkt)
                    case .spreads:
                        spreadCells(market: mkt)
                    case .totals:
                        totalCells(market: mkt)
                    case .outrights:
                        outrightCells(market: mkt)
                    }
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
    }

    // MARK: - H2H Cells

    @ViewBuilder
    private func h2hCells(market: Market?) -> some View {
        let awayOdds = market?.outcomes.first(where: { $0.name == event.awayTeam })?.price
        let homeOdds = market?.outcomes.first(where: { $0.name == event.homeTeam })?.price

        Text(formatOdds(awayOdds))
            .font(AppFonts.odds)
            .foregroundStyle(AppColors.textPrimary)
            .frame(width: 80, height: 36, alignment: .center)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(oddsBackground(price: awayOdds, allPrices: allPricesForTeam(event.awayTeam)))
            )

        Text(formatOdds(homeOdds))
            .font(AppFonts.odds)
            .foregroundStyle(AppColors.textPrimary)
            .frame(width: 80, height: 36, alignment: .center)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(oddsBackground(price: homeOdds, allPrices: allPricesForTeam(event.homeTeam)))
            )
    }

    // MARK: - Spread Cells

    @ViewBuilder
    private func spreadCells(market: Market?) -> some View {
        let awayOutcome = market?.outcomes.first(where: { $0.name == event.awayTeam })
        let homeOutcome = market?.outcomes.first(where: { $0.name == event.homeTeam })

        spreadCell(outcome: awayOutcome, allPrices: allPricesForTeam(event.awayTeam))
        spreadCell(outcome: homeOutcome, allPrices: allPricesForTeam(event.homeTeam))
    }

    @ViewBuilder
    private func spreadCell(outcome: Outcome?, allPrices: [Int]) -> some View {
        VStack(spacing: 1) {
            Text(formatPoint(outcome?.point))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(AppColors.textPrimary)
            Text(formatOdds(outcome?.price))
                .font(.system(size: 12, weight: .regular, design: .monospaced))
                .foregroundStyle(AppColors.textSecondary)
        }
        .frame(width: 100, height: 42, alignment: .center)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(oddsBackground(price: outcome?.price, allPrices: allPrices))
        )
    }

    // MARK: - Total Cells

    @ViewBuilder
    private func totalCells(market: Market?) -> some View {
        let overOutcome = market?.outcomes.first(where: { $0.name == "Over" })
        let underOutcome = market?.outcomes.first(where: { $0.name == "Under" })

        spreadCell(outcome: overOutcome, allPrices: allPricesForOutcome("Over"))
        spreadCell(outcome: underOutcome, allPrices: allPricesForOutcome("Under"))
    }

    // MARK: - Outright Cells

    @ViewBuilder
    private func outrightCells(market: Market?) -> some View {
        if let bestOdds = market?.outcomes.first?.price {
            Text(formatOdds(bestOdds))
                .font(AppFonts.odds)
                .foregroundStyle(AppColors.textPrimary)
                .frame(width: 80, height: 36, alignment: .center)
        } else {
            Text("-")
                .font(AppFonts.odds)
                .foregroundStyle(AppColors.textSecondary)
                .frame(width: 80, height: 36, alignment: .center)
        }
    }

    // MARK: - Legend

    private var legend: some View {
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

    // MARK: - Helpers

    private func marketForBookmaker(_ bookmaker: Bookmaker) -> Market? {
        bookmaker.markets.first(where: { $0.key == marketType.rawValue })
    }

    private func allPricesForTeam(_ teamName: String) -> [Int] {
        event.bookmakers.compactMap { bookmaker in
            marketForBookmaker(bookmaker)?.outcomes.first(where: { $0.name == teamName })?.price
        }
    }

    private func allPricesForOutcome(_ outcomeName: String) -> [Int] {
        event.bookmakers.compactMap { bookmaker in
            marketForBookmaker(bookmaker)?.outcomes.first(where: { $0.name == outcomeName })?.price
        }
    }

    private func formatOdds(_ price: Int?) -> String {
        guard let price else { return "-" }
        return price > 0 ? "+\(price)" : "\(price)"
    }

    private func formatPoint(_ point: Double?) -> String {
        guard let point else { return "-" }
        if point == point.rounded() {
            return point > 0 ? "+\(Int(point))" : "\(Int(point))"
        }
        return point > 0 ? "+\(point)" : "\(point)"
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

#Preview("Moneyline") {
    NavigationStack {
        BetPage(event: previewBasketball[0], marketType: .h2h)
    }
}

#Preview("Spreads") {
    NavigationStack {
        BetPage(event: previewBasketball[0], marketType: .spreads)
    }
}

#Preview("Totals") {
    NavigationStack {
        BetPage(event: previewBasketball[0], marketType: .totals)
    }
}
