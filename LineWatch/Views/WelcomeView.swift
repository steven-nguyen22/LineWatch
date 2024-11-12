//
//  WelcomeView.swift
//  LineWatch
//
//  Created by Steven Nguyen on 11/11/24.
//

import SwiftUI

struct WelcomeView: View {
    var body: some View {
        VStack {
            VStack(spacing: 20) {
                Text("Welcome to LineWatch")
                    .bold().font(.title)
                Text("Get Started").padding()
            }
            .multilineTextAlignment(.center)
            .padding()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    WelcomeView()
}
