import Foundation
import Supabase
@testable import Connectcha

/// Signs a fixed-code test number in, retrying when GoTrue's per-number OTP
/// rate limit fires (tests sign in as several people in quick succession).
@MainActor
enum TestSignIn {
    static func signIn(_ phone: String) async throws {
        let auth = API.shared.client.auth
        try? await auth.signOut()
        MediaCache.shared.clearAll()
        for attempt in 0..<5 {
            do {
                try await auth.signInWithOTP(phone: phone)
                break
            } catch {
                if attempt == 4 { throw error }
                try await Task.sleep(for: .seconds(2))
            }
        }
        try await auth.verifyOTP(phone: phone, token: "123456", type: .sms)
    }

    static func signOut() async {
        try? await API.shared.client.auth.signOut()
        MediaCache.shared.clearAll()
    }
}
