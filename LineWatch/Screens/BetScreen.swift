//
//  BetScreen.swift
//  LineWatch
//
//  Created by Steven Nguyen on 11/13/24.
//

import SwiftUI

struct BetScreen: View {
    var linesManager = LinesManager()
    @State var lines: [ResponseBody]?
    var currentIndex: Int
    
    var body: some View {
        let index = lines?[currentIndex].bookmakers.count ?? 0
        
        ZStack(alignment: .top) {
                    Color.teal.opacity(0.3)
                        .ignoresSafeArea()
            VStack{
                Text("\(lines?[currentIndex].awayTeam ?? "") @ \(lines?[currentIndex].homeTeam ?? "")")
                    .foregroundStyle(.black)
                    .font(.title)
                Divider()
                    .padding(.bottom, 30)
                
                ScrollView {
                    VStack(spacing: 20) {
                        ForEach(0..<index, id:\.self) { i in
                            let awayOdds = lines?[currentIndex].bookmakers[i].markets[0].outcomes[0].price
                            let homeOdds =
                                lines?[currentIndex].bookmakers[i].markets[0].outcomes[1].price
                            
                            let displayAwayOdds = awayOdds.map { $0 > 0 ? "+\($0)" : "\($0)" } ?? ""
                            let displayHomeOdds = homeOdds.map { $0 > 0 ? "+\($0)" : "\($0)" } ?? ""
                            HStack{
                                Text(lines?[0].bookmakers[i].title ?? "Bovada")
                                    .padding(.trailing, 100)
                                Text(displayAwayOdds)
                                    .frame(width: 60, height: 30)
                                    .background(Rectangle().stroke())
                                    .background(.green)
                                Text(displayHomeOdds)
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
                
                
            }
            .padding(.top,20)
            
        }
    }
}

#Preview {
    BetScreen(lines: previewLines, currentIndex: 0)
}
