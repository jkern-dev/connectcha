import XCTest

/// Messaging scenarios (S12, S13) on the local stack with the demo seed.
final class MessagingUITests: XCTestCase {
    @MainActor
    private func launch(as phone: String, tab: String = "home") -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-ui-testing", "-reset-session"]
        app.launchEnvironment["CONNECTCHA_DEMO"] = "1"
        app.launchEnvironment["CONNECTCHA_AUTO_SIGNIN"] = phone
        app.launchEnvironment["CONNECTCHA_START_TAB"] = tab
        app.launch()
        return app
    }

    @MainActor
    private func scrollTo(_ element: XCUIElement, in app: XCUIApplication, maxSwipes: Int = 8) -> Bool {
        var swipes = 0
        while !element.exists && swipes < maxSwipes { app.swipeUp(); swipes += 1 }
        return element.waitForExistence(timeout: 3)
    }

    /// S12: Dad responds to Mom's post; only Mom and Dad have the conversation,
    /// Josh (who also follows Mom) sees nothing of it, and the conversation
    /// carries a post preview.
    @MainActor
    func testResponseIsPrivateToThePair() throws {
        var app = launch(as: "15550000003")   // Dad follows Mom
        let message = app.buttons["Message Linda about this post"].firstMatch
        XCTAssertTrue(scrollTo(message, in: app), "the input under Mom's post reads 'Message Linda' (Dad's saved name)")
        message.tap()
        let field = app.textFields.matching(NSPredicate(format: "placeholderValue BEGINSWITH 'Message '")).firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        field.tap()
        field.typeText("Those tomatoes look great")
        app.buttons["Send"].tap()
        XCTAssertFalse(field.waitForExistence(timeout: 5), "compose screen closes after sending")

        // Dad's inbox has the conversation with a post preview.
        app.tabBars.buttons["Inbox"].tap()
        XCTAssertTrue(app.staticTexts["Linda"].waitForExistence(timeout: 15))
        app.staticTexts["Linda"].tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Responding to'")).firstMatch.waitForExistence(timeout: 10), "post preview")

        // Josh follows Mom too but never sees Dad's response.
        app.terminate()
        app = launch(as: "15550000001", tab: "inbox")
        XCTAssertTrue(app.navigationBars["Inbox"].waitForExistence(timeout: 30))
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'tomatoes look great'")).firstMatch.exists)
        XCTAssertFalse(app.staticTexts["Dad"].exists, "no conversation with Dad about Mom's post")

        // Mom sees it and can reply even though... she does follow Dad; either way it's private to the pair.
        app.terminate()
        app = launch(as: "15550000002", tab: "inbox")
        let robert = app.staticTexts["Robert"]
        XCTAssertTrue(robert.waitForExistence(timeout: 30), "Mom's inbox shows Dad under her saved name")
        robert.tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'tomatoes look great'")).firstMatch.waitForExistence(timeout: 10))
    }

    /// S13: when neither person follows the other, the conversation stays
    /// readable but nothing new can be sent.
    @MainActor
    func testReadOnlyWhenNoFollowRemains() throws {
        // Ana and Josh follow each other and have a conversation in the seed.
        var app = launch(as: "15550000004", tab: "inbox")
        XCTAssertTrue(app.staticTexts["Josh Kern"].waitForExistence(timeout: 30))
        app.staticTexts["Josh Kern"].tap()
        let composer = app.textViews["conversation.composer"].firstMatch.exists ? app.textViews["conversation.composer"].firstMatch : app.textFields["conversation.composer"].firstMatch
        XCTAssertTrue(composer.waitForExistence(timeout: 10), "composer is available while a follow exists")

        // Ana unfollows Josh and removes him as a follower.
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.tabBars.buttons["Profile"].tap()
        app.buttons.matching(NSPredicate(format: "label CONTAINS 'following'")).firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Josh Kern"].waitForExistence(timeout: 15))
        app.staticTexts["Josh Kern"].swipeLeft()
        app.buttons["Unfollow"].firstMatch.tap()
        if app.sheets.buttons["Unfollow"].firstMatch.waitForExistence(timeout: 3) { app.sheets.buttons["Unfollow"].firstMatch.tap() }
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.buttons.matching(NSPredicate(format: "label CONTAINS 'followers'")).firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Josh Kern"].waitForExistence(timeout: 15))
        app.staticTexts["Josh Kern"].swipeLeft()
        app.buttons["Remove"].firstMatch.tap()
        if app.sheets.buttons["Remove"].firstMatch.waitForExistence(timeout: 3) { app.sheets.buttons["Remove"].firstMatch.tap() }

        // The conversation is still there, read only.
        app.tabBars.buttons["Inbox"].tap()
        XCTAssertTrue(app.staticTexts["Josh Kern"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.staticTexts["Read only"].exists)
        app.staticTexts["Josh Kern"].tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'Inverness'")).firstMatch.waitForExistence(timeout: 10), "old messages stay readable")
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'You can read this conversation'")).firstMatch.exists)
        XCTAssertFalse(app.textFields["conversation.composer"].exists)
        XCTAssertFalse(app.textViews["conversation.composer"].exists)

        // Same for Josh.
        app.terminate()
        app = launch(as: "15550000001", tab: "inbox")
        XCTAssertTrue(app.staticTexts["Ana Silva"].waitForExistence(timeout: 30))
        app.staticTexts["Ana Silva"].tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'You can read this conversation'")).firstMatch.waitForExistence(timeout: 10))
    }
}
