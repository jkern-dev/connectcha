import XCTest

/// Story scenarios on the local stack with the demo seed (S14, S2 for stories).
final class StoriesUITests: XCTestCase {
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

    /// Mom follows Josh and has her own active story: her story comes first (A3),
    /// Josh's story opens in the viewer under the saved name, and a reaction sends.
    @MainActor
    func testTrayOrderAndViewerReaction() throws {
        let app = launch(as: "15550000002")
        let mine = app.buttons["story.mine"]
        XCTAssertTrue(mine.waitForExistence(timeout: 30), "own story is in the tray")
        let trayItems = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'story.'"))
        let josh = trayItems.matching(NSPredicate(format: "label BEGINSWITH 'Josh'")).firstMatch
        XCTAssertTrue(josh.waitForExistence(timeout: 10), "Josh's story is in the tray")
        XCTAssertEqual(trayItems.element(boundBy: 0).identifier, "story.mine", "own story first")

        josh.tap()
        // A photo story shows for five seconds, so act straight away.
        let react = app.buttons["React ❤️"]
        XCTAssertTrue(react.waitForExistence(timeout: 15), "viewer opened with reactions for a follower")
        react.tap()
        XCTAssertTrue(app.staticTexts["Josh"].exists, "viewer header shows the saved name")
        XCTAssertTrue(app.textFields.matching(NSPredicate(format: "placeholderValue == 'Reply to Josh'")).firstMatch.exists)
        XCTAssertTrue(app.staticTexts["Sent ❤️"].waitForExistence(timeout: 4))
        // After the last story the viewer closes by itself and the tray is back.
        XCTAssertTrue(mine.waitForExistence(timeout: 15))
    }

    /// S2 for stories: a pending requester sees no stories at all.
    @MainActor
    func testPendingRequesterSeesNoStories() throws {
        let app = launch(as: "15550000008")
        // Nia's feed is empty; the tray shows only her own "add" slot.
        XCTAssertTrue(app.staticTexts["Your feed is empty for now"].waitForExistence(timeout: 30))
        XCTAssertFalse(app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'story, '")).firstMatch.exists, "no stories from anyone")
        XCTAssertTrue(app.buttons["Add to your story"].exists)
    }

    /// S14: Josh's expired story is not in anyone's tray but is in his archive;
    /// his active story shows "Seen by 2" and names the viewers.
    @MainActor
    func testExpiredStoryOnlyInArchiveAndSeenBy() throws {
        var app = launch(as: "15550000006")   // Priya follows Josh
        let trayItems = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'story.'"))
        XCTAssertTrue(trayItems.firstMatch.waitForExistence(timeout: 30), "the tray loaded")
        let josh = trayItems.matching(NSPredicate(format: "label BEGINSWITH 'Josh'")).firstMatch
        XCTAssertTrue(josh.waitForExistence(timeout: 10), "Josh's story is in Priya's tray")
        josh.tap()
        XCTAssertTrue(app.staticTexts["Josh Kern"].waitForExistence(timeout: 15))
        // Only the active story plays; one tap forward leaves Josh's group.
        app.buttons["Next story"].tap()
        let stillJosh = app.staticTexts["Josh Kern"].waitForExistence(timeout: 2)
        XCTAssertFalse(stillJosh && app.buttons["Close"].exists && app.textFields.matching(NSPredicate(format: "placeholderValue == 'Reply to Josh Kern'")).firstMatch.exists,
                       "the expired story must not play after the active one")
        if app.buttons["Close"].exists { app.buttons["Close"].tap() }

        app.terminate()
        app = launch(as: "15550000001", tab: "profile")
        XCTAssertTrue(app.navigationBars["Profile"].waitForExistence(timeout: 30))
        app.buttons["Story archive"].tap()
        XCTAssertTrue(app.navigationBars["Story archive"].waitForExistence(timeout: 10))
        let archived = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Story from'"))
        XCTAssertTrue(archived.firstMatch.waitForExistence(timeout: 15))
        XCTAssertEqual(archived.count, 2, "active and expired stories are both in the archive")
        XCTAssertEqual(archived.matching(NSPredicate(format: "label CONTAINS 'active'")).count, 1)

        // Seen-by list on the active story.
        archived.matching(NSPredicate(format: "label CONTAINS 'active'")).firstMatch.tap()
        let seenBy = app.buttons["story.seenBy"]
        XCTAssertTrue(seenBy.waitForExistence(timeout: 15))
        XCTAssertTrue(seenBy.label.contains("2"), "two people viewed it in the seed")
        seenBy.tap()
        XCTAssertTrue(app.navigationBars["Seen by"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Mom"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Priya Nair"].exists)
    }
}
