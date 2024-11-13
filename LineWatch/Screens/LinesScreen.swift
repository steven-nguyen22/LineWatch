//
//  LinesScreen.swift
//  LineWatch
//
//  Created by Steven Nguyen on 11/12/24.
//

import SwiftUI

struct LinesScreen: View {
    var body: some View {

//            VStack{
//                HStack{
//                    Text("LArrow")
//                    ScrollView(.horizontal) {
//                        HStack(spacing: 20) {
//                            ForEach(0..<10) {
//                                Text("Item \($0)")
//                                    .foregroundStyle(.white)
//                                    .font(.largeTitle)
//                                    .frame(width: 200, height: 200)
//                                    .background(.red)
//                            }
//                        }
//                    }
//                    Text("RArrow")
//                }
//            }
        HStack {
            ScrollView(.horizontal) {
                HStack() {
                    LinesView()
                    LinesView()
                }
                
            }
        }
            

    }
    
}

#Preview {
    LinesScreen()
}
