//
//  TermsOfServiceView.swift
//  LineWatch
//
//  Shown once during onboarding, after the features walkthrough and
//  before sign-in. Persists agreement via @AppStorage("hasAgreedToTerms")
//  so users only see this screen once.
//

import SwiftUI

struct TermsOfServiceView: View {
    let onAgree: () -> Void

    @State private var hasChecked = false

    private static let termsURL = URL(string: "https://steven-nguyen22.github.io/LineWatch-Website/#/terms")!
    private static let privacyURL = URL(string: "https://steven-nguyen22.github.io/LineWatch-Website/#/privacy")!

    var body: some View {
        ZStack {
            AppColors.backgroundPrimary
                .ignoresSafeArea()

            VStack(spacing: 0) {
                ScrollView {
                    VStack(spacing: 24) {
                        // Icon
                        Image(systemName: "doc.text.fill")
                            .font(.system(size: 56))
                            .foregroundStyle(AppColors.primaryGreen)
                            .padding(.top, 40)

                        // Title
                        Text("Terms of Service")
                            .font(AppFonts.largeTitle)
                            .foregroundStyle(AppColors.textPrimary)

                        Text("Please review and agree before continuing")
                            .font(AppFonts.body)
                            .foregroundStyle(AppColors.textSecondary)
                            .multilineTextAlignment(.center)

                        // Key points
                        VStack(alignment: .leading, spacing: 16) {
                            bulletPoint(
                                icon: "info.circle.fill",
                                title: "Informational Purposes Only",
                                description: "LineWatch displays publicly available odds. We do not accept bets, wagers, or payments."
                            )
                            bulletPoint(
                                icon: "exclamationmark.triangle.fill",
                                title: "No Guarantee of Accuracy",
                                description: "Odds may be delayed or inaccurate. Always verify with your sportsbook before placing a wager."
                            )
                            bulletPoint(
                                icon: "person.fill.checkmark",
                                title: "21+ Only",
                                description: "You must be at least 21 years of age and located in a jurisdiction where sports betting is legal."
                            )
                            bulletPoint(
                                icon: "shield.fill",
                                title: "Limited Liability",
                                description: "LineWatch is not responsible for any financial losses resulting from reliance on information in this app."
                            )
                        }
                        .padding(.horizontal, 24)
                        .padding(.top, 8)

                        // Read full ToS link
                        Link(destination: Self.termsURL) {
                            HStack(spacing: 6) {
                                Text("Read full Terms of Service")
                                Image(systemName: "arrow.up.right")
                                    .font(.system(size: 12, weight: .semibold))
                            }
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(AppColors.primaryGreen)
                        }
                        .padding(.top, 8)
                        .padding(.bottom, 24)
                    }
                }

                // Bottom: checkbox + continue button
                VStack(spacing: 16) {
                    // Agreement checkbox — only the checkbox icon toggles state.
                    // The label text contains tappable Links that must NOT be
                    // wrapped inside a Button (the Button would swallow the tap).
                    HStack(alignment: .top, spacing: 12) {
                        Button {
                            hasChecked.toggle()
                        } label: {
                            Image(systemName: hasChecked ? "checkmark.square.fill" : "square")
                                .font(.system(size: 22))
                                .foregroundStyle(hasChecked ? AppColors.primaryGreen : AppColors.textSecondary)
                        }
                        .buttonStyle(.plain)

                        agreementText
                            .font(.system(size: 13))
                            .foregroundStyle(AppColors.textPrimary)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                            .tint(AppColors.primaryGreen)

                        Spacer(minLength: 0)
                    }

                    // Continue button
                    Button {
                        onAgree()
                    } label: {
                        Text("Continue")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(
                                RoundedRectangle(cornerRadius: 14)
                                    .fill(hasChecked ? AppColors.primaryGreen : AppColors.textSecondary.opacity(0.3))
                            )
                    }
                    .buttonStyle(.plain)
                    .disabled(!hasChecked)
                    .animation(.easeInOut(duration: 0.2), value: hasChecked)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 40)
                .padding(.top, 16)
                .background(
                    AppColors.backgroundPrimary
                        .shadow(color: .black.opacity(0.3), radius: 8, y: -4)
                )
            }
        }
        .trackScreen("terms_of_service")
    }

    /// Inline checkbox label — markdown links inside Text are tappable in iOS 15+
    /// when the Text isn't wrapped in a Button. Link color is controlled by the
    /// outer `.tint(...)` modifier so it inherits the app's primary green.
    private var agreementText: Text {
        Text("I agree to the [Terms of Service](\(Self.termsURL.absoluteString)) and [Privacy Policy](\(Self.privacyURL.absoluteString))")
    }

    private func bulletPoint(icon: String, title: String, description: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundStyle(AppColors.primaryGreen)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(AppColors.textPrimary)
                Text(description)
                    .font(.system(size: 13))
                    .foregroundStyle(AppColors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

#Preview {
    TermsOfServiceView(onAgree: {})
}
