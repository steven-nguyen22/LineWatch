//
//  FeedbackFormView.swift
//  LineWatch
//
//  A lightweight in-app form so users can send bug reports / feature requests
//  straight to the developers. Submits to the `submit-feedback` edge function,
//  which emails the message to the LineWatch inbox via Resend.
//
//  Presented via `.fullScreenCover` with a clear background, so this renders as
//  a centered floating card over a dimmed home screen (not a bottom sheet).
//

import SwiftUI

struct FeedbackFormView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var subject = ""
    @State private var details = ""
    @State private var isSending = false
    @State private var didSend = false
    @State private var errorMessage: String?

    private let service = SupabaseService()

    private var canSubmit: Bool {
        !subject.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !details.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

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
        .trackScreen("feedback_form")
        .onAppear { PostHogService.capture("feedback_opened") }
    }

    private var card: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header

                if didSend {
                    successState
                } else {
                    formFields
                    sendButton
                    if let errorMessage {
                        Text(errorMessage)
                            .font(AppFonts.caption)
                            .foregroundStyle(AppColors.alertRed)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .multilineTextAlignment(.center)
                    }

                    featuresInProgress
                }
            }
            .padding(24)
        }
        .frame(maxHeight: 760)
        .fixedSize(horizontal: false, vertical: true)
        .background(AppColors.backgroundCard)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .shadow(color: AppColors.cardShadow, radius: 20, x: 0, y: 8)
    }

    // MARK: - Sections

    private var header: some View {
        VStack(spacing: 12) {
            // X pinned top-right via overlay so the title stays centered.
            ZStack(alignment: .topTrailing) {
                Image(systemName: "square.and.pencil")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(AppColors.primaryGreen)
                    .frame(maxWidth: .infinity)

                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(AppColors.textSecondary)
                }
            }

            Text("Share Your Feedback")
                .font(AppFonts.largeTitle)
                .foregroundStyle(AppColors.textPrimary)
                .frame(maxWidth: .infinity, alignment: .center)
                .multilineTextAlignment(.center)

            Text("Found a bug or have a feature you'd like to see? Send it straight to the developers — we read every message.")
                .font(AppFonts.body)
                .foregroundStyle(AppColors.textSecondary)
                .frame(maxWidth: .infinity, alignment: .center)
                .multilineTextAlignment(.center)
        }
    }

    private var formFields: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                AuthTextField(
                    text: $subject,
                    placeholder: "ex: Odds not loading for NBA",
                    label: "Subject"
                )
                Text("A short summary of your bug, report, or idea.")
                    .font(AppFonts.caption)
                    .foregroundStyle(AppColors.textSecondary)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Details")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(.white.opacity(0.8))

                FeedbackTextEditor(text: $details)

                Text("Describe the bug, feature, or change you'd like in as much detail as you want.")
                    .font(AppFonts.caption)
                    .foregroundStyle(AppColors.textSecondary)
            }
        }
    }

    private var sendButton: some View {
        Button {
            send()
        } label: {
            Group {
                if isSending {
                    ProgressView().tint(.white)
                } else {
                    Text("SEND")
                        .font(.system(size: 17, weight: .bold))
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .foregroundStyle(.white)
            .background(AppColors.primaryGreen)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .disabled(!canSubmit || isSending)
        .opacity(canSubmit && !isSending ? 1.0 : 0.6)
    }

    private var featuresInProgress: some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider()
                .foregroundStyle(AppColors.divider)

            Text("Features In-Progress")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(AppColors.textPrimary)

            HStack(alignment: .top, spacing: 10) {
                Circle()
                    .fill(AppColors.primaryGreen)
                    .frame(width: 6, height: 6)
                    .padding(.top, 6)
                Text("Machine Learning MLB Prediction Algorithm")
                    .font(AppFonts.caption)
                    .foregroundStyle(AppColors.textSecondary)
            }
        }
    }

    private var successState: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(AppColors.primaryGreen)
            Text("Thanks! Your feedback was sent.")
                .font(AppFonts.title)
                .foregroundStyle(AppColors.textPrimary)
                .multilineTextAlignment(.center)
            Text("We appreciate you helping make LineWatch better.")
                .font(AppFonts.body)
                .foregroundStyle(AppColors.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
    }

    // MARK: - Actions

    private func send() {
        isSending = true
        errorMessage = nil
        Task {
            do {
                try await service.submitFeedback(subject: subject, body: details)
                PostHogService.capture("feedback_sent")
                await MainActor.run {
                    isSending = false
                    didSend = true
                }
                // Auto-dismiss shortly after showing the confirmation.
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                await MainActor.run { dismiss() }
            } catch FeedbackError.rateLimited {
                await MainActor.run {
                    isSending = false
                    errorMessage = "You've sent a lot of feedback recently — please try again later."
                }
            } catch {
                await MainActor.run {
                    isSending = false
                    errorMessage = "Couldn't send — please check your connection and try again."
                }
            }
        }
    }
}

// MARK: - Styled multi-line editor

/// A `TextEditor` styled to match `AuthTextField` (the app has no other
/// multi-line input). Shows a placeholder when empty.
private struct FeedbackTextEditor: View {
    @Binding var text: String

    var body: some View {
        ZStack(alignment: .topLeading) {
            if text.isEmpty {
                Text("Tell us what happened or what you'd like…")
                    .font(.body)
                    .foregroundStyle(.white.opacity(0.3))
                    .padding(.horizontal, 18)
                    .padding(.vertical, 16)
            }
            TextEditor(text: $text)
                .font(.body)
                .foregroundStyle(.white)
                .scrollContentBackground(.hidden)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
        }
        .frame(minHeight: 120, alignment: .topLeading)
        .background(.white.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(.white.opacity(0.15), lineWidth: 1)
        )
    }
}

#Preview {
    FeedbackFormView()
        .preferredColorScheme(.dark)
}
