import XCTest

/// Following scenarios on the local stack. Expects a freshly reset database
/// (`make reset`) and the demo contacts (CONNECTCHA_DEMO=1).
final class FollowingUITests: XCTestCase {
    @MainActor private func launch(as phone: String, tab: String = "people") -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-ui-testing", "-reset-session"]
        app.launchEnvironment["CONNECTCHA_DEMO"] = "1"
        app.launchEnvironment["CONNECTCHA_AUTO_SIGNIN"] = phone
        app.launchEnvironment["CONNECTCHA_START_TAB"] = tab
        app.launch()
        return app
    }

    /// Scrolls the current screen until the element exists (lazy lists only expose visible rows).
    @MainActor private func scrollTo(_ element: XCUIElement, in app: XCUIApplication, maxSwipes: Int = 6) -> Bool {
        var swipes = 0
        while !element.exists && swipes < maxSwipes {
            app.swipeUp()
            swipes += 1
        }
        return element.waitForExistence(timeout: 3)
    }

    /// Fails if any phone-number-looking text is on screen (S3: numbers never shown).
    @MainActor private func assertNoPhoneNumbers(_ app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        let predicate = NSPredicate(format: "label MATCHES '.*555[- ]?000[- ]?00\\\\d\\\\d.*'")
        XCTAssertEqual(app.staticTexts.matching(predicate).count, 0, "a phone number is visible", file: file, line: line)
    }

    @MainActor private func signOut(_ app: XCUIApplication) {
        app.tabBars.buttons["You"].tap()
        app.buttons["Settings"].tap()
        let signOut = app.descendants(matching: .any)["settings.signOut"].firstMatch
        XCTAssertTrue(scrollTo(signOut, in: app))
        signOut.tap()
        let confirm = app.sheets.buttons["Sign out"].firstMatch
        if confirm.waitForExistence(timeout: 3) { confirm.tap() } else { app.buttons["Sign out"].firstMatch.tap() }
        XCTAssertTrue(app.textFields["Phone number"].waitForExistence(timeout: 15))
    }

    @MainActor private func signIn(_ app: XCUIApplication, digits: String) {
        let phone = app.textFields["Phone number"]
        XCTAssertTrue(phone.waitForExistence(timeout: 15))
        phone.tap()
        phone.typeText(digits)
        app.buttons["Text me the code"].tap()
        let code = app.textFields["Six digit code"]
        XCTAssertTrue(code.waitForExistence(timeout: 15))
        code.tap()
        code.typeText("123456")
        // Returning personas skip straight to the tabs; a first-time device may show the photo step.
        let tabBar = app.tabBars.firstMatch
        let skip = app.buttons["Skip for now"]
        _ = XCTWaiter.wait(for: [
            XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == true"), object: tabBar),
            XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == true"), object: skip),
        ], timeout: 20, enforceOrder: false)
        var hops = 0
        while !tabBar.exists && hops < 6 {
            if app.buttons["Skip for now"].exists { app.buttons["Skip for now"].tap() }
            else if app.buttons["Not now"].exists { app.buttons["Not now"].tap() }
            else if app.buttons["Continue"].exists { app.buttons["Continue"].tap() }
            else if app.buttons["Done"].exists { app.buttons["Done"].tap() }
            hops += 1
            _ = tabBar.waitForExistence(timeout: 3)
        }
        XCTAssertTrue(tabBar.waitForExistence(timeout: 15))
        app.tabBars.buttons["People"].tap()
    }

    /// S1, S2, S16 as a new user (Nia, +1 555 000 0008) who has Josh in her contacts.
    @MainActor
    func testMinimalProfileHiddenCountsAndNoStrangers() throws {
        let app = launch(as: "15550000008")

        // S1: Ben is not in Nia's contacts and must not appear anywhere.
        XCTAssertTrue(app.staticTexts["Your circle"].waitForExistence(timeout: 30))
        XCTAssertFalse(app.staticTexts["Ben Carter"].exists)
        XCTAssertEqual(app.searchFields.count, 0, "there is no search anywhere")

        // Open Josh from People you know.
        let josh = app.staticTexts["Josh Kern"]
        XCTAssertTrue(josh.waitForExistence(timeout: 30))
        josh.tap()
        XCTAssertTrue(app.navigationBars["Josh Kern"].waitForExistence(timeout: 10))

        // S2: minimal profile only: no bio, no posts, a request button.
        XCTAssertFalse(app.staticTexts["Dad of two, weekend hiker."].exists, "bio is hidden before approval")
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Post by'")).count, 0, "no posts before approval")
        // S16: no counts for another person.
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label MATCHES[c] '^\\d+ (followers|following)$' OR label IN {'Followers', 'Following'}")).firstMatch.exists)
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "label MATCHES[c] '^\\d+ (followers|following)$'")).count, 0)
        assertNoPhoneNumbers(app)

        let request = app.buttons["Ask to follow"]
        let requested = app.buttons["Asked"]
        if request.waitForExistence(timeout: 5) {
            request.tap()
        }
        XCTAssertTrue(requested.waitForExistence(timeout: 10), "a pending requester sees Asked")
        // Still minimal while pending.
        XCTAssertFalse(app.staticTexts["Dad of two, weekend hiker."].exists)
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Post by'")).count, 0)
    }

    /// S3: Ana (has Ben's number) requests Ben; Ben approves and is offered a
    /// follow-back; Ana must approve before Ben sees anything. No numbers shown.
    @MainActor
    func testFollowBackFlow() throws {
        let app = launch(as: "15550000004")
        XCTAssertTrue(app.staticTexts["Your circle"].waitForExistence(timeout: 30))
        let ben = app.staticTexts["Ben Carter"]
        XCTAssertTrue(ben.waitForExistence(timeout: 30), "Ana has Ben in her contacts")
        let requestBen = app.buttons["Ask to follow Ben Carter"]
        if requestBen.exists { requestBen.tap() }
        XCTAssertTrue(app.buttons["Asked"].waitForExistence(timeout: 10))
        assertNoPhoneNumbers(app)

        // Ben's turn.
        signOut(app)
        signIn(app, digits: "5550000005")
        let ana = app.staticTexts["Ana Silva"]
        XCTAssertTrue(ana.waitForExistence(timeout: 30), "Ben sees Ana's request under her profile name")
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Not in contacts'")).firstMatch.exists, "Ben doesn't have Ana's number")
        assertNoPhoneNumbers(app)
        app.buttons["request.approve"].firstMatch.tap()
        let followBack = app.buttons["Ask to follow Ana Silva"]
        XCTAssertTrue(followBack.waitForExistence(timeout: 15), "after approving, Ben is offered a follow-back")
        followBack.tap()
        // Ben does not follow Ana yet: her profile shows Requested, no posts.
        // (Ana is reachable from Ben's followers list.)
        app.tabBars.buttons["You"].tap()
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'People who follow you'")).firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Ana Silva"].waitForExistence(timeout: 10))
        app.staticTexts["Ana Silva"].tap()
        XCTAssertTrue(app.buttons["Asked"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Post by'")).count, 0, "Ben can't see Ana's posts until she approves")
        assertNoPhoneNumbers(app)

        // Ana's turn: the follow-back request is labelled as such and needs approval.
        signOut(app)
        signIn(app, digits: "5550000004")
        XCTAssertTrue(app.staticTexts["Ben Carter"].waitForExistence(timeout: 30))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'approved you and wants to follow you back'")).firstMatch.exists)
        assertNoPhoneNumbers(app)
        app.buttons["request.approve"].firstMatch.tap()
        // Ana already follows Ben, so no follow-back offer this time.
        XCTAssertFalse(app.buttons["Ask to follow Ben Carter"].waitForExistence(timeout: 3))
    }

    /// S6: deleting the contact keeps the follow and switches to the profile name.
    @MainActor
    func testDeletedContactKeepsFollowAndChangesName() throws {
        let app = launch(as: "15550000001", tab: "you")
        XCTAssertTrue(app.staticTexts["Josh Kern"].waitForExistence(timeout: 30))
        app.buttons["Settings"].tap()
        let demoTools = app.descendants(matching: .any)["settings.demoTools"].firstMatch
        XCTAssertTrue(scrollTo(demoTools, in: app))
        demoTools.tap()
        let delete = app.descendants(matching: .any)["Delete \"Dad\" from Contacts"].firstMatch
        XCTAssertTrue(delete.waitForExistence(timeout: 15))
        delete.tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Deleted.'")).firstMatch.waitForExistence(timeout: 10))

        // Josh still follows him, now under his profile name.
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'People you follow'")).firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Robert Kern"].waitForExistence(timeout: 15), "follow continues under the profile name")
        XCTAssertFalse(app.staticTexts["Dad"].exists)

        // Put the contact back for the other tests and the demo.
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.buttons["Settings"].tap()
        let demoToolsAgain = app.descendants(matching: .any)["settings.demoTools"].firstMatch
        XCTAssertTrue(scrollTo(demoToolsAgain, in: app))
        demoToolsAgain.tap()
        app.descendants(matching: .any)["Re-seed this persona's contacts"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Re-seeded."].waitForExistence(timeout: 15))
    }
}
