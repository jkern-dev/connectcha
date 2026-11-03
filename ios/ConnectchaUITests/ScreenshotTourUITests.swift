import XCTest

/// Not a scenario test: walks the main screens as Josh and attaches a
/// screenshot of each, so a reviewer can look at every screen in one result
/// bundle (used for the refinement passes). Skipped unless CONNECTCHA_TOUR=1.
/// With CONNECTCHA_TOUR_LARGE_TEXT=1 the app runs at the largest accessibility
/// text size.
final class ScreenshotTourUITests: XCTestCase {
    @MainActor
    private func snap(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    @MainActor
    private func back(_ app: XCUIApplication) {
        app.navigationBars.buttons.element(boundBy: 0).tap()
    }

    @MainActor
    func testTour() throws {
        guard ProcessInfo.processInfo.environment["CONNECTCHA_TOUR"] == "1" else { throw XCTSkip("tour only") }
        let app = XCUIApplication()
        app.launchArguments += ["-ui-testing", "-reset-session"]
        if ProcessInfo.processInfo.environment["CONNECTCHA_TOUR_LARGE_TEXT"] == "1" {
            app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        }
        app.launchEnvironment["CONNECTCHA_DEMO"] = "1"
        app.launchEnvironment["CONNECTCHA_AUTO_SIGNIN"] = "15550000001"
        app.launchEnvironment["CONNECTCHA_START_TAB"] = "home"
        app.launch()
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let allow = springboard.buttons["Allow"].firstMatch
        if allow.waitForExistence(timeout: 8) { allow.tap() }

        XCTAssertTrue(app.staticTexts["Connectcha"].waitForExistence(timeout: 30))
        sleep(3)
        snap(app, "01-home")

        // A snapshot (Mom's).
        let trayItems = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'story.'"))
        if trayItems.matching(NSPredicate(format: "label BEGINSWITH 'Mom'")).firstMatch.waitForExistence(timeout: 10) {
            trayItems.matching(NSPredicate(format: "label BEGINSWITH 'Mom'")).firstMatch.tap()
            sleep(2)
            snap(app, "02-snapshot")
            if app.buttons["Close"].exists { app.buttons["Close"].tap() }
        }

        // Found it lovely, from Josh's own photo.
        let hike = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Hike with the dogs'")).firstMatch
        var swipes = 0
        while !hike.exists && swipes < 6 { app.swipeUp(); swipes += 1 }
        if hike.exists {
            snap(app, "03-home-scrolled")
            let count = app.buttons["post.likeCount.mine"].firstMatch
            if count.exists { count.tap(); sleep(2); snap(app, "04-found-it-lovely"); app.buttons["Done"].tap() }
        }
        app.swipeDown(); app.swipeDown(); app.swipeDown()

        // Share sheet, both kinds.
        app.buttons["Share"].firstMatch.tap()
        sleep(2)
        snap(app, "05-share-photos")
        app.buttons["Snapshot"].firstMatch.tap()
        sleep(1)
        snap(app, "06-share-snapshot")
        app.buttons["Cancel"].tap()

        // Letters and a conversation.
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Letters'")).firstMatch.tap()
        sleep(3)
        snap(app, "07-letters")
        let mom = app.staticTexts["Mom"].firstMatch
        if mom.waitForExistence(timeout: 10) { mom.tap(); sleep(3); snap(app, "08-conversation"); back(app) }
        back(app)

        // People and someone's page.
        app.tabBars.buttons["People"].tap()
        sleep(3)
        snap(app, "09-people")
        let priya = app.staticTexts["Priya Nair"].firstMatch
        if priya.exists { priya.tap(); sleep(3); snap(app, "10-someones-page-asked"); back(app) }
        app.tabBars.buttons["Home"].tap()
        let ana = app.staticTexts["Ana Silva"].firstMatch
        if ana.waitForExistence(timeout: 5) { ana.tap(); sleep(3); snap(app, "11-someones-page-following"); back(app) }

        // You, Lately, lists, past snapshots, edit, settings.
        app.tabBars.buttons["You"].tap()
        sleep(3)
        snap(app, "12-you")
        app.buttons["Lately"].tap()
        sleep(3)
        snap(app, "13-lately")
        back(app)
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'People who follow you'")).firstMatch.tap()
        sleep(2)
        snap(app, "14-people-who-follow-you")
        back(app)
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Past snapshots'")).firstMatch.tap()
        sleep(3)
        snap(app, "15-past-snapshots")
        back(app)
        app.buttons["Change your photo or words"].tap()
        sleep(2)
        snap(app, "16-edit")
        app.buttons["Cancel"].tap()
        app.buttons["Settings"].tap()
        sleep(2)
        snap(app, "17-settings")
    }

    /// The signed-out screen.
    @MainActor
    func testSignInTour() throws {
        guard ProcessInfo.processInfo.environment["CONNECTCHA_TOUR"] == "1" else { throw XCTSkip("tour only") }
        let app = XCUIApplication()
        app.launchArguments += ["-ui-testing", "-reset-session"]
        app.launchEnvironment["CONNECTCHA_DEMO"] = "0"
        app.launch()
        XCTAssertTrue(app.textFields["Phone number"].waitForExistence(timeout: 20))
        sleep(1)
        snap(app, "00-sign-in")
    }
}
