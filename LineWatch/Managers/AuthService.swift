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
import RevenueCat

@Observable
class AuthService {
    var isAuthenticated = false
    var authError: String?
    var subscriptionTier: SubscriptionTier = .rookie
    var trialEndsAt: Date? = nil
    var trialAcknowledged: Bool = false

    init() {
        // Hydrate trial state from cache for instant UI on launch
        if let cachedTier = UserDefaults.standard.string(forKey: "cached_subscription_tier"),
           let tier = SubscriptionTier(rawValue: cachedTier) {
            subscriptionTier = tier
        }
        let cachedEnds = UserDefaults.standard.double(forKey: "cached_trial_ends_at")
        if cachedEnds > 0 {
            trialEndsAt = Date(timeIntervalSince1970: cachedEnds)
        }
        trialAcknowledged = UserDefaults.standard.bool(forKey: "cached_trial_acknowledged")
    }

    // MARK: - Trial / Effective Tier

    /// True while the user is inside an active 7-day trial and hasn't paid for an upgrade.
    var isOnTrial: Bool {
        guard let endsAt = trialEndsAt, subscriptionTier == .rookie else { return false }
        return endsAt > Date()
    }

    /// True once the trial end date has passed (regardless of acknowledgement).
    var trialExpired: Bool {
        guard let endsAt = trialEndsAt else { return false }
        return endsAt <= Date()
    }

    /// True when we should show the post-trial paywall as a fullScreenCover —
    /// trial is over, user hasn't acknowledged it yet, and they're still on rookie.
    var needsPostTrialPaywall: Bool {
        trialExpired && !trialAcknowledged && subscriptionTier == .rookie
    }

    /// The tier the app should treat the user as. During an active trial this
    /// returns `.hallOfFame` even though the DB row says `rookie`.
    var effectiveTier: SubscriptionTier {
        isOnTrial ? .hallOfFame : subscriptionTier
    }

    /// Whole days remaining in the active trial, or nil if not on trial.
    var trialDaysRemaining: Int? {
        guard let endsAt = trialEndsAt, isOnTrial else { return nil }
        return Calendar.current.dateComponents([.day], from: Date(), to: endsAt).day
    }

    // MARK: - Session Management

    /// Check for an existing session on app launch (restores from Keychain automatically)
    func restoreSession() async {
        do {
            let session = try await SupabaseManager.shared.auth.session
            await MainActor.run {
                isAuthenticated = (session.user.id != nil)
            }
            if session.user.id != nil {
                await fetchProfile()
                await syncRevenueCatIdentity()
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
            let session = try await SupabaseManager.shared.auth.signUp(
                email: email,
                password: password,
                data: ["full_name": .string(name)]
            )
            await MainActor.run {
                isAuthenticated = true
                authError = nil
            }
            await fetchProfile()
            await syncRevenueCatIdentity()
        } catch {
            await MainActor.run {
                authError = error.localizedDescription
            }
        }
    }

    // MARK: - Email/Password Sign In

    func signIn(email: String, password: String) async {
        do {
            let session = try await SupabaseManager.shared.auth.signIn(
                email: email,
                password: password
            )
            await MainActor.run {
                isAuthenticated = true
                authError = nil
            }
            await fetchProfile()
            await syncRevenueCatIdentity()
        } catch {
            await MainActor.run {
                authError = error.localizedDescription
            }
        }
    }

    // MARK: - Sign In with Apple

    func signInWithApple(idToken: String, nonce: String) async {
        do {
            let session = try await SupabaseManager.shared.auth.signInWithIdToken(
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
            await fetchProfile()
            await syncRevenueCatIdentity()
        } catch {
            await MainActor.run {
                authError = "Apple sign-in failed: \(error.localizedDescription)"
            }
        }
    }

    // MARK: - Sign In with Google

    func signInWithGoogle(idToken: String, rawNonce: String) async {
        do {
            let session = try await SupabaseManager.shared.auth.signInWithIdToken(
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
            await fetchProfile()
            await syncRevenueCatIdentity()
        } catch {
            await MainActor.run {
                authError = "Google sign-in failed: \(error.localizedDescription)"
            }
        }
    }

    // MARK: - Sign Out

    func signOut() async {
        do {
            try await SupabaseManager.shared.auth.signOut()
            _ = try? await Purchases.shared.logOut()
            UserDefaults.standard.removeObject(forKey: "cached_subscription_tier")
            UserDefaults.standard.removeObject(forKey: "cached_trial_ends_at")
            UserDefaults.standard.removeObject(forKey: "cached_trial_acknowledged")
            NotificationManager.shared.cancelTrialReminders()
            await MainActor.run {
                isAuthenticated = false
                subscriptionTier = .rookie
                trialEndsAt = nil
                trialAcknowledged = false
            }
        } catch {
            await MainActor.run {
                authError = "Sign out failed: \(error.localizedDescription)"
            }
        }
    }

    // MARK: - Profile / Subscription

    /// Fetch the user's profile (tier + trial state) from Supabase.
    /// Caches results in UserDefaults and schedules/cancels trial notifications.
    func fetchProfile() async {
        // Try cached value first for instant UI
        if let cached = UserDefaults.standard.string(forKey: "cached_subscription_tier"),
           let tier = SubscriptionTier(rawValue: cached) {
            await MainActor.run {
                subscriptionTier = tier
            }
        }

        do {
            let session = try await SupabaseManager.shared.auth.session
            let userId = session.user.id

            struct ProfileRow: Decodable {
                let subscriptionTier: String
                let trialEndsAt: Date?
                let trialAcknowledged: Bool

                enum CodingKeys: String, CodingKey {
                    case subscriptionTier = "subscription_tier"
                    case trialEndsAt = "trial_ends_at"
                    case trialAcknowledged = "trial_acknowledged"
                }
            }

            let row: ProfileRow = try await SupabaseManager.shared
                .from("profiles")
                .select("subscription_tier, trial_ends_at, trial_acknowledged")
                .eq("id", value: userId)
                .single()
                .execute()
                .value

            let tier = SubscriptionTier(rawValue: row.subscriptionTier) ?? .rookie
            UserDefaults.standard.set(tier.rawValue, forKey: "cached_subscription_tier")

            if let endsAt = row.trialEndsAt {
                UserDefaults.standard.set(endsAt.timeIntervalSince1970, forKey: "cached_trial_ends_at")
            } else {
                UserDefaults.standard.removeObject(forKey: "cached_trial_ends_at")
            }
            UserDefaults.standard.set(row.trialAcknowledged, forKey: "cached_trial_acknowledged")

            await MainActor.run {
                subscriptionTier = tier
                trialEndsAt = row.trialEndsAt
                trialAcknowledged = row.trialAcknowledged
            }

            // Schedule or cancel local trial reminders based on current state
            if isOnTrial, let endsAt = trialEndsAt {
                NotificationManager.shared.scheduleTrialReminders(endsAt: endsAt)
            } else {
                NotificationManager.shared.cancelTrialReminders()
            }
        } catch {
            // Silent failure — keep cached or default tier
        }
    }

    /// Mark the post-trial paywall as acknowledged so it doesn't appear again.
    /// Called when the user taps "Continue with Rookie" or selects a paid tier.
    func acknowledgeTrialPaywall() async {
        do {
            let session = try await SupabaseManager.shared.auth.session
            try await SupabaseManager.shared
                .from("profiles")
                .update(["trial_acknowledged": true])
                .eq("id", value: session.user.id)
                .execute()
            UserDefaults.standard.set(true, forKey: "cached_trial_acknowledged")
            await MainActor.run {
                trialAcknowledged = true
            }
        } catch {
            // Silent fail — flip local state anyway so the user isn't stuck
            UserDefaults.standard.set(true, forKey: "cached_trial_acknowledged")
            await MainActor.run {
                trialAcknowledged = true
            }
        }
    }

    // MARK: - RevenueCat Identity

    /// Log the current Supabase user into RevenueCat so their purchases are tied
    /// to their account across devices. If RC reports an entitlement higher than
    /// what Supabase has, reconcile by writing the RC-derived tier back to Supabase.
    func syncRevenueCatIdentity() async {
        do {
            let session = try await SupabaseManager.shared.auth.session
            let userId = session.user.id.uuidString
            let (customerInfo, _) = try await Purchases.shared.logIn(userId)

            // Derive tier from active entitlements (HoF > Pro > Rookie).
            let active = customerInfo.entitlements.active
            let rcTier: SubscriptionTier
            if active["hall_of_fame"] != nil {
                rcTier = .hallOfFame
            } else if active["pro"] != nil {
                rcTier = .pro
            } else {
                rcTier = .rookie
            }

            // If RC has a higher tier than Supabase (cross-device purchase), reconcile.
            if rcTier > subscriptionTier {
                await updateSubscriptionTier(rcTier)
            }
        } catch {
            // Silent — RC sync is best-effort
        }
    }

    /// Persist a new subscription tier to Supabase after a successful purchase.
    func updateSubscriptionTier(_ tier: SubscriptionTier) async {
        do {
            let session = try await SupabaseManager.shared.auth.session
            try await SupabaseManager.shared
                .from("profiles")
                .update(["subscription_tier": tier.rawValue])
                .eq("id", value: session.user.id)
                .execute()
        } catch {
            // Silent — still flip local state so the user sees their upgrade
        }
        UserDefaults.standard.set(tier.rawValue, forKey: "cached_subscription_tier")
        await MainActor.run {
            subscriptionTier = tier
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
