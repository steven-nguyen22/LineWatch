//
//  AuthService.swift
//  LineWatch
//
//  Created by Steven Nguyen on 3/27/26.
//

import Foundation
import Supabase
import AuthenticationServices
import CryptoKit
import GoogleSignIn

@Observable
class AuthService {
    var isAuthenticated = false
    var authError: String?
    var subscriptionTier: SubscriptionTier = .rookie

    private let supabase: SupabaseClient

    init() {
        supabase = SupabaseClient(
            supabaseURL: URL(string: "https://voxokcdwctpvzbqigklw.supabase.co")!,
            supabaseKey: "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InZveG9rY2R3Y3RwdnpicWlna2x3Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzQ2NTg4ODYsImV4cCI6MjA5MDIzNDg4Nn0.lGh1rKpR8kt3MPJnSe4VXdR_b1mmOT9x6xLvFmhiPnw"
        )
    }

    // MARK: - Session Management

    /// Check for an existing session on app launch (restores from Keychain automatically)
    func restoreSession() async {
        do {
            let session = try await supabase.auth.session
            await MainActor.run {
                isAuthenticated = (session.user.id != nil)
            }
            if session.user.id != nil {
                await fetchSubscriptionTier()
            }
        } catch {
            await MainActor.run {
                isAuthenticated = false
            }
        }
    }

    // MARK: - Email/Password Sign Up

    func signUp(email: String, password: String, name: String) async {
        do {
            let session = try await supabase.auth.signUp(
                email: email,
                password: password,
                data: ["full_name": .string(name)]
            )
            await MainActor.run {
                isAuthenticated = true
                authError = nil
            }
            await fetchSubscriptionTier()
        } catch {
            await MainActor.run {
                authError = error.localizedDescription
            }
        }
    }

    // MARK: - Email/Password Sign In

    func signIn(email: String, password: String) async {
        do {
            let session = try await supabase.auth.signIn(
                email: email,
                password: password
            )
            await MainActor.run {
                isAuthenticated = true
                authError = nil
            }
            await fetchSubscriptionTier()
        } catch {
            await MainActor.run {
                authError = error.localizedDescription
            }
        }
    }

    // MARK: - Sign In with Apple

    func signInWithApple(idToken: String, nonce: String) async {
        do {
            let session = try await supabase.auth.signInWithIdToken(
                credentials: .init(
                    provider: .apple,
                    idToken: idToken,
                    nonce: nonce
                )
            )
            await MainActor.run {
                isAuthenticated = true
                authError = nil
            }
            await fetchSubscriptionTier()
        } catch {
            await MainActor.run {
                authError = "Apple sign-in failed: \(error.localizedDescription)"
            }
        }
    }

    // MARK: - Sign In with Google

    func signInWithGoogle(idToken: String, rawNonce: String) async {
        do {
            let session = try await supabase.auth.signInWithIdToken(
                credentials: OpenIDConnectCredentials(
                    provider: .google,
                    idToken: idToken,
                    nonce: rawNonce
                )
            )
            await MainActor.run {
                isAuthenticated = true
                authError = nil
            }
            await fetchSubscriptionTier()
        } catch {
            await MainActor.run {
                authError = "Google sign-in failed: \(error.localizedDescription)"
            }
        }
    }

    // MARK: - Sign Out

    func signOut() async {
        do {
            try await supabase.auth.signOut()
            UserDefaults.standard.removeObject(forKey: "cached_subscription_tier")
            await MainActor.run {
                isAuthenticated = false
                subscriptionTier = .rookie
            }
        } catch {
            await MainActor.run {
                authError = "Sign out failed: \(error.localizedDescription)"
            }
        }
    }

    // MARK: - Subscription Tier

    /// Fetch the user's subscription tier from the Supabase profiles table
    func fetchSubscriptionTier() async {
        // Try cached value first for instant UI
        if let cached = UserDefaults.standard.string(forKey: "cached_subscription_tier"),
           let tier = SubscriptionTier(rawValue: cached) {
            await MainActor.run {
                subscriptionTier = tier
            }
        }

        do {
            let session = try await supabase.auth.session
            let userId = session.user.id

            struct ProfileRow: Decodable {
                let subscriptionTier: String

                enum CodingKeys: String, CodingKey {
                    case subscriptionTier = "subscription_tier"
                }
            }

            let row: ProfileRow = try await supabase
                .from("profiles")
                .select("subscription_tier")
                .eq("id", value: userId)
                .single()
                .execute()
                .value

            if let tier = SubscriptionTier(rawValue: row.subscriptionTier) {
                UserDefaults.standard.set(tier.rawValue, forKey: "cached_subscription_tier")
                await MainActor.run {
                    subscriptionTier = tier
                }
            }
        } catch {
            // Silent failure — keep cached or default tier
        }
    }

    // MARK: - Nonce Helpers (for Apple & Google Sign In)

    /// Generate a random nonce string for Apple/Google Sign In
    static func randomNonceString(length: Int = 32) -> String {
        precondition(length > 0)
        var randomBytes = [UInt8](repeating: 0, count: length)
        let errorCode = SecRandomCopyBytes(kSecRandomDefault, randomBytes.count, &randomBytes)
        if errorCode != errSecSuccess {
            fatalError("Unable to generate nonce. SecRandomCopyBytes failed with OSStatus \(errorCode)")
        }
        let charset: [Character] = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        return String(randomBytes.map { charset[Int($0) % charset.count] })
    }

    /// SHA256 hash a string (used for Apple Sign In nonce)
    static func sha256(_ input: String) -> String {
        let inputData = Data(input.utf8)
        let hashedData = SHA256.hash(data: inputData)
        return hashedData.compactMap { String(format: "%02x", $0) }.joined()
    }
}
