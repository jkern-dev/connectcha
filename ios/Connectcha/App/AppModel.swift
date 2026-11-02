import Foundation
import Observation
import Supabase
import UserNotifications

/// Top-level state: who is signed in, whether onboarding is finished, and the
/// shared counts used for tab badges. One instance lives for the app's life.
@Observable
@MainActor
final class AppModel {
    enum Phase: Equatable {
        case loading
        case signedOut
        case onboarding
        case ready
    }

    private(set) var phase: Phase = .loading
    private(set) var me: Me?
    var unread = UnreadCounts(unreadConversations: 0, pendingRequests: 0)

    /// Set when the server rejects the session (for example after a sign-out
    /// elsewhere) so the UI can explain instead of silently bouncing.
    var banner: String?

    private var authTask: Task<Void, Never>?

    var userId: UUID? { me?.id }

    func start() {
        guard authTask == nil else { return }
        authTask = Task { [weak self] in
            guard let self else { return }
            #if DEBUG
            if CommandLine.arguments.contains("-reset-onboarding") {
                for key in UserDefaults.standard.dictionaryRepresentation().keys where key.hasPrefix("onboarding.complete.") {
                    UserDefaults.standard.removeObject(forKey: key)
                }
            }
            if CommandLine.arguments.contains("-reset-session") {
                try? await API.shared.client.auth.signOut()
                ContactSync.shared.signedOut()
                MediaCache.shared.clearAll()
                UserDefaults.standard.removeObject(forKey: "demo.seededForPhone")
            }
            // Demo convenience: CONNECTCHA_AUTO_SIGNIN=15550000001 signs in with
            // the fixed-code test number when nobody is signed in (DEBUG only).
            if let phone = ProcessInfo.processInfo.environment["CONNECTCHA_AUTO_SIGNIN"], !phone.isEmpty,
               API.shared.client.auth.currentSession == nil {
                let e164 = phone.hasPrefix("+") ? phone : "+" + phone
                try? await API.shared.client.auth.signInWithOTP(phone: e164)
                try? await API.shared.client.auth.verifyOTP(phone: e164, token: "123456", type: .sms)
            }
            #endif
            for await (event, session) in API.shared.client.auth.authStateChanges {
                switch event {
                case .initialSession, .signedIn, .tokenRefreshed, .userUpdated:
                    if session != nil {
                        await self.loadMe()
                    } else {
                        self.phase = .signedOut
                        self.me = nil
                    }
                case .signedOut:
                    self.me = nil
                    self.phase = .signedOut
                default:
                    break
                }
            }
        }
    }

    /// Fetches the own profile and routes to onboarding or the app.
    func loadMe() async {
        do {
            let me: Me = try await API.shared.rpc("get_me")
            self.me = me
            ContactSync.shared.prepare(for: me.id)
            #if DEBUG
            // Demo personas arrive fully set up; skip the per-device steps.
            if me.onboarded, ProcessInfo.processInfo.environment["CONNECTCHA_AUTO_SIGNIN"] != nil {
                OnboardingProgress.markComplete(for: me.id)
            }
            #endif
            if !me.onboarded || !OnboardingProgress.isComplete(for: me.id) {
                phase = .onboarding
            } else {
                phase = .ready
                await NotificationManager.shared.registerIfAuthorized()
                #if DEBUG
                // Demo personas skip onboarding, so ask for notifications here once.
                if ProcessInfo.processInfo.environment["CONNECTCHA_AUTO_SIGNIN"] != nil,
                   NotificationManager.shared.authorization == .notDetermined {
                    await NotificationManager.shared.requestAuthorization()
                }
                #endif
            }
        } catch {
            let apiError = APIError(error)
            if apiError.code == "offline", me != nil {
                // Keep showing what we have.
                return
            }
            if apiError.code == "not_signed_in" || apiError.underlying.contains("401") {
                await signOut()
            } else {
                banner = apiError.message
                phase = me == nil ? .signedOut : phase
            }
        }
    }

    func refreshMe() async {
        if let me: Me = try? await API.shared.rpc("get_me") {
            self.me = me
        }
    }

    func refreshUnread() async {
        if let counts: UnreadCounts = try? await API.shared.rpc("get_unread_counts") {
            unread = counts
        }
    }

    func finishOnboarding() {
        if let id = me?.id { OnboardingProgress.markComplete(for: id) }
        phase = .ready
        Task { await NotificationManager.shared.registerIfAuthorized() }
    }

    func signOut() async {
        await NotificationManager.shared.unregister()
        try? await API.shared.client.auth.signOut()
        ContactSync.shared.signedOut()
        MediaCache.shared.clearAll()
        me = nil
        phase = .signedOut
    }
}

/// Which onboarding steps this device has finished for a user. Server-side
/// "onboarded" only covers the name step; the rest is per device.
enum OnboardingProgress {
    static func key(_ id: UUID) -> String { "onboarding.complete.\(id.uuidString)" }
    static func isComplete(for id: UUID) -> Bool { UserDefaults.standard.bool(forKey: key(id)) }
    static func markComplete(for id: UUID) { UserDefaults.standard.set(true, forKey: key(id)) }
    static func reset(for id: UUID) { UserDefaults.standard.removeObject(forKey: key(id)) }
}
