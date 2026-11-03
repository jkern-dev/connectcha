import XCTest

/// People tab scenarios on the local stack with demo contacts (D-10).
/// Runs as Josh (+1 555 000 0001) with auto sign-in.
final class PeopleUITests: XCTestCase {
    private func launchAsJosh(contacts: ContactsChoice) -> XCUIApplication {
        let app = XCUIApplication()
        app.resetAuthorizationStatus(for: .contacts)
        app.launchArguments += ["-ui-testing", "-reset-session"]
        app.launchEnvironment["CONNECTCHA_DEMO"] = "1"
        app.launchEnvironment["CONNECTCHA_AUTO_SIGNIN"] = "15550000001"
        app.launchEnvironment["CONNECTCHA_START_TAB"] = "people"
        app.launch()

        // Contacts access was never asked on this install: the tab shows the explainer.
        let find = app.buttons["Find people"]
        XCTAssertTrue(find.waitForExistence(timeout: 30), "People tab should offer to find people")
        find.tap()
        answerContactsPrompt(contacts)
        return app
    }

    enum ContactsChoice { case allow, deny }

    private func answerContactsPrompt(_ choice: ContactsChoice) {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let allow = springboard.buttons["Allow Full Access"].firstMatch
        let allowLegacy = springboard.buttons["Allow"].firstMatch
        let deny = springboard.buttons["Don’t Allow"].firstMatch
        let denyAscii = springboard.buttons["Don't Allow"].firstMatch
        let appeared = NSPredicate(format: "exists == true")
        _ = XCTWaiter.wait(for: [
            XCTNSPredicateExpectation(predicate: appeared, object: allow),
            XCTNSPredicateExpectation(predicate: appeared, object: allowLegacy),
        ], timeout: 10, enforceOrder: false)
        switch choice {
        case .allow:
            // iOS 26: an alert with "Continue", then a sheet with "Share All N Contacts".
            // Older systems: "Allow Full Access" then a confirmation.
            for _ in 0..<4 {
                let shareAll = springboard.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Share All'")).firstMatch
                let candidates = [shareAll] + ["Continue", "Allow Full Access", "Allow", "OK"].map { springboard.buttons[$0].firstMatch }
                guard let button = candidates.first(where: { $0.waitForExistence(timeout: 3) }) else { break }
                button.tap()
            }
        case .deny:
            if deny.exists { deny.tap() } else if denyAscii.exists { denyAscii.tap() }
        }
    }

    /// S7: a contact appears under the saved name; S9: a non-US contact's Invite
    /// shows the country-code message and opens no composer.
    @MainActor
    func testSavedNamesAndNonUSInvite() throws {
        let app = launchAsJosh(contacts: .allow)

        // Dad's pending request is shown under the saved name "Dad", not "Robert Kern".
        let dad = app.staticTexts["Dad"]
        XCTAssertTrue(dad.waitForExistence(timeout: 30))
        XCTAssertFalse(app.staticTexts["Robert Kern"].exists)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'In your contacts'")).firstMatch.exists)

        // Non-US contact: tapping Invite shows the message and no composer.
        let lucia = app.buttons["Invite Lucía Fernández"]
        var tries = 0
        while !lucia.exists && tries < 12 {
            app.swipeUp()
            tries += 1
        }
        XCTAssertTrue(lucia.waitForExistence(timeout: 5), "non-US contacts stay in the invite list")
        lucia.tap()
        XCTAssertTrue(app.alerts["Not available yet"].waitForExistence(timeout: 5), "S9: country-code message")
        XCTAssertTrue(app.alerts.staticTexts.containing(NSPredicate(format: "label CONTAINS 'country code'")).firstMatch.exists)
        app.alerts.buttons["OK"].tap()
        XCTAssertFalse(app.navigationBars["New Message"].exists, "no Messages composer for a non-US contact")
    }

    /// S17: with contacts denied the user can still approve a request.
    @MainActor
    func testDeniedContactsStillAllowsApproving() throws {
        let app = launchAsJosh(contacts: .deny)

        XCTAssertTrue(app.staticTexts["Contacts access is off"].waitForExistence(timeout: 20))
        // Dad's request is still there (under the profile name, since no contacts are readable).
        XCTAssertTrue(app.staticTexts["Robert Kern"].waitForExistence(timeout: 20))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Not in contacts'")).firstMatch.exists)
        XCTAssertTrue(app.buttons["request.approve"].exists)
        XCTAssertTrue(app.buttons["request.decline"].exists)
        // No discovery surface without contacts.
        XCTAssertFalse(app.staticTexts["People you know"].exists)
        // Sharing stays available.
        app.tabBars.buttons["Home"].tap()
        XCTAssertTrue(app.buttons["Share"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["Share"].isEnabled)
    }
}
