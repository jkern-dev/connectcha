import XCTest

/// Spec 10 on the simulator: a response to Josh's post arrives as a banner
/// that names the sender by her saved contact name ("Mom"), while the server
/// payload only ever carried "Linda Kern". Uses the in-app delivery poller
/// (CONNECTCHA_INAPP_PUSH=1); the demo uses scripts/push-bridge.sh instead.
final class NotificationsUITests: XCTestCase {
    private let apiURL = URL(string: "http://127.0.0.1:54321")!
    private let anonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0"

    /// Minimal REST client so the test can act as another person.
    private func call(_ path: String, token: String? = nil, body: [String: Any]) async throws -> Data {
        var request = URLRequest(url: apiURL.appendingPathComponent(path))
        request.httpMethod = "POST"
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "authorization") }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, _) = try await URLSession.shared.data(for: request)
        return data
    }

    private func signIn(_ phone: String) async throws -> String {
        _ = try await call("auth/v1/otp", body: ["phone": phone])
        try await Task.sleep(for: .seconds(1.5))
        let data = try await call("auth/v1/verify", body: ["phone": phone, "token": "123456", "type": "sms"])
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let token = json?["access_token"] as? String else { throw NSError(domain: "test", code: 1) }
        return token
    }

    @MainActor
    func testResponsePushShowsSavedName() async throws {
        let app = XCUIApplication()
        app.launchArguments += ["-ui-testing", "-reset-session"]
        app.launchEnvironment["CONNECTCHA_DEMO"] = "1"
        app.launchEnvironment["CONNECTCHA_AUTO_SIGNIN"] = "15550000001"
        app.launchEnvironment["CONNECTCHA_START_TAB"] = "home"
        app.launchEnvironment["CONNECTCHA_INAPP_PUSH"] = "1"
        app.launch()

        // Josh is asked for notifications once; allow.
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let allow = springboard.buttons["Allow"].firstMatch
        if allow.waitForExistence(timeout: 20) { allow.tap() }
        XCTAssertTrue(app.navigationBars["Connectcha"].waitForExistence(timeout: 30))
        // Give the token registration and contact matching a moment.
        try await Task.sleep(for: .seconds(4))

        // Mom responds to Josh's hike post (server side, as Mom).
        let mom = try await signIn("+15550000002")
        let josh = try await signIn("+15550000001")
        let feedData = try await call("rest/v1/rpc/get_feed", token: josh, body: [:])
        let feed = try JSONSerialization.jsonObject(with: feedData) as? [String: Any]
        let posts = feed?["posts"] as? [[String: Any]] ?? []
        let hike = posts.first { ($0["caption"] as? String)?.hasPrefix("Hike with the dogs") == true }
        let postId = try XCTUnwrap(hike?["id"] as? String)
        _ = try await call("rest/v1/rpc/respond_to_post", token: mom, body: ["p_post_id": postId, "p_body": "Lovely day for it"])

        // The banner names Mom by Josh's saved contact name, never "Linda Kern".
        let banner = springboard.staticTexts.containing(NSPredicate(format: "label CONTAINS 'responded to your post'")).firstMatch
        XCTAssertTrue(banner.waitForExistence(timeout: 30), "a push banner appears")
        XCTAssertTrue(banner.label.contains("Mom"), "saved name on device: \(banner.label)")
        XCTAssertFalse(banner.label.contains("Linda"), "profile name must not leak into the banner when a saved name exists")
        XCTAssertFalse(banner.label.contains("Lovely day"), "message text never appears in a push")

        // Tapping it deep-links into the conversation.
        banner.tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'Lovely day for it'")).firstMatch.waitForExistence(timeout: 20))
    }
}
