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
                LazyVStack(spacing: 12) {
                    ForEach(events) { event in
                        NavigationLink(value: AppRoute.eventDetail(event)) {
                            EventCard(event: event)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 16)
            }
        }
        .background(AppColors.backgroundPrimary)
        .navigationTitle(sport.displayName)
        .navigationBarTitleDisplayMode(.large)
    }
}

// MARK: - Event Card

private struct EventCard: View {
    let event: ResponseBody

    var body: some View {
        HStack(spacing: 12) {
            // Green accent bar
            RoundedRectangle(cornerRadius: 2)
                .fill(AppColors.primaryGreen)
                .frame(width: 4)

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

            // Bookmaker count badge
            VStack(spacing: 2) {
                Text("\(event.bookmakers.count)")
                    .font(AppFonts.headline)
                    .foregroundStyle(AppColors.primaryGreen)
                Text("books")
                    .font(.system(size: 10))
                    .foregroundStyle(AppColors.textSecondary)
            }

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
