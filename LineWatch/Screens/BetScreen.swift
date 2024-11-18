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
    @State var awayList: [Int] = []
    @State var homeList: [Int] = []
    
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
                                    .background(
                                            awayOdds == awayList.last ? Color.green :
                                            awayOdds == awayList.first ? Color.red : Color.white
                                        )
                                Text(displayHomeOdds)
                                    .frame(width: 60, height: 30)
                                    .background(Rectangle().stroke())
                                    .background(
                                            homeOdds == homeList.last ? Color.green :
                                            homeOdds == homeList.first ? Color.red : Color.white
                                        )
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
        .onAppear {
            updateOdds()
        }
        
    }
    
    // Helper function to update odds
    private func updateOdds() {
        guard let bookmakers = lines?[currentIndex].bookmakers else { return }
        
        awayList = bookmakers.compactMap { $0.markets[0].outcomes[0].price }
        homeList = bookmakers.compactMap { $0.markets[0].outcomes[1].price }
        
        awayList.sort()
        homeList.sort()
    }
}

#Preview {
    BetScreen(lines: previewLines, currentIndex: 0)
}
