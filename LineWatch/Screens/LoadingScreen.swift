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

            VStack(spacing: 20) {
                // App logo
                Image("AppLogo")
                    .resizable()
                    .scaledToFill()
                    .frame(width: 120, height: 120)
                    .clipShape(Circle())

                // Logo text: "Line" in white, "Watch" in green
                HStack(spacing: 0) {
                    Text("Line")
                        .foregroundStyle(.white)
                    Text("Watch")
                        .foregroundStyle(AppColors.primaryGreen)
                }
                .font(.system(size: 36, weight: .bold, design: .rounded))

                // Spinner
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: AppColors.primaryGreen))
                    .scaleEffect(1.3)
                    .padding(.top, 8)
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
        .trackScreen("loading")
    }
}

#Preview {
    LoadingScreen(onComplete: {})
}
