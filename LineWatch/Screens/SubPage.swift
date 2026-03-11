//
//  SubPage.swift
//  LineWatch
//
//  Created by Steven Nguyen on 3/9/26.
//

import SwiftUI

struct SubPage: View {
    let sport: SportCategory
    @Environment(OddsDataService.self) private var dataService
    @State private var selectedMarket: MarketType = .h2h

    var body: some View {
        let events = dataService.events(for: sport)

        ScrollView {
            if events.isEmpty {
                // Empty state
                VStack(spacing: 16) {
                    Image(systemName: "sportscourt")
                        .font(.system(size: 48))
                        .foregroundStyle(AppColors.textSecondary.opacity(0.5))

                    Text("No events available")
                        .font(AppFonts.title)
                        .foregroundStyle(AppColors.textSecondary)

                    Text("Check back later for upcoming \(sport.displayName.lowercased()) games.")
                        .font(AppFonts.body)
                        .foregroundStyle(AppColors.textSecondary.opacity(0.7))
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 100)
                .padding(.horizontal, 40)
            } else {
                VStack(spacing: 0) {
                    // Market type picker
                    Picker("Market", selection: $selectedMarket) {
                        ForEach(MarketType.standardMarkets) { market in
                            Text(market.displayName).tag(market)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 16)

                    // Event list
                    LazyVStack(spacing: 12) {
                        ForEach(events) { event in
                            NavigationLink(value: AppRoute.eventDetail(event, selectedMarket)) {
                                EventCard(event: event, marketType: selectedMarket)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
                }
            }
        }
        .background(AppColors.backgroundPrimary)
        .navigationTitle(sport.displayName)
        .navigationBarTitleDisplayMode(.large)
        .tint(AppColors.primaryGreen)
    }
}

// MARK: - Event Card

private struct EventCard: View {
    let event: ResponseBody
    let marketType: MarketType

    var body: some View {
        HStack(spacing: 12) {
            // Green accent bar
            RoundedRectangle(cornerRadius: 2)
                .fill(AppColors.primaryGreen)
                .frame(width: 4)

            // Team info
            VStack(alignment: .leading, spacing: 6) {
                Text(event.awayTeam)
                    .font(AppFonts.headline)
                    .foregroundStyle(AppColors.textPrimary)

                HStack(spacing: 4) {
                    Text("@")
                        .font(AppFonts.caption)
                        .foregroundStyle(AppColors.textSecondary)

                    Text(event.homeTeam)
                        .font(AppFonts.headline)
                        .foregroundStyle(AppColors.textPrimary)
                }

                if let time = event.commenceTime {
                    Text(formatGameTime(time))
                        .font(AppFonts.caption)
                        .foregroundStyle(AppColors.textSecondary)
                }
            }

            Spacer()

            // Market-specific preview
            oddsPreview

            Image(systemName: "chevron.right")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(AppColors.textSecondary.opacity(0.5))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(AppColors.backgroundCard)
                .shadow(color: AppColors.cardShadow, radius: 4, x: 0, y: 2)
        )
    }

    @ViewBuilder
    private var oddsPreview: some View {
        let market = event.bookmakers.first?.markets.first(where: { $0.key == marketType.rawValue })

        if let market = market, !market.outcomes.isEmpty {
            switch marketType {
            case .h2h:
                // Show two compact odds values
                VStack(spacing: 2) {
                    Text(formatOdds(market.outcomes.first?.price))
                        .font(AppFonts.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(AppColors.primaryGreen)
                    Text(formatOdds(market.outcomes.last?.price))
                        .font(AppFonts.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(AppColors.primaryGreen)
                }

            case .spreads:
                if let point = market.outcomes.first?.point {
                    VStack(spacing: 2) {
                        Text(formatPoint(point))
                            .font(AppFonts.headline)
                            .foregroundStyle(AppColors.primaryGreen)
                        Text("spread")
                            .font(.system(size: 10))
                            .foregroundStyle(AppColors.textSecondary)
                    }
                }

            case .totals:
                if let point = market.outcomes.first?.point {
                    VStack(spacing: 2) {
                        Text("O/U")
                            .font(.system(size: 10))
                            .foregroundStyle(AppColors.textSecondary)
                        Text(formatPoint(point))
                            .font(AppFonts.headline)
                            .foregroundStyle(AppColors.primaryGreen)
                    }
                }

            case .outrights:
                VStack(spacing: 2) {
                    Text("\(event.bookmakers.count)")
                        .font(AppFonts.headline)
                        .foregroundStyle(AppColors.primaryGreen)
                    Text("books")
                        .font(.system(size: 10))
                        .foregroundStyle(AppColors.textSecondary)
                }
            }
        } else {
            // Fallback: bookmaker count
            VStack(spacing: 2) {
                Text("\(event.bookmakers.count)")
                    .font(AppFonts.headline)
                    .foregroundStyle(AppColors.primaryGreen)
                Text("books")
                    .font(.system(size: 10))
                    .foregroundStyle(AppColors.textSecondary)
            }
        }
    }

    private func formatOdds(_ price: Int?) -> String {
        guard let price else { return "-" }
        return price > 0 ? "+\(price)" : "\(price)"
    }

    private func formatPoint(_ point: Double) -> String {
        if point == point.rounded() {
            return point > 0 ? "+\(Int(point))" : "\(Int(point))"
        }
        return point > 0 ? "+\(point)" : "\(point)"
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
        SubPage(sport: .basketball)
            .environment(previewDataService)
    }
}
