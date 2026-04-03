//
//  BetPage.swift
//  LineWatch
//
//  Created by Steven Nguyen on 3/9/26.
//

import SwiftUI

// MARK: - Bet Selection Model

struct BetSelection: Equatable {
    let bookmakerTitle: String
    let outcomeName: String
    let odds: Int
}

// MARK: - BetPage

struct BetPage: View {
    let event: ResponseBody
    let marketType: MarketType

    @Environment(OddsDataService.self) private var dataService
    @State private var selections: [BetSelection] = []
    @State private var betAmount1: Double = 50
    @State private var betAmount2: Double = 50
    @State private var betText1: String = "50"
    @State private var betText2: String = "50"
    @State private var selectedPropType: PlayerPropType = .points
    @State private var isLoadingProps = false
    @FocusState private var focusedBet: Int?

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 0) {
                    // Header
                    headerSection

                    if marketType == .playerProps {
                        playerPropsContent
                    } else {
                        standardMarketContent
                    }

                    // Extra padding so content isn't hidden behind the panel
                    if !selections.isEmpty {
                        Spacer()
                            .frame(height: 20)
                    }
                }
            }

            // Sticky bet simulator panel
            if !selections.isEmpty {
                betSimulatorPanel
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.25), value: selections)
        .background(AppColors.backgroundPrimary)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") {
                    focusedBet = nil
                }
                .fontWeight(.semibold)
            }
        }
        .task {
            if marketType == .playerProps {
                isLoadingProps = true
                await dataService.fetchPlayerProps(eventId: event.id)
                isLoadingProps = false
            }
        }
    }

    // MARK: - Standard Market Content

    private var standardMarketContent: some View {
        VStack(spacing: 0) {
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

    // MARK: - Header

    private var headerSection: some View {
        VStack(spacing: 10) {
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

            HStack(spacing: 0) {
                // Away team (left)
                VStack(spacing: 8) {
                    if let logoURL = dataService.teamLogoURLs[event.awayTeam ?? ""],
                       let url = URL(string: logoURL) {
                        AsyncImage(url: url) { image in
                            image.resizable().scaledToFit()
                        } placeholder: {
                            Color.clear.frame(width: 56, height: 56)
                        }
                        .frame(width: 56, height: 56)
                    }
                    Text(event.awayDisplay)
                        .font(AppFonts.headline)
                        .foregroundStyle(AppColors.textPrimary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)

                Text("@")
                    .font(AppFonts.body)
                    .foregroundStyle(AppColors.textSecondary)

                // Home team (right)
                VStack(spacing: 8) {
                    if let logoURL = dataService.teamLogoURLs[event.homeTeam ?? ""],
                       let url = URL(string: logoURL) {
                        AsyncImage(url: url) { image in
                            image.resizable().scaledToFit()
                        } placeholder: {
                            Color.clear.frame(width: 56, height: 56)
                        }
                        .frame(width: 56, height: 56)
                    }
                    Text(event.homeDisplay)
                        .font(AppFonts.headline)
                        .foregroundStyle(AppColors.textPrimary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 20)

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
                Text(shortenTeamName(event.awayDisplay))
                    .frame(width: 80, alignment: .center)
                Text(shortenTeamName(event.homeDisplay))
                    .frame(width: 80, alignment: .center)

            case .spreads:
                Text(shortenTeamName(event.awayDisplay))
                    .frame(width: 100, alignment: .center)
                Text(shortenTeamName(event.homeDisplay))
                    .frame(width: 100, alignment: .center)

            case .totals:
                Text("Over")
                    .frame(width: 100, alignment: .center)
                Text("Under")
                    .frame(width: 100, alignment: .center)

            case .outrights:
                Text("Odds")
                    .frame(width: 80, alignment: .center)

            case .playerProps:
                EmptyView()  // Player props has its own layout
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
                        h2hCells(market: mkt, bookmakerTitle: bookmaker.title)
                    case .spreads:
                        spreadCells(market: mkt, bookmakerTitle: bookmaker.title)
                    case .totals:
                        totalCells(market: mkt, bookmakerTitle: bookmaker.title)
                    case .outrights:
                        outrightCells(market: mkt)
                    case .playerProps:
                        EmptyView()  // Player props has its own layout
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
    private func h2hCells(market: Market?, bookmakerTitle: String) -> some View {
        let awayOutcome = market?.outcomes.first(where: { $0.name == event.awayDisplay })
        let homeOutcome = market?.outcomes.first(where: { $0.name == event.homeDisplay })

        selectableOddsCell(
            odds: awayOutcome?.price,
            outcomeName: event.awayDisplay,
            bookmakerTitle: bookmakerTitle,
            allPrices: allPricesForTeam(event.awayDisplay),
            width: 80
        )

        selectableOddsCell(
            odds: homeOutcome?.price,
            outcomeName: event.homeDisplay,
            bookmakerTitle: bookmakerTitle,
            allPrices: allPricesForTeam(event.homeDisplay),
            width: 80
        )
    }

    // MARK: - Spread Cells

    @ViewBuilder
    private func spreadCells(market: Market?, bookmakerTitle: String) -> some View {
        let awayOutcome = market?.outcomes.first(where: { $0.name == event.awayDisplay })
        let homeOutcome = market?.outcomes.first(where: { $0.name == event.homeDisplay })

        selectableSpreadCell(
            outcome: awayOutcome,
            outcomeName: event.awayDisplay,
            bookmakerTitle: bookmakerTitle,
            allPrices: allPricesForTeam(event.awayDisplay)
        )

        selectableSpreadCell(
            outcome: homeOutcome,
            outcomeName: event.homeDisplay,
            bookmakerTitle: bookmakerTitle,
            allPrices: allPricesForTeam(event.homeDisplay)
        )
    }

    // MARK: - Total Cells

    @ViewBuilder
    private func totalCells(market: Market?, bookmakerTitle: String) -> some View {
        let overOutcome = market?.outcomes.first(where: { $0.name == "Over" })
        let underOutcome = market?.outcomes.first(where: { $0.name == "Under" })

        selectableSpreadCell(
            outcome: overOutcome,
            outcomeName: "Over",
            bookmakerTitle: bookmakerTitle,
            allPrices: allPricesForOutcome("Over")
        )

        selectableSpreadCell(
            outcome: underOutcome,
            outcomeName: "Under",
            bookmakerTitle: bookmakerTitle,
            allPrices: allPricesForOutcome("Under")
        )
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

    // MARK: - Selectable Odds Cell (H2H)

    @ViewBuilder
    private func selectableOddsCell(odds: Int?, outcomeName: String, bookmakerTitle: String, allPrices: [Int], width: CGFloat) -> some View {
        let selected = isSelected(bookmakerTitle: bookmakerTitle, outcomeName: outcomeName)

        Text(formatOdds(odds))
            .font(AppFonts.odds)
            .foregroundStyle(AppColors.textPrimary)
            .frame(width: width, height: 36, alignment: .center)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(oddsBackground(price: odds, allPrices: allPrices))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(selected ? AppColors.primaryGreen : Color.clear, lineWidth: 2.5)
            )
            .onTapGesture {
                if let odds {
                    toggleSelection(BetSelection(
                        bookmakerTitle: bookmakerTitle,
                        outcomeName: outcomeName,
                        odds: odds
                    ))
                }
            }
    }

    // MARK: - Selectable Spread/Total Cell

    @ViewBuilder
    private func selectableSpreadCell(outcome: Outcome?, outcomeName: String, bookmakerTitle: String, allPrices: [Int]) -> some View {
        let selected = isSelected(bookmakerTitle: bookmakerTitle, outcomeName: outcomeName)

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
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(selected ? AppColors.primaryGreen : Color.clear, lineWidth: 2.5)
        )
        .onTapGesture {
            if let price = outcome?.price {
                toggleSelection(BetSelection(
                    bookmakerTitle: bookmakerTitle,
                    outcomeName: outcomeName,
                    odds: price
                ))
            }
        }
    }

    // MARK: - Bet Simulator Panel

    private var betSimulatorPanel: some View {
        VStack(spacing: 0) {
            // Top accent border
            Rectangle()
                .fill(AppColors.primaryGreen)
                .frame(height: 2)

            VStack(spacing: 12) {
                // Header
                Text("Bet Simulator")
                    .font(AppFonts.headline)
                    .foregroundStyle(AppColors.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                // Selection 1
                if selections.count >= 1 {
                    betRow(selection: selections[0], betAmount: $betAmount1, betText: $betText1, rowIndex: 0)
                }

                // Selection 2
                if selections.count >= 2 {
                    Divider()
                        .foregroundStyle(AppColors.divider)

                    betRow(selection: selections[1], betAmount: $betAmount2, betText: $betText2, rowIndex: 1)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
        .background(
            AppColors.backgroundCard
                .shadow(color: AppColors.cardShadow, radius: 8, x: 0, y: -4)
        )
    }

    @ViewBuilder
    private func betRow(selection: BetSelection, betAmount: Binding<Double>, betText: Binding<String>, rowIndex: Int) -> some View {
        VStack(spacing: 8) {
            // Label + remove button
            HStack {
                HStack(spacing: 4) {
                    Text(selection.bookmakerTitle)
                        .font(AppFonts.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(AppColors.textPrimary)

                    Text("·")
                        .foregroundStyle(AppColors.textSecondary)

                    Text("\(shortenTeamName(selection.outcomeName)) (\(formatOdds(selection.odds)))")
                        .font(AppFonts.caption)
                        .foregroundStyle(AppColors.primaryGreen)
                }

                Spacer()

                Button {
                    removeSelection(selection)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(AppColors.textSecondary.opacity(0.6))
                }
            }

            // Slider row
            HStack(spacing: 8) {
                // Tappable dollar amount — tap to type a custom value
                HStack(spacing: 1) {
                    Text("$")
                        .font(.system(size: 14, weight: .semibold, design: .monospaced))
                        .foregroundStyle(AppColors.textPrimary)

                    TextField("0", text: betText)
                        .font(.system(size: 14, weight: .semibold, design: .monospaced))
                        .foregroundStyle(AppColors.textPrimary)
                        .keyboardType(.numberPad)
                        .focused($focusedBet, equals: rowIndex)
                        .onChange(of: betText.wrappedValue) { _, newValue in
                            // Only sync to slider if user is actively editing
                            if focusedBet == rowIndex {
                                let cleaned = newValue.filter { $0.isNumber }
                                if cleaned != newValue {
                                    betText.wrappedValue = cleaned
                                }
                                if let value = Double(cleaned) {
                                    betAmount.wrappedValue = min(value, 10000)
                                }
                            }
                        }
                        .onChange(of: focusedBet) { _, newFocus in
                            // When focus leaves this row, clamp and format
                            if newFocus != rowIndex {
                                let value = min(max(Double(betText.wrappedValue) ?? 0, 0), 10000)
                                betAmount.wrappedValue = value
                                betText.wrappedValue = "\(Int(value))"
                            }
                        }
                }
                .frame(width: 64, alignment: .leading)
                .lineLimit(1)

                Slider(value: betAmount, in: 0...1000, step: 10)
                    .tint(AppColors.primaryGreen)
                    .onChange(of: betAmount.wrappedValue) { _, newValue in
                        // Sync slider changes to text (only when not typing)
                        if focusedBet != rowIndex {
                            betText.wrappedValue = "\(Int(newValue))"
                        }
                    }

                let payout = calculatePayout(betAmount: betAmount.wrappedValue, odds: selection.odds)
                Text("+$\(payout, specifier: "%.2f")")
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .foregroundStyle(AppColors.primaryGreen)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .frame(width: 90, alignment: .trailing)
            }
        }
    }

    // MARK: - Player Props Content

    private var playerPropsContent: some View {
        VStack(spacing: 0) {
            // Sub-picker: Points | Rebounds | Assists
            Picker("Prop Type", selection: $selectedPropType) {
                ForEach(PlayerPropType.allCases) { propType in
                    Text(propType.displayName).tag(propType)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 16)

            if isLoadingProps {
                VStack(spacing: 12) {
                    ProgressView()
                        .scaleEffect(1.2)
                    Text("Loading player props...")
                        .font(AppFonts.caption)
                        .foregroundStyle(AppColors.textSecondary)
                }
                .padding(.top, 60)
            } else {
                let lines = buildPlayerPropLines(for: selectedPropType)

                if lines.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "person.crop.circle.badge.questionmark")
                            .font(.system(size: 40))
                            .foregroundStyle(AppColors.textSecondary.opacity(0.5))
                        Text("No player props available")
                            .font(AppFonts.body)
                            .foregroundStyle(AppColors.textSecondary)
                    }
                    .padding(.top, 60)
                } else {
                    let awayLines = lines.filter { $0.teamName == event.awayTeam }
                    let homeLines = lines.filter { $0.teamName == event.homeTeam }
                    let otherLines = lines.filter { $0.teamName == nil }

                    LazyVStack(spacing: 12) {
                        if !awayLines.isEmpty {
                            teamSectionHeader(teamName: event.awayTeam ?? "Away")
                            ForEach(awayLines) { line in
                                playerPropCard(line: line)
                            }
                        }
                        if !homeLines.isEmpty {
                            teamSectionHeader(teamName: event.homeTeam ?? "Home")
                            ForEach(homeLines) { line in
                                playerPropCard(line: line)
                            }
                        }
                        if !otherLines.isEmpty {
                            ForEach(otherLines) { line in
                                playerPropCard(line: line)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
                }
            }
        }
    }

    // MARK: - Team Section Header

    private func teamSectionHeader(teamName: String) -> some View {
        HStack(spacing: 8) {
            if let logoURL = dataService.teamLogoURLs[teamName],
               let url = URL(string: logoURL) {
                AsyncImage(url: url) { image in
                    image.resizable().scaledToFit()
                } placeholder: {
                    Color.clear.frame(width: 24, height: 24)
                }
                .frame(width: 24, height: 24)
            }
            Text(teamName)
                .font(AppFonts.headline)
                .foregroundStyle(AppColors.textPrimary)
            Rectangle()
                .fill(AppColors.textSecondary.opacity(0.2))
                .frame(height: 1)
        }
        .padding(.top, 8)
        .padding(.bottom, 4)
    }

    // MARK: - Player Prop Card

    private func playerPropCard(line: PlayerPropLine) -> some View {
        VStack(spacing: 0) {
            // Player header
            HStack(spacing: 10) {
                if let headshotURL = dataService.playerHeadshotURLs[line.playerName],
                   let url = URL(string: headshotURL) {
                    AsyncImage(url: url) { image in
                        image.resizable().scaledToFill()
                    } placeholder: {
                        Image(systemName: "person.circle.fill")
                            .font(.system(size: 36))
                            .foregroundStyle(AppColors.textSecondary.opacity(0.3))
                    }
                    .frame(width: 36, height: 36)
                    .clipShape(Circle())
                } else {
                    Image(systemName: "person.circle.fill")
                        .font(.system(size: 36))
                        .foregroundStyle(AppColors.textSecondary.opacity(0.3))
                }

                Text(line.playerName)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(AppColors.textPrimary)

                Spacer()

                Text(formatPoint(line.line))
                    .font(.system(size: 15, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(AppColors.primaryGreen)
                    )
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(AppColors.backgroundPrimary.opacity(0.6))

            // Mini column headers
            HStack(spacing: 0) {
                Text("Sportsbook")
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("Over")
                    .frame(width: 80, alignment: .center)
                Text("Under")
                    .frame(width: 80, alignment: .center)
            }
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(AppColors.textSecondary)
            .textCase(.uppercase)
            .padding(.horizontal, 14)
            .padding(.vertical, 6)

            // Bookmaker rows
            let allOverPrices = line.bookmakerOdds.compactMap(\.over)
            let allUnderPrices = line.bookmakerOdds.compactMap(\.under)

            ForEach(Array(line.bookmakerOdds.enumerated()), id: \.offset) { index, bm in
                HStack(spacing: 0) {
                    Text(bm.bookmakerTitle)
                        .font(.system(size: 13))
                        .foregroundStyle(AppColors.textPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    // Over cell
                    propOddsCell(
                        odds: bm.over,
                        outcomeName: "\(line.playerName) O \(formatPoint(line.line))",
                        bookmakerTitle: bm.bookmakerTitle,
                        allPrices: allOverPrices,
                        width: 80
                    )

                    // Under cell
                    propOddsCell(
                        odds: bm.under,
                        outcomeName: "\(line.playerName) U \(formatPoint(line.line))",
                        bookmakerTitle: bm.bookmakerTitle,
                        allPrices: allUnderPrices,
                        width: 80
                    )
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(index % 2 == 0 ? AppColors.backgroundCard : AppColors.backgroundPrimary.opacity(0.3))
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(AppColors.backgroundCard)
                .shadow(color: AppColors.cardShadow, radius: 4, x: 0, y: 2)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Prop Odds Cell

    @ViewBuilder
    private func propOddsCell(odds: Int?, outcomeName: String, bookmakerTitle: String, allPrices: [Int], width: CGFloat) -> some View {
        let selected = isSelected(bookmakerTitle: bookmakerTitle, outcomeName: outcomeName)

        Text(formatOdds(odds))
            .font(.system(size: 13, weight: .medium, design: .monospaced))
            .foregroundStyle(AppColors.textPrimary)
            .frame(width: width, height: 32, alignment: .center)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(oddsBackground(price: odds, allPrices: allPrices))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(selected ? AppColors.primaryGreen : Color.clear, lineWidth: 2.5)
            )
            .onTapGesture {
                if let odds {
                    toggleSelection(BetSelection(
                        bookmakerTitle: bookmakerTitle,
                        outcomeName: outcomeName,
                        odds: odds
                    ))
                }
            }
    }

    // MARK: - Build Player Prop Lines

    private func buildPlayerPropLines(for propType: PlayerPropType) -> [PlayerPropLine] {
        guard let propsData = dataService.playerPropsByEvent[event.id] else { return [] }

        // Collect all (playerName, line) → [(bookmakerTitle, over, under)]
        var playerMap: [String: (line: Double, bookmakers: [(bookmakerTitle: String, over: Int?, under: Int?)])] = [:]

        for bookmaker in propsData.bookmakers {
            guard let market = bookmaker.markets.first(where: { $0.key == propType.rawValue }) else { continue }

            // Group outcomes by player (description field)
            var playerOutcomes: [String: (over: Int?, under: Int?, line: Double?)] = [:]
            for outcome in market.outcomes {
                guard let playerName = outcome.description else { continue }
                var entry = playerOutcomes[playerName] ?? (over: nil, under: nil, line: nil)
                if outcome.name == "Over" {
                    entry.over = outcome.price
                    entry.line = outcome.point
                } else if outcome.name == "Under" {
                    entry.under = outcome.price
                    if entry.line == nil { entry.line = outcome.point }
                }
                playerOutcomes[playerName] = entry
            }

            // Merge into playerMap
            for (playerName, outcomes) in playerOutcomes {
                let line = outcomes.line ?? 0
                if var existing = playerMap[playerName] {
                    existing.bookmakers.append((bookmakerTitle: bookmaker.title, over: outcomes.over, under: outcomes.under))
                    playerMap[playerName] = existing
                } else {
                    playerMap[playerName] = (line: line, bookmakers: [(bookmakerTitle: bookmaker.title, over: outcomes.over, under: outcomes.under)])
                }
            }
        }

        // Look up player-to-team mapping
        let teamMap = dataService.playerTeamsByEvent[event.id] ?? [:]

        // Convert to array and sort by line descending (star players first)
        return playerMap.map { name, data in
            PlayerPropLine(playerName: name, line: data.line, teamName: teamMap[name], bookmakerOdds: data.bookmakers)
        }
        .sorted { $0.line > $1.line }
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

    // MARK: - Selection Helpers

    private func toggleSelection(_ selection: BetSelection) {
        if let index = selections.firstIndex(of: selection) {
            selections.remove(at: index)
        } else if selections.count < 2 {
            selections.append(selection)
        } else {
            selections[0] = selection
        }
    }

    private func removeSelection(_ selection: BetSelection) {
        selections.removeAll { $0 == selection }
    }

    private func isSelected(bookmakerTitle: String, outcomeName: String) -> Bool {
        selections.contains { $0.bookmakerTitle == bookmakerTitle && $0.outcomeName == outcomeName }
    }

    // MARK: - Payout Calculation

    private func calculatePayout(betAmount: Double, odds: Int) -> Double {
        guard betAmount > 0 else { return 0 }
        if odds > 0 {
            return betAmount * (Double(odds) / 100.0)
        } else {
            return betAmount * (100.0 / Double(abs(odds)))
        }
    }

    // MARK: - Formatting Helpers

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

    private func formatOdds(_ price: Int) -> String {
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
            .environment(previewDataService)
    }
}

#Preview("Spreads") {
    NavigationStack {
        BetPage(event: previewBasketball[0], marketType: .spreads)
            .environment(previewDataService)
    }
}

#Preview("Totals") {
    NavigationStack {
        BetPage(event: previewBasketball[0], marketType: .totals)
            .environment(previewDataService)
    }
}

#Preview("Player Props") {
    NavigationStack {
        BetPage(event: previewBasketball[0], marketType: .playerProps)
            .environment(previewDataService)
    }
}
