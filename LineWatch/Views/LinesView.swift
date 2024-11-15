//
//  LinesView.swift
//  LineWatch
//
//  Created by Steven Nguyen on 11/12/24.
//

import SwiftUI

struct LinesView: View {
    var linesManager = LinesManager()
    @State var lines: [ResponseBody]?
    
    var body: some View {
        let index = lines?.count ?? 0
        
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
                VStack(spacing: 10) {
                    ForEach(0..<index, id: \.self) { temp in
                        Text(lines?[temp].homeTeam ?? "") + Text(" vs ") + Text(lines?[temp].awayTeam ?? "")
                        Divider()
                    }
                    
                }
                .padding(.top, 10)
                
            }
            .padding(.top,20)
//            .task {
//                do {
//                    lines = try await linesManager.getCurrentLines()
//                } catch GHError.invalidURL {
//                    print("invalid URL")
//                } catch GHError.invalidResponse {
//                    print("invalid response")
//                } catch GHError.invalidData {
//                    print("invalid data")
//                } catch {
//                    print("error")
//                }
//            }
            
        }
    }
}

#Preview {
    LinesView(lines: previewLines)
}
