import XCTest

/// Feed scenarios on the local stack with the demo seed.
final class FeedUITests: XCTestCase {
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
        while !element.exists && swipes < maxSwipes {
            app.swipeUp()
            swipes += 1
        }
        return element.waitForExistence(timeout: 3)
    }

    /// S11: the poster can open the list of who liked; a viewer sees only the count.
    @MainActor
    func testLikesCountForViewersNamesForPoster() throws {
        // Josh's "Hike with the dogs" has four likes in the seed.
        var app = launch(as: "15550000001")
        let caption = app.staticTexts.containing(NSPredicate(format: "label BEGINSWITH 'Hike with the dogs'")).firstMatch
        XCTAssertTrue(scrollTo(caption, in: app), "Josh's own post is in his feed")
        let mineCount = app.buttons["post.likeCount.mine"].firstMatch
        XCTAssertTrue(mineCount.exists, "the poster's count is tappable")
        XCTAssertEqual(mineCount.label, "4 found it lovely")
        mineCount.tap()
        XCTAssertTrue(app.navigationBars["Found it lovely"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Mom"].waitForExistence(timeout: 10), "the poster sees names (saved name for a contact)")
        XCTAssertTrue(app.staticTexts["Ana Silva"].exists)
        app.buttons["Done"].tap()

        // Mom views the same post: a count, no list.
        app.terminate()
        app = launch(as: "15550000002")
        let captionForMom = app.staticTexts.containing(NSPredicate(format: "label BEGINSWITH 'Hike with the dogs'")).firstMatch
        XCTAssertTrue(scrollTo(captionForMom, in: app))
        let fourLikesText = app.staticTexts.matching(identifier: "post.likeCount").matching(NSPredicate(format: "label == '4 found it lovely'")).firstMatch
        XCTAssertTrue(fourLikesText.exists, "a viewer sees the count as plain text")
        let fourLikesButton = app.buttons.matching(identifier: "post.likeCount.mine").matching(NSPredicate(format: "label == '4 found it lovely'"))
        XCTAssertEqual(fourLikesButton.count, 0, "a viewer cannot open the list for someone else's post")
        fourLikesText.tap()
        XCTAssertFalse(app.navigationBars["Found it lovely"].waitForExistence(timeout: 2))
    }

    /// S15: a new user sees pending requests and prompts, never filler.
    @MainActor
    func testEmptyFeedShowsRequestsAndPromptsOnly() throws {
        // Nia (+1 555 000 0008) has Josh and Ana in her contacts and follows nobody.
        let app = launch(as: "15550000008", tab: "people")
        // Fresh account: finish the name step if it appears.
        let first = app.textFields["First name"]
        if first.waitForExistence(timeout: 8) {
            first.tap(); first.typeText("Nia")
            app.textFields["Last name"].tap(); app.textFields["Last name"].typeText("Newcomer")
            app.buttons["Continue"].tap()
            if app.buttons["Skip for now"].waitForExistence(timeout: 8) { app.buttons["Skip for now"].tap() }
            if app.buttons["Not now"].waitForExistence(timeout: 8) { app.buttons["Not now"].tap() }
            var hops = 0
            while !app.tabBars.firstMatch.exists && hops < 4 {
                if app.buttons["Continue"].exists { app.buttons["Continue"].tap() }
                if app.buttons["Skip for now"].exists { app.buttons["Skip for now"].tap() }
                if app.buttons["Done"].exists { app.buttons["Done"].tap() }
                hops += 1
                _ = app.tabBars.firstMatch.waitForExistence(timeout: 3)
            }
            app.tabBars.buttons["People"].tap()
        }
        XCTAssertTrue(app.staticTexts["Your circle"].waitForExistence(timeout: 30))
        let requestJosh = app.buttons["Ask to follow Josh Kern"]
        if requestJosh.waitForExistence(timeout: 20) { requestJosh.tap() }
        XCTAssertTrue(app.buttons["Asked"].firstMatch.waitForExistence(timeout: 10))

        app.tabBars.buttons["Home"].tap()
        XCTAssertTrue(app.staticTexts["Nothing on the table yet"].waitForExistence(timeout: 20), "empty state is shown")
        XCTAssertTrue(app.staticTexts["Waiting for their yes"].exists, "pending requests are listed")
        XCTAssertTrue(app.staticTexts["Josh Kern"].exists)
        XCTAssertTrue(app.buttons["Find people you know"].exists)
        XCTAssertTrue(app.buttons["Share your first photo"].exists)
        // No filler: no photo cards, no Lovely buttons.
        XCTAssertEqual(app.buttons.matching(identifier: "Lovely").count, 0)
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Write back'")).count, 0)
    }

    /// S5 at feed level: Priya loses Josh's post the moment he removes her.
    @MainActor
    func testRemovedFollowerLosesFeedAccess() throws {
        var app = launch(as: "15550000006")
        let hike = app.staticTexts.containing(NSPredicate(format: "label BEGINSWITH 'Hike with the dogs'")).firstMatch
        XCTAssertTrue(scrollTo(hike, in: app), "Priya follows Josh and sees his post")

        app.terminate()
        app = launch(as: "15550000001", tab: "you")
        XCTAssertTrue(app.staticTexts["Josh Kern"].waitForExistence(timeout: 30))
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'People who follow you'")).firstMatch.tap()
        let priya = app.staticTexts["Priya Nair"]
        XCTAssertTrue(priya.waitForExistence(timeout: 15))
        priya.swipeLeft()
        app.buttons["Remove"].firstMatch.tap()
        let confirm = app.sheets.buttons["Remove"].firstMatch
        if confirm.waitForExistence(timeout: 3) { confirm.tap() }
        XCTAssertFalse(priya.waitForExistence(timeout: 5), "Priya leaves the follower list")

        app.terminate()
        app = launch(as: "15550000006")
        XCTAssertTrue(app.staticTexts["Connectcha"].waitForExistence(timeout: 30))
        let hikeAgain = app.staticTexts.containing(NSPredicate(format: "label BEGINSWITH 'Hike with the dogs'")).firstMatch
        XCTAssertFalse(scrollTo(hikeAgain, in: app, maxSwipes: 10), "the removed follower no longer sees the post")
        // She was not told: no activity item.
        app.swipeDown(); app.swipeDown(); app.swipeDown()
    }

    /// The caption field is multi-line, so Return adds a line; the keyboard
    /// needs its own way out or it covers Where and the Share button.
    @MainActor
    func testCaptionKeyboardCanBePutAway() throws {
        let app = launch(as: "15550000001", tab: "create")
        let caption = app.descendants(matching: .any).matching(identifier: "share.caption").firstMatch
        XCTAssertTrue(caption.waitForExistence(timeout: 20))
        caption.tap()
        caption.typeText("Back garden")
        let done = app.buttons["Hide keyboard"]
        XCTAssertTrue(done.waitForExistence(timeout: 5))
        done.tap()
        XCTAssertTrue(done.waitForNonExistence(timeout: 5))
        XCTAssertEqual(caption.value as? String, "Back garden")
    }
}
