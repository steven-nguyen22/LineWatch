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
        
        NavigationView {
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
                    
                    ScrollView {
                        VStack(spacing: 20) {
                            ForEach(0..<index, id: \.self) { i in
                                NavigationLink {
                                    BetScreen(lines: lines, currentIndex: i)
                                } label : {
                                    Text("\(lines?[i].awayTeam ?? "") @ \(lines?[i].homeTeam ?? "")")
                                        .foregroundStyle(.black)
                                    Divider()
                                }
                            }
                        }
                        .padding(.top, 10)
                    }
                    
                    
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
}

#Preview {
    LinesView(lines: previewLines)
}
