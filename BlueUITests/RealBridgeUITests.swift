import XCTest

/// Opt-in genuine Mac model integration. Never runs in normal CI or with the deterministic assistant.
final class RealBridgeUITests: XCTestCase {
    @MainActor func testRealModelReadEditAndRelaunch() {
        let app = XCUIApplication()
        app.launchArguments = ["--uitest", "--uitest-reset"]
        app.launch()
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 20))
        let input = app.textFields["assistantInput"]
        input.tap()
        input.typeText("What rating did I give Interstellar?\n")
        XCTAssertTrue(app.buttons["result-Interstellar"].waitForExistence(timeout: 90))
        app.buttons["result-Interstellar"].tap()
        input.tap()
        input.typeText("Change Interstellar's rating to 9.5.\n")
        XCTAssertTrue(app.buttons["result-Interstellar"].waitForExistence(timeout: 90))
        app.buttons["result-Interstellar"].tap()
        app.buttons["row-Interstellar"].tap()
        XCTAssertEqual(app.textFields["field-rating"].value as? String, "9.5")
        app.terminate()
        app.launchArguments = ["--uitest"]
        app.launch()
        app.buttons["collection-template.movies"].tap()
        let row = app.buttons["row-Interstellar"]
        for _ in 0..<5 {
            if row.isHittable { break }
            app.swipeUp()
        }
        row.tap()
        XCTAssertEqual(app.textFields["field-rating"].value as? String, "9.5")
        let image = XCTAttachment(screenshot: app.screenshot())
        image.name = "real-model-persisted-rating"
        image.lifetime = .keepAlways
        add(image)
    }
}
