//
//  LoadingScreen.swift
//  LineWatch
//
//  Created by Steven Nguyen on 3/9/26.
//

import SwiftUI

struct LoadingScreen: View {
    var onComplete: () -> Void

    var body: some View {
        ZStack {
            // Dark background with subtle green gradient
            LinearGradient(
                colors: [
                    AppColors.backgroundDark,
                    Color(red: 0.08, green: 0.14, blue: 0.10)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 28) {
                // Logo
                Text("LineWatch")
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .foregroundStyle(AppColors.primaryGreen)

                // Spinner
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: AppColors.primaryGreen))
                    .scaleEffect(1.3)
            }
        }
        .onAppear {
            Task {
                try? await Task.sleep(for: .seconds(2))
                await MainActor.run {
                    onComplete()
                }
            }
        }
    }
}

#Preview {
    LoadingScreen(onComplete: {})
}
