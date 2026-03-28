//
//  AuthTextFields.swift
//  LineWatch
//
//  Created by Steven Nguyen on 3/27/26.
//

import SwiftUI

// MARK: - Auth Text Field

struct AuthTextField: View {
    @Binding var text: String
    var placeholder: String
    var label: String
    var keyboardType: UIKeyboardType = .default

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundStyle(.white.opacity(0.8))

            TextField("", text: $text, prompt: Text(placeholder).foregroundStyle(.white.opacity(0.3)))
                .font(.body)
                .foregroundStyle(.white)
                .keyboardType(keyboardType)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .padding(.horizontal, 14)
                .frame(height: 48)
                .background(.white.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(.white.opacity(0.15), lineWidth: 1)
                )
        }
    }
}

// MARK: - Auth Secure Field

struct AuthSecureField: View {
    @Binding var text: String
    var placeholder: String
    var label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundStyle(.white.opacity(0.8))

            SecureField("", text: $text, prompt: Text(placeholder).foregroundStyle(.white.opacity(0.3)))
                .font(.body)
                .foregroundStyle(.white)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .padding(.horizontal, 14)
                .frame(height: 48)
                .background(.white.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(.white.opacity(0.15), lineWidth: 1)
                )
        }
    }
}

#Preview {
    ZStack {
        Color(red: 0.12, green: 0.12, blue: 0.14).ignoresSafeArea()
        VStack(spacing: 16) {
            AuthTextField(text: .constant(""), placeholder: "ex: jon@email.com", label: "Email", keyboardType: .emailAddress)
            AuthSecureField(text: .constant(""), placeholder: "********", label: "Password")
        }
        .padding()
    }
}
