//
//  ContentView.swift
//  LineWatch
//
//  Created by Steven Nguyen on 11/10/24.
//

import SwiftUI

struct ContentView: View {
    var linesManager = LinesManager()
    @State var lines: ResponseBody?
    
    var body: some View {
//        VStack {
//            Image(systemName: "globe")
//                .imageScale(.large)
//                .foregroundStyle(.tint)
//            Text("Hello, world!")
//            Text("test")
//        }
//        .padding()
        
        VStack {
//            if let lines = lines {
//                Text("data fetched succesfully!")
//            }
//            else {
//                LoadingView()
//                    .task {
//                        do {
//                            lines = try await linesManager.getCurrentLines()
//                        } catch {
//                            print("Error getting weather: \(error)")
//                        }
//                    }
//            }
//            Text("test")
//                    .task {
//                        do {
//                            lines = try await linesManager.getCurrentLines()
//                        } catch {
//                            print(String(describing: error))
//                        }
//                    }
            WelcomeView()
        }
        .background(.blue)
        .preferredColorScheme(.dark)
    }
}

#Preview {
    ContentView()
}
