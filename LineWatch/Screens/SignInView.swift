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
    @State private var email = ""
    @State private var password = ""
    @State private var currentNonce: String?
    @State private var isLoading = false
    @State private var showSignUp = false

    var body: some View {
        NavigationStack {
            ZStack {
                // Background
                AppColors.backgroundPrimary
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 0) {
                        Spacer().frame(height: 60)

                        // App logo
                        Image("AppLogo")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 100, height: 100)

                        // Logo text: "Line" in white, "Watch" in green
                        LineWatchLogo(size: 36)

                        Text("Sign in to your account")
                            .font(.body)
                            .foregroundStyle(.white.opacity(0.7))
                            .padding(.top, 8)

                        // Email & Password fields
                        VStack(spacing: 16) {
                            AuthTextField(
                                text: $email,
                                placeholder: "ex: jon.smith@email.com",
                                label: "Email",
                                keyboardType: .emailAddress
                            )

                            AuthSecureField(
                                text: $password,
                                placeholder: "********",
                                label: "Password"
                            )
                        }
                        .padding(.top, 32)
                        .padding(.horizontal, 32)

                        // Sign In button
                        Button {
                            isLoading = true
                            Task {
                                await authService.signIn(email: email, password: password)
                                isLoading = false
                            }
                        } label: {
                            Group {
                                if isLoading {
                                    ProgressView()
                                        .tint(.white)
                                } else {
                                    Text("SIGN IN")
                                        .font(.system(size: 17, weight: .bold))
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                            .foregroundStyle(.white)
                            .background(AppColors.primaryGreen)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        .disabled(email.isEmpty || password.isEmpty || isLoading)
                        .opacity(email.isEmpty || password.isEmpty ? 0.6 : 1.0)
                        .padding(.top, 24)
                        .padding(.horizontal, 32)

                        // Divider
                        HStack {
                            Rectangle()
                                .fill(.white.opacity(0.2))
                                .frame(height: 1)
                            Text("or sign in with")
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.5))
                                .fixedSize()
                            Rectangle()
                                .fill(.white.opacity(0.2))
                                .frame(height: 1)
                        }
                        .padding(.top, 24)
                        .padding(.horizontal, 32)

                        // Sign In with Google & Apple buttons
                        VStack(spacing: 12) {
                            // Sign In with Google
                            Button {
                                handleGoogleSignIn()
                            } label: {
                                HStack(spacing: 12) {
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
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                            }

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
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        .padding(.top, 20)
                        .padding(.horizontal, 32)

                        // Error message
                        if let error = authService.authError {
                            Text(error)
                                .font(.caption)
                                .foregroundStyle(.red)
                                .multilineTextAlignment(.center)
                                .padding(.top, 12)
                                .padding(.horizontal, 32)
                        }

                        // Sign Up link
                        HStack(spacing: 4) {
                            Text("Don't have an account?")
                                .foregroundStyle(.white.opacity(0.6))
                            Button("SIGN UP") {
                                showSignUp = true
                            }
                            .foregroundStyle(AppColors.primaryGreen)
                            .fontWeight(.bold)
                        }
                        .font(.subheadline)
                        .padding(.top, 28)
                        .padding(.bottom, 40)
                    }
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .navigationBarHidden(true)
            .navigationDestination(isPresented: $showSignUp) {
                SignUpView()
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
                if authService.isAuthenticated {
                    await NotificationManager.shared.requestAuthorization()
                }
            }

        case .failure(let error):
            if (error as NSError).code != ASAuthorizationError.canceled.rawValue {
                authService.authError = "Apple sign-in failed: \(error.localizedDescription)"
            }
        }
    }

    // MARK: - Google Sign In Handler

    private func handleGoogleSignIn() {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let rootViewController = windowScene.windows.first?.rootViewController else {
            authService.authError = "Unable to find root view controller"
            return
        }

        // Generate a nonce — pass raw to Google SDK, pass raw to Supabase (it hashes internally)
        let rawNonce = AuthService.randomNonceString()
        let hashedNonce = AuthService.sha256(rawNonce)

        GIDSignIn.sharedInstance.signIn(
            withPresenting: rootViewController,
            hint: nil,
            additionalScopes: nil,
            nonce: hashedNonce
        ) { result, error in
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

            Task {
                await authService.signInWithGoogle(idToken: idToken, rawNonce: rawNonce)
                if authService.isAuthenticated {
                    await NotificationManager.shared.requestAuthorization()
                }
            }
        }
    }
}

#Preview {
    SignInView()
        .environment(AuthService())
}
