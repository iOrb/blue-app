import UIKit
import XCTest

final class BlueUITests: XCTestCase {
    @MainActor private func launch(reset: Bool = true) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--uitest", "--test-assistant"] + (reset ? ["--uitest-reset"] : [])
        app.launch()
        XCTAssertTrue(app.buttons["scope-notes"].waitForExistence(timeout: 20))
        return app
    }
    @MainActor private func screenshot(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
    @MainActor private func dismissSheet(_ app: XCUIApplication) {
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.08)).tap()
    }
    @MainActor private func replace(_ field: XCUIElement, _ text: String) {
        field.tap()
        let old = field.value as? String ?? ""
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: old.count) + text)
    }
    @MainActor private func spanish(_ app: XCUIApplication) {
        app.buttons["settingsButton"].tap()
        XCTAssertTrue(app.buttons["languageSpanish"].waitForExistence(timeout: 5))
        app.buttons["languageSpanish"].tap()
        dismissSheet(app)
    }
    @MainActor func testCleanOverviewAndCalendarDaySheet() {
        let app = launch()
        XCTAssertFalse(app.buttons["row-Interstellar"].exists)
        XCTAssertFalse(app.textFields["assistantInput"].exists)
        XCTAssertFalse(app.buttons["scope-favorites"].exists)
        screenshot(app, "overview-english")
        app.buttons["scope-notes"].tap()
        screenshot(app, "notes-titles-only")
        app.buttons["scope-calendar"].tap()
        app.buttons["day-8"].tap()
        XCTAssertTrue(app.otherElements["sheetBackdrop"].waitForExistence(timeout: 5))
        screenshot(app, "calendar-day-sheet")
        dismissSheet(app)
        XCTAssertTrue(app.buttons["newEvent"].isHittable)
        spanish(app)
        screenshot(app, "calendar-spanish")
    }
    @MainActor func testEventAutosaveAndDeleteCancellation() {
        var app = launch()
        app.buttons["scope-calendar"].tap()
        app.buttons["newEvent"].tap()
        let title = app.textFields["eventTitle"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        title.tap()
        title.typeText("Calendar persistence")
        dismissSheet(app)
        app.terminate()
        app = launch(reset: false)
        app.buttons["scope-calendar"].tap()
        let day = Calendar.current.component(.day, from: Date())
        app.buttons["day-\(day)"].tap()
        XCTAssertTrue(
            app.buttons.containing(.staticText, identifier: "Calendar persistence").firstMatch.waitForExistence(
                timeout: 5))
        app.buttons.containing(.staticText, identifier: "Calendar persistence").firstMatch.tap()
        XCTAssertEqual(app.textFields["eventTitle"].value as? String, "Calendar persistence")
        app.buttons["Delete"].tap()
        XCTAssertTrue(app.sheets["Delete this event?"].waitForExistence(timeout: 5))
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.7)).tap()
        XCTAssertTrue(app.textFields["eventTitle"].exists)
        screenshot(app, "event-autosaved")
    }
    @MainActor func testNoteTapEditAutosaveAndRelaunch() {
        var app = launch()
        app.buttons["createMenu"].tap()
        app.buttons["New note"].tap()
        let title = app.textFields["noteTitle"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        replace(title, "Quiet notes")
        app.descendants(matching: .any).matching(identifier: "markdownPreview").firstMatch.tap()
        let body = app.textViews["noteBody"]
        XCTAssertTrue(body.waitForExistence(timeout: 5))
        body.tap()
        body.typeText("# Space\n\n**Keep it simple.**")
        app.terminate()
        app = launch(reset: false)
        app.buttons["scope-notes"].tap()
        app.buttons["note-Quiet notes"].tap()
        XCTAssertTrue(
            app.buttons.matching(identifier: "markdownPreview").matching(
                NSPredicate(format: "label CONTAINS %@", "Space")
            ).firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(app.textViews["noteBody"].exists)
        XCTAssertFalse(app.buttons["noteSave"].exists)
        screenshot(app, "rendered-note-autosaved")
    }
    @MainActor func testCollectionIconsNumberWheelAndFilterRemoval() {
        let app = launch()
        app.buttons["collection-template.movies"].tap()
        let favorite = app.buttons["quickFilter-__favorite"]
        XCTAssertTrue(favorite.waitForExistence(timeout: 5))
        favorite.tap()
        favorite.tap()
        app.buttons["row-Interstellar"].tap()
        let rating = app.buttons["property-rating"]
        XCTAssertTrue(rating.waitForExistence(timeout: 5))
        rating.tap()
        let wheel = app.pickerWheels.firstMatch
        XCTAssertTrue(wheel.waitForExistence(timeout: 5))
        wheel.adjust(toPickerWheelValue: "8.5")
        dismissSheet(app)
        XCTAssertEqual(app.buttons["property-rating"].value as? String, "8.5")
        XCTAssertFalse(app.buttons["recordSave"].exists)
        screenshot(app, "record-visual-properties")
        app.terminate()
        let reopened = launch(reset: false)
        reopened.buttons["collection-template.movies"].tap()
        reopened.buttons["row-Interstellar"].tap()
        XCTAssertEqual(reopened.buttons["property-rating"].value as? String, "8.5")
    }
    @MainActor func testAssistantSheetReturnAndDraftDismissal() {
        let app = launch()
        app.buttons["askBlue"].tap()
        let input = app.textFields["assistantInput"]
        XCTAssertTrue(input.waitForExistence(timeout: 5))
        input.tap()
        input.typeText("What rating did I give Interstellar?\n")
        XCTAssertTrue(app.buttons["result-Interstellar"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["Close"].exists)
        screenshot(app, "assistant-result-sheet")
        app.buttons["scope-notes"].tap()
        XCTAssertFalse(input.exists)
        app.buttons["askBlue"].tap()
        input.tap()
        input.typeText("Unsent draft")
        dismissSheet(app)
        app.buttons["askBlue"].tap()
        XCTAssertEqual(input.value as? String, "Unsent draft")
    }
    @MainActor func testSpanishOverviewAndTouchTargets() {
        let app = launch()
        spanish(app)
        XCTAssertTrue(app.buttons["scope-collections"].exists)
        screenshot(app, "overview-spanish")
        app.buttons["collection-template.movies"].tap()
        screenshot(app, "collection-spanish")
        for id in ["openFilters", "newRecord", "askBlue"] {
            let button = app.buttons[id]
            XCTAssertTrue(button.exists)
            XCTAssertGreaterThanOrEqual(button.frame.height, 44)
        }
    }
    @MainActor func testAccessibilitySizeCalendarAndNotes() {
        let app = XCUIApplication()
        app.launchArguments = [
            "--uitest", "--uitest-reset", "--test-assistant", "-UIPreferredContentSizeCategoryName",
            "UICTContentSizeCategoryAccessibilityXXXL",
        ]
        app.launch()
        XCTAssertTrue(app.buttons["scope-calendar"].waitForExistence(timeout: 20))
        app.buttons["scope-calendar"].tap()
        XCTAssertTrue(app.datePickers.firstMatch.exists)
        screenshot(app, "calendar-accessibility-size")
        app.buttons["scope-notes"].tap()
        screenshot(app, "notes-accessibility-size")
    }

}
