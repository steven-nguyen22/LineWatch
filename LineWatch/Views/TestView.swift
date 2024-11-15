//
//  TestView.swift
//  LineWatch
//
//  Created by Steven Nguyen on 11/14/24.
//

import SwiftUI

struct TestView: View {
    @State private var yer: [LinesTest]?
    
    var body: some View {
        VStack {
            let yup = yer?.count ?? 0
            ForEach(0..<yup, id: \.self) { temp in
                Text(yer?[temp].homeTeam ?? "") + Text(" vs ") + Text(yer?[temp].awayTeam ?? "")
                Divider()
            }
        }
        .task {
            do {
                yer = try await getLine()
            } catch GHError.invalidURL {
                print("invalid URL")
            } catch GHError.invalidResponse {
                print("invalid response")
            } catch GHError.invalidData {
                print("invalid data")
            } catch {
                print("error")
            }
        }
        
    }
    
    func getLine() async throws -> [LinesTest] {
        let endpoint = "https://api.the-odds-api.com/v4/sports/basketball_nba/odds/?apiKey=38362e374889c29da9e8c1692d5c133d&regions=us&markets=h2h&oddsFormat=american"
        
        guard let url = URL(string: endpoint) else {
            throw GHError.invalidURL
        }
        
        let (data, response) = try await URLSession.shared.data(from: url)
        
        
        guard let response = response as? HTTPURLResponse, response.statusCode == 200 else {
            throw GHError.invalidResponse
        }
        
        do {
            let decoder = JSONDecoder()
//            decoder.keyDecodingStrategy = .convertFromSnakeCase
//            return try decoder.decode(LinesTest.self, from: data)
            let temp: [LinesTest] = try decoder.decode([LinesTest].self, from: data)
//            let temp = try decoder.decode(LinesTest.self, from: data)
//            print(temp[0])
            return temp
//            let output = temp.lines[0]
//            return output
        } catch {
            throw GHError.invalidData
        }
        
        
    }
}

#Preview {
    TestView()
}

struct LinesTest: Codable {
    let sportKey, homeTeam, awayTeam: String
    
    enum CodingKeys: String, CodingKey {
            case sportKey = "sport_key"
            case homeTeam = "home_team"
            case awayTeam = "away_team"
        }
}

//enum GHError: Error {
//    case invalidURL
//    case invalidResponse
//    case invalidData
//}
