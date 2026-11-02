import XCTest

/// Not a scenario test: walks the main screens as Josh and attaches a
/// screenshot of each, so a reviewer can look at every screen in one result
/// bundle (used for the refinement passes). Skipped unless CONNECTCHA_TOUR=1.
final class ScreenshotTourUITests: XCTestCase {
    @MainActor
    private func snap(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    @MainActor
    func testTour() throws {
        guard ProcessInfo.processInfo.environment["CONNECTCHA_TOUR"] == "1" else { throw XCTSkip("tour only") }
        let app = XCUIApplication()
        app.launchArguments += ["-ui-testing", "-reset-session"]
        app.launchEnvironment["CONNECTCHA_DEMO"] = "1"
        app.launchEnvironment["CONNECTCHA_AUTO_SIGNIN"] = "15550000001"
        app.launchEnvironment["CONNECTCHA_START_TAB"] = "home"
        app.launch()
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let allow = springboard.buttons["Allow"].firstMatch
        if allow.waitForExistence(timeout: 8) { allow.tap() }

        XCTAssertTrue(app.navigationBars["Connectcha"].waitForExistence(timeout: 30))
        sleep(3)
        snap(app, "01-home")

        // Story viewer (Mom's story).
        let trayItems = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'story.'"))
        if trayItems.matching(NSPredicate(format: "label BEGINSWITH 'Mom'")).firstMatch.waitForExistence(timeout: 10) {
            trayItems.matching(NSPredicate(format: "label BEGINSWITH 'Mom'")).firstMatch.tap()
            sleep(2)
            snap(app, "02-story-viewer")
            if app.buttons["Close"].exists { app.buttons["Close"].tap() }
        }

        // Post detail from the feed.
        let hike = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Hike with the dogs'")).firstMatch
        var swipes = 0
        while !hike.exists && swipes < 6 { app.swipeUp(); swipes += 1 }
        if hike.exists {
            let count = app.buttons["post.likeCount.mine"].firstMatch
            if count.exists { count.tap(); sleep(2); snap(app, "03-likers"); app.buttons["Done"].tap() }
        }
        app.swipeDown(); app.swipeDown(); app.swipeDown()

        // Activity.
        app.buttons["Activity"].tap()
        sleep(3)
        snap(app, "04-activity")
        app.navigationBars.buttons.element(boundBy: 0).tap()

        // People.
        app.tabBars.buttons["People"].tap()
        sleep(3)
        snap(app, "05-people")
        let priya = app.staticTexts["Priya Nair"].firstMatch
        if priya.exists { priya.tap(); sleep(3); snap(app, "06-profile-other-requested"); app.navigationBars.buttons.element(boundBy: 0).tap() }

        // Create.
        app.tabBars.buttons["Create"].tap()
        sleep(1)
        snap(app, "07-create")
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'New post'")).firstMatch.tap()
        sleep(2)
        snap(app, "08-new-post")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'New story'")).firstMatch.tap()
        sleep(2)
        snap(app, "09-new-story")
        if app.buttons["Cancel"].exists { app.buttons["Cancel"].tap() } else { app.navigationBars.buttons.element(boundBy: 0).tap() }

        // Inbox and a conversation.
        app.tabBars.buttons["Inbox"].tap()
        sleep(3)
        snap(app, "10-inbox")
        let mom = app.staticTexts["Mom"].firstMatch
        if mom.waitForExistence(timeout: 10) { mom.tap(); sleep(3); snap(app, "11-conversation"); app.navigationBars.buttons.element(boundBy: 0).tap() }

        // Profile, lists, archive, edit, settings.
        app.tabBars.buttons["Profile"].tap()
        sleep(3)
        snap(app, "12-profile")
        app.buttons.matching(NSPredicate(format: "label CONTAINS 'followers'")).firstMatch.tap()
        sleep(2)
        snap(app, "13-followers")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.buttons["Story archive"].tap()
        sleep(3)
        snap(app, "14-archive")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.buttons["Edit profile"].tap()
        sleep(2)
        snap(app, "15-edit-profile")
        app.buttons["Cancel"].tap()
        app.buttons["Settings"].tap()
        sleep(2)
        snap(app, "16-settings")
    }
}
