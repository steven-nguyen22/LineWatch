//
//  LinesScreen.swift
//  LineWatch
//
//  Created by Steven Nguyen on 11/12/24.
//

import SwiftUI

struct LinesScreen: View {
    var linesManager = LinesManager()
    @State var lines: [ResponseBody]?

    var body: some View {

        HStack {
            ScrollView(.horizontal) {
                HStack() {
                    LinesView(lines: previewLines)
                        .containerRelativeFrame(.horizontal, count: 1, spacing: 16)
                    LinesView(lines: previewLines)
                        .containerRelativeFrame(.horizontal, count: 1, spacing: 16)
                }
                
                
            }
        }
            

    }
    
}

#Preview {
    LinesScreen(lines: previewLines)
}
