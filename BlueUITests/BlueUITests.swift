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
        XCTAssertTrue(app.buttons["closeConfirmation"].waitForExistence(timeout: 5))
        screenshot(app, "delete-modal")
        app.buttons["closeConfirmation"].tap()
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
        let body = app.descendants(matching: .any).matching(identifier: "noteBody").firstMatch
        XCTAssertTrue(body.waitForExistence(timeout: 5))
        body.tap()
        body.typeText("First line\nSecond line")
        app.terminate()
        app = launch(reset: false)
        app.buttons["scope-notes"].tap()
        app.buttons["note-Quiet notes"].tap()
        let reopenedBody = app.descendants(matching: .any).matching(identifier: "noteBody").firstMatch
        XCTAssertTrue(reopenedBody.waitForExistence(timeout: 5))
        XCTAssertEqual(reopenedBody.value as? String, "First line\nSecond line")
        XCTAssertFalse(app.buttons["noteSave"].exists)
        app.buttons["detailOptions"].tap()
        app.buttons["Delete"].tap()
        XCTAssertTrue(app.buttons["closeConfirmation"].waitForExistence(timeout: 5))
        app.buttons["closeConfirmation"].tap()
        XCTAssertTrue(reopenedBody.exists)
        screenshot(app, "plain-note-autosaved")
        app.buttons["askBlue"].tap()
        XCTAssertTrue(app.textFields["assistantInput"].waitForExistence(timeout: 5))
        dismissSheet(app)
        app.buttons["note-Quiet notes"].tap()
        XCTAssertTrue(app.buttons["detailOptions"].waitForExistence(timeout: 5))
        app.buttons["detailOptions"].tap()
        app.buttons["Delete"].tap()
        XCTAssertTrue(app.buttons["confirmDelete"].waitForExistence(timeout: 5))
        app.buttons["confirmDelete"].tap()
        XCTAssertTrue(app.buttons["scope-notes"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["note-Quiet notes"].exists)
        app.terminate()
        app = launch(reset: false)
        app.buttons["scope-notes"].tap()
        XCTAssertFalse(app.buttons["note-Quiet notes"].exists)
    }
    @MainActor func testCollectionSortIconsNumberWheelAndRelaunch() {
        let app = launch()
        app.buttons["collection-template.movies"].tap()
        XCTAssertFalse(app.buttons["quickFilter-__favorite"].exists)
        XCTAssertFalse(app.buttons["scope-notes"].exists)
        let sort = app.buttons["sortDirection"]
        XCTAssertTrue(sort.waitForExistence(timeout: 5))
        sort.tap()
        XCTAssertEqual(sort.value as? String, "Descending")
        sort.tap()
        screenshot(app, "collection-compact-header")
        app.buttons["row-Interstellar"].tap()
        let rating = app.scrollViews["recordEditor"].buttons["property-rating"]
        XCTAssertTrue(rating.waitForExistence(timeout: 5))
        rating.tap()
        let wheel = app.pickerWheels.firstMatch
        XCTAssertTrue(wheel.waitForExistence(timeout: 5))
        wheel.adjust(toPickerWheelValue: "8.5")
        dismissSheet(app)
        XCTAssertEqual(app.scrollViews["recordEditor"].buttons["property-rating"].value as? String, "8.5")
        XCTAssertFalse(app.buttons["recordSave"].exists)
        screenshot(app, "record-visual-properties")
        app.terminate()
        let reopened = launch(reset: false)
        reopened.buttons["collection-template.movies"].tap()
        reopened.buttons["row-Interstellar"].tap()
        XCTAssertEqual(reopened.scrollViews["recordEditor"].buttons["property-rating"].value as? String, "8.5")
    }
    @MainActor func testAssistantSheetReturnAndDraftDismissal() {
        let app = launch()
        let blue = app.buttons["askBlue"]
        XCTAssertGreaterThan(blue.frame.minX, app.buttons["scope-calendar"].frame.maxX)
        blue.tap()
        let input = app.textFields["assistantInput"]
        XCTAssertTrue(input.waitForExistence(timeout: 5))
        input.tap()
        input.typeText("What rating did I give Interstellar?\n")
        XCTAssertTrue(app.buttons["result-Interstellar"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["Close"].exists)
        XCTAssertLessThan(input.frame.midY, app.buttons["result-Interstellar"].frame.midY)
        XCTAssertFalse(app.buttons["scope-notes"].exists)
        screenshot(app, "assistant-result-sheet")
        dismissSheet(app)
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
        XCTAssertTrue(app.buttons["scope-collections"].waitForExistence(timeout: 5))
        screenshot(app, "overview-spanish")
        app.buttons["collection-template.movies"].tap()
        screenshot(app, "collection-spanish")
        for id in ["collectionOptions", "newRecord", "askBlue"] {
            let button = app.buttons[id]
            XCTAssertTrue(button.exists)
            XCTAssertGreaterThanOrEqual(button.frame.height.rounded(), 44, id)
        }
        app.buttons["askBlue"].tap()
        XCTAssertTrue(app.textFields["assistantInput"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["scope-notes"].exists)
        screenshot(app, "assistant-spanish")
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
