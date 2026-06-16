//
//  FeedbackFormView.swift
//  LineWatch
//
//  A lightweight in-app form so users can send bug reports / feature requests
//  straight to the developers. Submits to the `submit-feedback` edge function,
//  which emails the message to the LineWatch inbox via Resend.
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
            AppColors.backgroundPrimary.ignoresSafeArea()

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
                        }
                    }
                }
                .padding(20)
            }
        }
        .presentationDragIndicator(.visible)
        .trackScreen("feedback_form")
        .onAppear { PostHogService.capture("feedback_opened") }
    }

    // MARK: - Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "square.and.pencil")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(AppColors.primaryGreen)
                Spacer()
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

            Text("Found a bug or have a feature you'd like to see? Send it straight to the developers — we read every message.")
                .font(AppFonts.body)
                .foregroundStyle(AppColors.textSecondary)
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
                Text("A short summary of your bug report or idea.")
                    .font(AppFonts.caption)
                    .foregroundStyle(AppColors.textSecondary)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Details")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(.white.opacity(0.8))

                FeedbackTextEditor(text: $details)

                Text("Describe the bug or the feature you'd like in as much detail as you want.")
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
        .padding(.top, 40)
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
        .frame(minHeight: 140, alignment: .topLeading)
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
