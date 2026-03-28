//
//  SignInView.swift
//  LineWatch
//
//  Created by Steven Nguyen on 3/27/26.
//

import SwiftUI
import AuthenticationServices
import GoogleSignIn

struct SignInView: View {
    @Environment(AuthService.self) private var authService
    @State private var currentNonce: String?

    var body: some View {
        ZStack {
            // Same gradient background as LoadingScreen
            LinearGradient(
                colors: [
                    AppColors.backgroundDark,
                    Color(red: 0.08, green: 0.14, blue: 0.10)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                // Logo
                Text("LineWatch")
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .foregroundStyle(AppColors.primaryGreen)

                Text("Sign in to continue")
                    .font(.body)
                    .foregroundStyle(.white.opacity(0.7))
                    .padding(.top, 12)

                Spacer()

                // Sign-in buttons
                VStack(spacing: 16) {
                    // Sign In with Apple
                    SignInWithAppleButton(.signIn) { request in
                        let nonce = AuthService.randomNonceString()
                        currentNonce = nonce
                        request.requestedScopes = [.email, .fullName]
                        request.nonce = AuthService.sha256(nonce)
                    } onCompletion: { result in
                        handleAppleSignIn(result)
                    }
                    .signInWithAppleButtonStyle(.whiteOutline)
                    .frame(height: 52)

                    // Sign In with Google
                    Button {
                        handleGoogleSignIn()
                    } label: {
                        HStack(spacing: 12) {
                            // Google "G" logo
                            Image(systemName: "g.circle.fill")
                                .font(.title2)
                                .foregroundStyle(.blue)

                            Text("Sign in with Google")
                                .font(.system(size: 17, weight: .medium))
                                .foregroundStyle(Color(red: 0.26, green: 0.26, blue: 0.26))
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }

                    // Error message
                    if let error = authService.authError {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                            .padding(.top, 8)
                    }
                }
                .padding(.horizontal, 40)

                Spacer()
                    .frame(height: 80)
            }
        }
    }

    // MARK: - Apple Sign In Handler

    private func handleAppleSignIn(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .success(let authorization):
            guard let appleIDCredential = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let identityTokenData = appleIDCredential.identityToken,
                  let idToken = String(data: identityTokenData, encoding: .utf8),
                  let nonce = currentNonce else {
                return
            }

            Task {
                await authService.signInWithApple(idToken: idToken, nonce: nonce)
            }

        case .failure(let error):
            // User cancelled or other error
            if (error as NSError).code != ASAuthorizationError.canceled.rawValue {
                authService.authError = "Apple sign-in failed: \(error.localizedDescription)"
            }
        }
    }

    // MARK: - Google Sign In Handler

    private func handleGoogleSignIn() {
        // Get the root view controller for Google Sign-In presentation
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let rootViewController = windowScene.windows.first?.rootViewController else {
            authService.authError = "Unable to find root view controller"
            return
        }

        GIDSignIn.sharedInstance.signIn(withPresenting: rootViewController) { result, error in
            if let error = error {
                if (error as NSError).code != GIDSignInError.canceled.rawValue {
                    authService.authError = "Google sign-in failed: \(error.localizedDescription)"
                }
                return
            }

            guard let user = result?.user,
                  let idToken = user.idToken?.tokenString else {
                authService.authError = "Google sign-in failed: missing token"
                return
            }

            let accessToken = user.accessToken.tokenString

            Task {
                await authService.signInWithGoogle(idToken: idToken, accessToken: accessToken)
            }
        }
    }
}

#Preview {
    SignInView()
        .environment(AuthService())
}
