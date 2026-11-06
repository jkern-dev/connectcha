import XCTest

/// Settings on the local stack. Expects a freshly reset database with the
/// seeded fresh user (`make ios-ui-test` creates +1 555 000 0008 before each class).
final class SettingsUITests: XCTestCase {
    @MainActor private func launch(as phone: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-ui-testing", "-reset-session"]
        app.launchEnvironment["CONNECTCHA_DEMO"] = "1"
        app.launchEnvironment["CONNECTCHA_AUTO_SIGNIN"] = phone
        app.launchEnvironment["CONNECTCHA_START_TAB"] = "you"
        app.launch()
        return app
    }

    @MainActor private func scrollTo(_ element: XCUIElement, in app: XCUIApplication, maxSwipes: Int = 6) -> Bool {
        var swipes = 0
        while !element.exists && swipes < maxSwipes {
            app.swipeUp()
            swipes += 1
        }
        return element.waitForExistence(timeout: 3)
    }

    /// D-34: deleting the account from Settings lands on sign-in, and the
    /// deleted number can no longer sign in to the old account (a fresh
    /// sign-up starts onboarding instead of the tabs).
    @MainActor
    func testDeleteAccountFromSettings() throws {
        let app = launch(as: "15550000008")
        XCTAssertTrue(app.tabBars.buttons["You"].waitForExistence(timeout: 30))
        app.buttons["Settings"].tap()

        let delete = app.descendants(matching: .any)["settings.deleteAccount"].firstMatch
        XCTAssertTrue(scrollTo(delete, in: app))
        delete.tap()
        let confirm = app.sheets.buttons["Delete my account"].firstMatch
        if confirm.waitForExistence(timeout: 3) { confirm.tap() } else { app.buttons["Delete my account"].firstMatch.tap() }

        XCTAssertTrue(app.textFields["Phone number"].waitForExistence(timeout: 20), "deletion returns to sign-in")

        // Signing in again with the same number is a brand-new account: the name step, not the tabs.
        let phone = app.textFields["Phone number"]
        phone.tap()
        phone.typeText("5550000008")
        app.buttons["Text me the code"].tap()
        let code = app.textFields["Six digit code"]
        XCTAssertTrue(code.waitForExistence(timeout: 15))
        code.tap()
        code.typeText("123456")
        XCTAssertTrue(app.textFields["First name"].waitForExistence(timeout: 20), "the old account is gone; onboarding starts over")
        XCTAssertFalse(app.tabBars.buttons["You"].exists)
    }
}
