//
//  SubPage.swift
//  LineWatch
//
//  Created by Steven Nguyen on 3/9/26.
//

import SwiftUI
import NukeUI

struct SubPage: View {
    let sport: SportCategory
    @Environment(OddsDataService.self) private var dataService
    @Environment(AuthService.self) private var authService
    @State private var selectedMarket: MarketType = .h2h
    @State private var selectedLeague: FightingLeague = .mma
    @State private var searchText: String = ""
    @State private var showDisclaimer = false
    @State private var showPaywallForProps = false

    var body: some View {
        let events = displayedEvents

        ScrollView {
            VStack(spacing: 0) {
                // Header picker: fighting → league tabs; else → market tabs or single badge
                if sport == .fighting {
                    Picker("League", selection: $selectedLeague) {
                        ForEach(FightingLeague.allCases) { league in
                            Text(league.displayName).tag(league)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 16)
                } else if sport.availableMarkets.count > 1 {
                    // Custom segmented control — allows SF Symbol lock icon inline with text
                    HStack(spacing: 0) {
                        ForEach(sport.availableMarkets) { market in
                            let isSelected = selectedMarket == market
                            let locked = market == .playerProps && !authService.effectiveTier.canAccessPlayerProps

                            Button {
                                if locked {
                                    showPaywallForProps = true
                                } else {
                                    selectedMarket = market
                                }
                            } label: {
                                HStack(spacing: 4) {
                                    Text(market == .h2h ? "ML" : market.displayName)
                                        .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                                        .lineLimit(1)
                                    if locked {
                                        Image(systemName: "lock.fill")
                                            .font(.system(size: 10))
                                    }
                                }
                                .foregroundStyle(isSelected ? AppColors.textPrimary : AppColors.textSecondary)
                                .padding(.vertical, 7)
                                .padding(.horizontal, 6)
                                // Player Props gets all remaining space; other segments cap at 80pt
                                .frame(maxWidth: market == .playerProps ? .infinity : 80)
                                .background(
                                    RoundedRectangle(cornerRadius: 7)
                                        .fill(isSelected ? AppColors.backgroundCard : Color.clear)
                                        .shadow(color: isSelected ? AppColors.cardShadow : Color.clear, radius: 2, x: 0, y: 1)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(3)
                    .background(
                        RoundedRectangle(cornerRadius: 9)
                            .fill(Color(UIColor.systemGray5))
                    )
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 16)
                } else {
                    // Single market badge (e.g., "Outrights" for golf)
                    Text(sport.availableMarkets.first?.displayName ?? "")
                        .font(AppFonts.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(
                            Capsule()
                                .fill(AppColors.primaryGreen.opacity(0.3))
                        )
                        .padding(.top, 12)
                        .padding(.bottom, 16)
                }

                // Search bar
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(AppColors.textSecondary)
                    TextField("Search teams...", text: $searchText)
                        .font(AppFonts.body)
                        .foregroundStyle(AppColors.textPrimary)
                        .autocorrectionDisabled()
                    if !searchText.isEmpty {
                        Button {
                            searchText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(AppColors.textSecondary)
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(AppColors.backgroundCard)
                )
                .padding(.horizontal, 16)
                .padding(.bottom, 12)

                if events.isEmpty {
                    // Empty state
                    VStack(spacing: 16) {
                        Image(systemName: "sportscourt")
                            .font(.system(size: 48))
                            .foregroundStyle(AppColors.textSecondary.opacity(0.5))

                        Text("No events available")
                            .font(AppFonts.title)
                            .foregroundStyle(AppColors.textSecondary)

                        Text("Check back later for upcoming \(sport.displayName.lowercased()) events.")
                            .font(AppFonts.body)
                            .foregroundStyle(AppColors.textSecondary.opacity(0.7))
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, 80)
                    .padding(.horizontal, 40)
                } else {
                    // Event list
                    LazyVStack(spacing: 12) {
                        ForEach(events) { event in
                            NavigationLink(value: AppRoute.eventDetail(event, selectedMarket, nil)) {
                                EventCard(
                                    event: event,
                                    marketType: selectedMarket,
                                    awayLogoURL: imageURL(for: event.awayTeam, isFighting: event.isFighting),
                                    homeLogoURL: imageURL(for: event.homeTeam, isFighting: event.isFighting)
                                )
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
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showDisclaimer = true
                } label: {
                    Image(systemName: "info.circle")
                        .foregroundStyle(AppColors.textSecondary)
                }
            }
        }
        .alert("Disclaimer", isPresented: $showDisclaimer) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Sports betting availability varies by state. Not all sportsbooks are available in all states. Please check your local regulations before placing any bets. You must be 21+ to participate in sports betting.")
        }
        .navigationDestination(isPresented: $showPaywallForProps) {
            PaywallView()
        }
        .onAppear {
            if !sport.availableMarkets.contains(selectedMarket) {
                selectedMarket = sport.availableMarkets.first ?? .h2h
            }
        }
    }

    private var displayedEvents: [ResponseBody] {
        var all = dataService.events(for: sport)
        if sport == .fighting {
            all = all.filter { $0.sportKey == selectedLeague.rawValue }
        }
        guard !searchText.isEmpty else { return all }
        let query = searchText.lowercased()
        return all.filter {
            ($0.homeTeam?.lowercased().contains(query) ?? false) ||
            ($0.awayTeam?.lowercased().contains(query) ?? false) ||
            $0.sportTitle.lowercased().contains(query)
        }
    }

    private func imageURL(for name: String?, isFighting: Bool) -> String? {
        guard let name = name else { return nil }
        return isFighting
            ? dataService.playerHeadshotURLs[name]
            : dataService.teamLogoURLs[name]
    }
}

// MARK: - Event Card

private struct EventCard: View {
    let event: ResponseBody
    let marketType: MarketType
    let awayLogoURL: String?
    let homeLogoURL: String?

    var body: some View {
        HStack(spacing: 12) {
            // Green accent bar
            RoundedRectangle(cornerRadius: 2)
                .fill(AppColors.primaryGreen)
                .frame(width: 4)

            // Team info
            if event.isGolf {
                // Golf: just tournament name + time (no teams)
                VStack(alignment: .leading, spacing: 6) {
                    Text(event.sportTitle)
                        .font(AppFonts.headline)
                        .foregroundStyle(AppColors.textPrimary)
                        .lineLimit(1)

                    if let time = event.commenceTime {
                        Text(formatGameTime(time))
                            .font(AppFonts.caption)
                            .foregroundStyle(AppColors.textSecondary)
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        competitorImage(url: awayLogoURL)
                        Text(event.awayDisplay)
                            .font(AppFonts.headline)
                            .foregroundStyle(AppColors.textPrimary)
                            .lineLimit(1)
                    }

                    HStack(spacing: 4) {
                        Text(event.isFighting ? "vs" : "@")
                            .font(AppFonts.caption)
                            .foregroundStyle(AppColors.textSecondary)

                        competitorImage(url: homeLogoURL)
                        Text(event.homeDisplay)
                            .font(AppFonts.headline)
                            .foregroundStyle(AppColors.textPrimary)
                            .lineLimit(1)
                    }

                    if let time = event.commenceTime {
                        Text(formatGameTime(time))
                            .font(AppFonts.caption)
                            .foregroundStyle(AppColors.textSecondary)
                    }
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
    private func competitorImage(url: String?) -> some View {
        if event.isFighting {
            FighterCircle(url: url, size: 24)
        } else if let urlString = url, let url = URL(string: urlString) {
            LazyImage(url: url) { state in
                if let image = state.image {
                    image.resizable().scaledToFit()
                }
            }
            .frame(width: 20, height: 20)
        }
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

            case .playerProps:
                VStack(spacing: 2) {
                    Image(systemName: "person.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(AppColors.primaryGreen)
                    Text("Props")
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

// MARK: - Fighter Circle (shared)

struct FighterCircle: View {
    let url: String?
    let size: CGFloat

    var body: some View {
        ZStack {
            Circle().fill(Color.gray.opacity(0.3))
            if let urlString = url, let imageURL = URL(string: urlString) {
                LazyImage(url: imageURL) { state in
                    if let image = state.image {
                        image.resizable().scaledToFill()
                    } else {
                        Image(systemName: "figure.boxing")
                            .font(.system(size: size * 0.5))
                            .foregroundStyle(.gray)
                    }
                }
                .clipShape(Circle())
            } else {
                Image(systemName: "figure.boxing")
                    .font(.system(size: size * 0.5))
                    .foregroundStyle(.gray)
            }
        }
        .frame(width: size, height: size)
    }
}

#Preview {
    NavigationStack {
        SubPage(sport: .basketball)
            .environment(previewDataService)
            .environment(AuthService())
    }
}
