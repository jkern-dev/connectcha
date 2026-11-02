import XCTest

/// Not a scenario test: a helper the demo script can run to answer the system
/// notification prompt on a simulator (`scripts/demo.sh` uses it so banners
/// work without the owner tapping). Skipped unless CONNECTCHA_HELPER=allow.
final class DemoHelperUITests: XCTestCase {
    @MainActor
    func testAllowNotificationsPrompt() throws {
        guard ProcessInfo.processInfo.environment["CONNECTCHA_HELPER"] == "allow" else { throw XCTSkip("helper only") }
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let allow = springboard.buttons["Allow"].firstMatch
        if allow.waitForExistence(timeout: 5) { allow.tap(); return }
        let app = XCUIApplication()
        app.launchEnvironment["CONNECTCHA_DEMO"] = "1"
        app.launchEnvironment["CONNECTCHA_AUTO_SIGNIN"] = ProcessInfo.processInfo.environment["CONNECTCHA_HELPER_NUMBER"] ?? "15550000001"
        app.launch()
        if allow.waitForExistence(timeout: 20) { allow.tap() }
    }
}
