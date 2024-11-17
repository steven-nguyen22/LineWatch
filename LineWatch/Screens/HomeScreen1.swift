//
//  HomeScreen1.swift
//  LineWatch
//
//  Created by Steven Nguyen on 11/17/24.
//

import SwiftUI

struct HomeScreen1: View {
    var body: some View {
        Text("LineWatch")
            .foregroundStyle(.black)
            .font(.largeTitle.bold())
            .frame(width: 200, height: 50)
            .padding()
            .background(RoundedRectangle(cornerRadius: 30)
                .fill(.green)
                .frame(width: 250, height: 100))
    }
}

#Preview {
    HomeScreen1()
}
