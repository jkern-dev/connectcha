import Foundation
import Supabase
import Observation
import UIKit
import UserNotifications

/// Spec 10: registration (asked last in onboarding), device token upload,
/// foreground presentation and deep links. On a simulator the "token" is the
/// simulator's UDID so the demo bridge can deliver with `simctl push`.
@MainActor
@Observable
final class NotificationManager: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationManager()

    private(set) var authorization: UNAuthorizationStatus = .notDetermined
    /// Where a tapped notification wants the app to go.
    var pendingDeepLink: DeepLink?

    enum DeepLink: Equatable {
        case people
        case profile(UUID)
        case post(UUID)
        case conversation(UUID)
        case home
    }

    private override init() {
        super.init()
    }

    func install() {
        UNUserNotificationCenter.current().delegate = self
        Task { await refreshStatus() }
    }

    func refreshStatus() async {
        authorization = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    /// Spec 9.1 step 7: the system prompt, asked last.
    @discardableResult
    func requestAuthorization() async -> Bool {
        let granted = (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        await refreshStatus()
        if granted { registerForRemotePushes() }
        return granted
    }

    func registerForRemotePushes() {
        #if targetEnvironment(simulator)
        if let udid = ProcessInfo.processInfo.environment["SIMULATOR_UDID"] {
            Task { await upload(token: "sim:\(udid)", platform: "ios_simulator") }
        }
        #else
        UIApplication.shared.registerForRemoteNotifications()
        #endif
    }

    /// Called from the app delegate with the APNs token on a real device.
    /// A Debug build from Xcode carries the development push entitlement and
    /// gets a sandbox token; TestFlight and App Store builds get a production
    /// one. The server sends to the matching APNs host per token (D-33).
    func didRegister(deviceToken: Data) {
        let hex = deviceToken.map { String(format: "%02x", $0) }.joined()
        #if DEBUG
        let platform = "ios_sandbox"
        #else
        let platform = "ios"
        #endif
        Task { await upload(token: hex, platform: platform) }
    }

    nonisolated struct TokenParams: Encodable, Sendable {
        let pToken: String; let pPlatform: String
        enum CodingKeys: String, CodingKey { case pToken = "p_token", pPlatform = "p_platform" }
    }
    nonisolated struct UnregisterParams: Encodable, Sendable {
        let pToken: String
        enum CodingKeys: String, CodingKey { case pToken = "p_token" }
    }

    private var lastUploaded: String?

    private func upload(token: String, platform: String) async {
        guard API.shared.client.auth.currentSession != nil else { return }
        try? await API.shared.call("register_device_token", TokenParams(pToken: token, pPlatform: platform))
        lastUploaded = token
    }

    /// On sign-out the token must stop pointing at this account.
    func unregister() async {
        if let token = lastUploaded {
            try? await API.shared.call("unregister_device_token", UnregisterParams(pToken: token))
            lastUploaded = nil
        }
    }

    /// Re-register on every launch while authorised (tokens can rotate).
    func registerIfAuthorized() async {
        await refreshStatus()
        if authorization == .authorized || authorization == .provisional { registerForRemotePushes() }
    }

    // MARK: UNUserNotificationCenterDelegate (nonisolated entry points)

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .badge]
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let userInfo = response.notification.request.content.userInfo
        guard let payload = PushPayload(userInfo: userInfo) else { return }
        let link: DeepLink
        switch payload.kind {
        case .followRequest: link = .people
        case .requestApproved: link = payload.actorId.map { .profile($0) } ?? .people
        case .message: link = payload.conversationId.map { .conversation($0) } ?? .home
        case .bellPost: link = payload.postId.map { .post($0) } ?? .home
        case .bellStory: link = .home
        }
        await MainActor.run { self.pendingDeepLink = link }
    }
}
