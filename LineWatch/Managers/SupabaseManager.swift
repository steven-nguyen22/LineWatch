//
//  SupabaseManager.swift
//  LineWatch
//
//  Created by Steven Nguyen on 4/18/26.
//

import Foundation
import Supabase

/// Single shared SupabaseClient for the entire app.
/// Using one instance ensures both AuthService and SupabaseService share the same
/// Keychain-backed session, so authenticated requests automatically carry the user JWT.
enum SupabaseManager {
    static let shared = SupabaseClient(
        supabaseURL: URL(string: "https://voxokcdwctpvzbqigklw.supabase.co")!,
        supabaseKey: "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InZveG9rY2R3Y3RwdnpicWlna2x3Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzQ2NTg4ODYsImV4cCI6MjA5MDIzNDg4Nn0.lGh1rKpR8kt3MPJnSe4VXdR_b1mmOT9x6xLvFmhiPnw"
    )
}
