import XCTest

final class LaunchTests: XCTestCase {
    @MainActor
    func testLaunchShowsTabBar() throws {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 10))
    }
}
