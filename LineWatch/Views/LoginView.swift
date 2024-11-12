//
//  SignInView.swift
//  LineWatch
//
//  Created by Steven Nguyen on 11/11/24.
//

import SwiftUI

struct LoginView: View {
    @State var username: String = ""
    @State var password: String = ""
    var body: some View {
        VStack {
            Text("Welcome Back")
                .font(.largeTitle)
                .fontWeight(.black)
                .padding(.bottom, 42)
            VStack(spacing: 16.0) {
                InputFieldView(data: $username, title: "Username")
                InputFieldView(data: $password, title: "Password")
            }
            Button(action: {}) {
                Text("Sign In")
                .fontWeight(.heavy)
                .font(.title3)
                .frame(maxWidth: .infinity)
                .padding()
                .foregroundColor(.white)
                .background(LinearGradient(gradient: Gradient(colors: [.pink, .purple]), startPoint: .leading, endPoint: .trailing))
                .cornerRadius(40)
            }
        }
        HStack {
            Spacer()                          // spacer to push text to the right
            Text("Forgotten Password?")
                .fontWeight(.thin)            // make the font thinner
                .foregroundColor(Color.blue)  // make the color blue
                .underline()                  // underline the text
        }.padding(.top, 16)                   // extrac space to the top to sign in button
    }
}

#Preview {
    LoginView()
}
