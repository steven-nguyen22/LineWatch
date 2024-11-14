//
//  BetScreen.swift
//  LineWatch
//
//  Created by Steven Nguyen on 11/13/24.
//

import SwiftUI

struct BetScreen: View {
    var body: some View {
        ZStack(alignment: .top) {
                    Color.teal.opacity(0.3)
                        .ignoresSafeArea()
            VStack{
                Text("Lakers vs Warriors")
                    .foregroundStyle(.white)
                    .font(.largeTitle)
                Divider()
                    .padding(.bottom, 30)
                
                
                VStack(spacing: 20) {
                    ForEach(0..<10, id:\.self) { _ in
                        HStack{
                            Text("Bovada")
                                .padding(.trailing, 100)
                            Text("-200")
                                .frame(width: 60, height: 30)
                                .background(Rectangle().stroke())
                                .background(.green)
                            Text("+200")
                                .frame(width: 60, height: 30)
                                .background(Rectangle().stroke())
                                .background(.red)
                            Divider()
                        }
                        Divider()
                    }
                    
                }
                .padding(.top, 10)
                
            }
            .padding(.top,20)
            
        }
    }
}

#Preview {
    BetScreen()
}
