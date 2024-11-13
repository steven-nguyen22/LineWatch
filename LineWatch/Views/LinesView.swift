//
//  LinesView.swift
//  LineWatch
//
//  Created by Steven Nguyen on 11/12/24.
//

import SwiftUI

struct LinesView: View {
    var body: some View {
        ZStack(alignment: .top) {
                    Color.teal.opacity(0.3)
                        .ignoresSafeArea()
            VStack{
                Text("Basketball")
                    .foregroundStyle(.white)
                    .font(.largeTitle)
                    .frame(width: 200, height: 50)
                    .background(Rectangle().stroke())
                    .background(.yellow)
                VStack(spacing: 20) {
                    ForEach(0..<10) {
                        Text("Item \($0)")
                    }
                }
                .padding(.top, 10)
                
            }
            .padding(.top,20)
            
        }
    }
}

#Preview {
    LinesView()
}
