//
//  LineWatchLogo.swift
//  LineWatch
//
//  Created by Steven Nguyen on 4/11/26.
//

import SwiftUI

/// Split-color "LineWatch" wordmark: white "Line" + green "Watch".
struct LineWatchLogo: View {
    var size: CGFloat = 32

    var body: some View {
        HStack(spacing: 0) {
            Text("Line")
                .foregroundStyle(.white)
            Text("Watch")
                .foregroundStyle(AppColors.primaryGreen)
        }
        .font(.system(size: size, weight: .bold, design: .rounded))
    }
}

#Preview {
    ZStack {
        AppColors.backgroundPrimary.ignoresSafeArea()
        LineWatchLogo()
    }
}
