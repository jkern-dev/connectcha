import XCTest

/// Runs against the local Supabase stack with a fixed-code test number.
/// Covers spec 9.1 steps 1 to 3 and the "non-US number refused" rule (S10).
final class SignUpFlowUITests: XCTestCase {
    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-ui-testing", "-reset-session"]
        app.launchEnvironment["CONNECTCHA_DEMO"] = "0"
        app.launch()
        return app
    }

    @MainActor
    func testSignUpToTabBar() throws {
        let app = launch()

        let phone = app.textFields["Phone number"]
        XCTAssertTrue(phone.waitForExistence(timeout: 15), "phone entry should appear when signed out")
        phone.tap()
        phone.typeText("5550000008")

        let textMe = app.buttons["Text me the code"]
        XCTAssertTrue(textMe.isEnabled)
        textMe.tap()

        let code = app.textFields["Six digit code"]
        XCTAssertTrue(code.waitForExistence(timeout: 15))
        code.tap()
        code.typeText("123456")

        // Either the name step (first sign-up) or the photo step (returning) or the tab bar.
        let first = app.textFields["First name"]
        let choosePhoto = app.buttons["Choose a photo"]
        let tabBar = app.tabBars.firstMatch
        let appeared = NSPredicate(format: "exists == true")
        let expectation = XCTNSPredicateExpectation(predicate: appeared, object: first)
        let photoExpectation = XCTNSPredicateExpectation(predicate: appeared, object: choosePhoto)
        let tabExpectation = XCTNSPredicateExpectation(predicate: appeared, object: tabBar)
        _ = XCTWaiter.wait(for: [expectation, photoExpectation, tabExpectation], timeout: 20, enforceOrder: false)

        if first.exists {
            first.tap()
            first.typeText("Nia")
            let last = app.textFields["Last name"]
            last.tap()
            last.typeText("Newcomer")
            app.buttons["Continue"].tap()
        }
        if choosePhoto.waitForExistence(timeout: 10) {
            app.buttons["Skip for now"].tap()
        }
        // Steps 4 to 7 on a device that has not finished them: decline each.
        var hops = 0
        while !tabBar.exists && hops < 8 {
            if app.buttons["Not now"].waitForExistence(timeout: 4) { app.buttons["Not now"].tap() }
            else if app.buttons["Skip for now"].exists { app.buttons["Skip for now"].tap() }
            else if app.buttons["Done"].exists { app.buttons["Done"].tap() }
            else if app.buttons["Continue"].exists { app.buttons["Continue"].tap() }
            hops += 1
            _ = tabBar.waitForExistence(timeout: 3)
        }
        XCTAssertTrue(tabBar.waitForExistence(timeout: 20), "signed-in users land on the tab bar")
        XCTAssertTrue(app.tabBars.buttons["Home"].exists)
        XCTAssertTrue(app.tabBars.buttons["People"].exists)
        XCTAssertTrue(app.tabBars.buttons["You"].exists)
        XCTAssertEqual(app.tabBars.buttons.count, 3, "three tabs: Share and Letters live in Home's top bar")
    }

    @MainActor
    func testNonUSNumberIsRefusedBeforeAnyCode() throws {
        let app = launch()
        let phone = app.textFields["Phone number"]
        XCTAssertTrue(phone.waitForExistence(timeout: 15))
        // The field only accepts US digits; a non-US shape (area code starting
        // with 0) never enables the button, so no code request is ever sent.
        phone.tap()
        phone.typeText("0447700900")
        XCTAssertFalse(app.buttons["Text me the code"].isEnabled)
        let message = app.staticTexts.containing(NSPredicate(format: "label CONTAINS[c] 'US phone number'")).firstMatch
        XCTAssertTrue(message.waitForExistence(timeout: 5))
    }

    @MainActor
    func testWrongCodeShowsPlainMessage() throws {
        let app = launch()
        let phone = app.textFields["Phone number"]
        XCTAssertTrue(phone.waitForExistence(timeout: 15))
        phone.tap()
        phone.typeText("5550000009")
        app.buttons["Text me the code"].tap()
        let code = app.textFields["Six digit code"]
        XCTAssertTrue(code.waitForExistence(timeout: 15))
        code.tap()
        code.typeText("000000")
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS[c] 'code'")).firstMatch.waitForExistence(timeout: 15))
    }
}
