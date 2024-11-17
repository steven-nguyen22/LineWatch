//
//  ContentView.swift
//  LineWatch
//
//  Created by Steven Nguyen on 11/10/24.
//

import SwiftUI

struct ContentView: View {
//    @State private var presentedNumbers = [1, 4, 8]
    var linesManager = LinesManager()
    @State var lines: [ResponseBody]?

    var body: some View {
//        NavigationStack(path: $presentedNumbers) {
//            List(1..<50) { i in
//                NavigationLink(value: i) {
//                    Label("Row \(i)", systemImage: "\(i).circle")
//                }
//            }
//            .navigationDestination(for: Int.self) { i in
//                Text("Detail \(i)")
//            }
//            .navigationTitle("Navigation")
//        }
        
        NavigationView {
                    NavigationLink {
                        BetScreen(lines: lines, currentIndex: 1)
                    } label: {
                        VStack {
                            Image(systemName: "globe")
                                .imageScale(.large)
                                .foregroundColor(.accentColor)
                            Text("Hello, world!")
                        }
                        .padding()
                    }
                }
    }
}

#Preview {
    ContentView(lines: previewLines)
}
