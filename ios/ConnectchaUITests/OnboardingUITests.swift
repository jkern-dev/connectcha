import XCTest

/// Spec 9.1 end to end on a fresh account, in the spec's order, with the
/// notifications prompt last (M9 acceptance). Uses +1 555 000 0009.
final class OnboardingUITests: XCTestCase {
    @MainActor
    func testFullOnboardingInOrder() throws {
        let app = XCUIApplication()
        app.resetAuthorizationStatus(for: .contacts)
        app.launchArguments += ["-ui-testing", "-reset-session", "-reset-onboarding"]
        app.launchEnvironment["CONNECTCHA_DEMO"] = "1"
        app.launch()

        // 1. Phone number and code.
        let phone = app.textFields["Phone number"]
        XCTAssertTrue(phone.waitForExistence(timeout: 20))
        XCTAssertTrue(app.links["Terms"].exists || app.buttons["Terms"].exists, "terms linked on the first screen")
        XCTAssertTrue(app.links["Privacy Policy"].exists || app.buttons["Privacy Policy"].exists)
        phone.tap(); phone.typeText("5550000009")
        app.buttons["Text me the code"].tap()
        let code = app.textFields["Six digit code"]
        XCTAssertTrue(code.waitForExistence(timeout: 15))
        code.tap(); code.typeText("123456")

        // 2. Name (both required).
        let first = app.textFields["First name"]
        let photo = app.buttons["Choose a photo"]
        _ = XCTWaiter.wait(for: [
            XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == true"), object: first),
            XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == true"), object: photo),
        ], timeout: 20, enforceOrder: false)
        if first.exists {
            XCTAssertFalse(app.buttons["Continue"].isEnabled, "Continue stays off without a name")
            first.tap(); first.typeText("Sasha")
            XCTAssertFalse(app.buttons["Continue"].isEnabled, "last name is required too")
            app.textFields["Last name"].tap(); app.textFields["Last name"].typeText("Spare")
            app.buttons["Continue"].tap()
        }

        // 3. Photo (optional).
        XCTAssertTrue(photo.waitForExistence(timeout: 15))
        app.buttons["Skip for now"].tap()

        // 4. Contacts explanation, then the system prompt.
        let findPeople = app.buttons["Find people"]
        XCTAssertTrue(findPeople.waitForExistence(timeout: 15), "contacts step explains before asking")
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'stay on your phone'")).firstMatch.exists)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS \"aren't kept\"")).firstMatch.exists)
        findPeople.tap()
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        for _ in 0..<4 {
            let shareAll = springboard.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Share All'")).firstMatch
            let candidates = [shareAll] + ["Continue", "Allow Full Access", "Allow", "OK"].map { springboard.buttons[$0].firstMatch }
            guard let button = candidates.first(where: { $0.waitForExistence(timeout: 3) }) else { break }
            button.tap()
        }

        // 5. People you know: checklist, nothing preselected, one send button with a count.
        let sendRequests = app.buttons["Send requests"]
        let continueButton = app.buttons["Continue"]
        _ = XCTWaiter.wait(for: [
            XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == true"), object: sendRequests),
            XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == true"), object: continueButton),
        ], timeout: 30, enforceOrder: false)
        if sendRequests.exists {
            XCTAssertFalse(sendRequests.isEnabled, "nothing is preselected (C1)")
            XCTAssertEqual(app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'select all' OR label CONTAINS[c] 'request all'")).count, 0)
            let josh = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Josh Kern'")).firstMatch
            XCTAssertTrue(josh.waitForExistence(timeout: 10))
            josh.tap()
            XCTAssertTrue(app.buttons["Send 1 request"].waitForExistence(timeout: 5), "the button shows the count")
            app.buttons["Send 1 request"].tap()
        } else {
            continueButton.tap()
        }

        // 6. Invites with an easy skip.
        let done = app.buttons["Done"]
        let cont = app.buttons["Continue"]
        _ = XCTWaiter.wait(for: [
            XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == true"), object: done),
            XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == true"), object: cont),
        ], timeout: 20, enforceOrder: false)
        XCTAssertTrue(app.staticTexts["Invite people"].exists, "invite step comes after people you know")
        if done.exists { done.tap() } else { cont.tap() }

        // 7. Notifications, asked last.
        XCTAssertTrue(app.buttons["Turn on notifications"].waitForExistence(timeout: 15), "notifications are asked last")
        app.buttons["Not now"].tap()

        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 20))
    }
}
