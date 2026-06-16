//
//  DisclaimerCardView.swift
//  LineWatch
//
//  Replaces the system `.alert` disclaimer with a centered floating card that
//  matches the FeedbackFormView style — dimmed backdrop, rounded card, X button
//  and "Got It" button both dismiss.
//
//  Present via:
//    .fullScreenCover(isPresented: $showDisclaimer) { DisclaimerCardView() }
//

import SwiftUI

struct DisclaimerCardView: View {
    @Environment(\.dismiss) private var dismiss

    private let disclaimerText = "Sports betting availability varies by state. Not all sportsbooks are available in all states. Please check your local regulations before placing any bets. You must be 21+ to participate in sports betting. LineWatch is for informational purposes only. We are not liable for any financial losses from reliance on information displayed in this app."

    var body: some View {
        ZStack {
            // Dimmed backdrop — tap outside the card to dismiss.
            Color.black.opacity(0.55)
                .ignoresSafeArea()
                .onTapGesture { dismiss() }

            // Centered floating card.
            card
                .padding(.horizontal, 24)
        }
        .presentationBackground(.clear)
    }

    private var card: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {

                // Header — icon centered, X pinned top-right.
                ZStack(alignment: .topTrailing) {
                    Image(systemName: "info.circle.fill")
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundStyle(AppColors.primaryGreen)
                        .frame(maxWidth: .infinity)

                    Button { dismiss() } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 24))
                            .foregroundStyle(AppColors.textSecondary)
                    }
                }

                Text("Disclaimer")
                    .font(AppFonts.largeTitle)
                    .foregroundStyle(AppColors.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .center)

                Text(disclaimerText)
                    .font(AppFonts.body)
                    .foregroundStyle(AppColors.textSecondary)

                // Got It button
                Button { dismiss() } label: {
                    Text("Got It")
                        .font(.system(size: 17, weight: .bold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .foregroundStyle(.white)
                        .background(AppColors.primaryGreen)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
            .padding(24)
        }
        .fixedSize(horizontal: false, vertical: true)
        .background(AppColors.backgroundCard)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .shadow(color: AppColors.cardShadow, radius: 20, x: 0, y: 8)
    }
}

#Preview {
    DisclaimerCardView()
        .preferredColorScheme(.dark)
}
