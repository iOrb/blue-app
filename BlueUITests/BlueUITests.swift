import UIKit
import XCTest

final class BlueUITests: XCTestCase {
    private enum TabItem {
        case notes, collections, calendar, blue

        var names: [String] {
            switch self {
            case .notes: ["Notes", "Notas"]
            case .collections: ["Collections", "Colecciones"]
            case .calendar: ["Calendar", "Calendario"]
            case .blue: ["Tell Blue", "Cuéntaselo a Blue"]
            }
        }
    }
    @MainActor private func tab(_ item: TabItem, in app: XCUIApplication) -> XCUIElement {
        app.tabBars.firstMatch.buttons.matching(NSPredicate(format: "label IN %@", item.names)).firstMatch
    }
    @MainActor private func assertHeaderAligned(_ app: XCUIApplication, with action: String) {
        let title = app.staticTexts["sectionTitle"]
        let settings = app.buttons["settingsButton"]
        XCTAssertTrue(title.exists)
        XCTAssertLessThan(title.frame.minX, settings.frame.minX)
        XCTAssertEqual(title.frame.midY, settings.frame.midY, accuracy: 2)
        XCTAssertEqual(title.frame.midY, app.buttons[action].frame.midY, accuracy: 2)
    }

    @MainActor private func launch(reset: Bool = true) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--uitest", "--test-assistant"] + (reset ? ["--uitest-reset"] : [])
        app.launch()
        XCTAssertTrue(tab(.notes, in: app).waitForExistence(timeout: 20))
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
        XCTAssertEqual(app.tabBars.firstMatch.buttons.count, 4)
        assertHeaderAligned(app, with: "createMenu")
        screenshot(app, "overview-english")
        tab(.notes, in: app).tap()
        assertHeaderAligned(app, with: "createMenu")
        screenshot(app, "notes-titles-only")
        tab(.calendar, in: app).tap()
        assertHeaderAligned(app, with: "newEvent")
        app.buttons["day-8"].tap()
        XCTAssertTrue(app.otherElements["sheetBackdrop"].waitForExistence(timeout: 5))
        screenshot(app, "calendar-day-sheet")
        dismissSheet(app)
        XCTAssertTrue(app.buttons["newEvent"].isHittable)
        spanish(app)
        assertHeaderAligned(app, with: "newEvent")
        screenshot(app, "calendar-spanish")
    }
    @MainActor func testEventAutosaveAndDeleteCancellation() {
        var app = launch()
        tab(.calendar, in: app).tap()
        app.buttons["newEvent"].tap()
        let title = app.textFields["eventTitle"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        title.tap()
        title.typeText("Calendar persistence")
        dismissSheet(app)
        app.terminate()
        app = launch(reset: false)
        tab(.calendar, in: app).tap()
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
        tab(.notes, in: app).tap()
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
        XCTAssertTrue(tab(.notes, in: app).waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["note-Quiet notes"].exists)
        app.terminate()
        app = launch(reset: false)
        tab(.notes, in: app).tap()
        XCTAssertFalse(app.buttons["note-Quiet notes"].exists)
    }
    @MainActor func testCollectionSortIconsNumberWheelAndRelaunch() {
        let app = launch()
        app.buttons["collection-template.movies"].tap()
        let sort = app.buttons["sortDirection"]
        XCTAssertTrue(sort.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["quickFilter-__favorite"].exists)
        // The root tab bar can remain in the accessibility tree during a push.
        let hiddenTab = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "hittable == false"), object: tab(.notes, in: app))
        XCTAssertEqual(XCTWaiter.wait(for: [hiddenTab], timeout: 5), .completed)
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
        let blue = tab(.blue, in: app)
        XCTAssertGreaterThanOrEqual(blue.frame.minX, tab(.calendar, in: app).frame.maxX)
        blue.tap()
        let input = app.textFields["assistantInput"]
        XCTAssertTrue(input.waitForExistence(timeout: 5))
        let keyboard = app.keyboards.firstMatch
        XCTAssertTrue(keyboard.waitForExistence(timeout: 5))
        XCTAssertLessThanOrEqual(input.frame.maxY, keyboard.frame.minY + 2)
        // XCTest reports the key area below the system suggestion strip.
        XCTAssertLessThan(keyboard.frame.minY - input.frame.maxY, 80)
        screenshot(app, "assistant-keyboard")
        input.typeText("What rating did I give Interstellar?\n")
        XCTAssertTrue(app.buttons["result-Interstellar"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["Close"].exists)
        XCTAssertGreaterThan(input.frame.midY, app.buttons["result-Interstellar"].frame.midY)
        XCTAssertFalse(tab(.notes, in: app).exists)
        screenshot(app, "assistant-result-sheet")
        dismissSheet(app)
        tab(.notes, in: app).tap()
        XCTAssertFalse(input.exists)
        tab(.blue, in: app).tap()
        input.tap()
        input.typeText("Unsent draft")
        dismissSheet(app)
        tab(.blue, in: app).tap()
        XCTAssertEqual(input.value as? String, "Unsent draft")
    }
    @MainActor func testBlueSearchWithoutLocalModel() {
        let app = XCUIApplication()
        app.launchArguments = ["--uitest", "--uitest-reset", "--test-library-search"]
        app.launch()
        XCTAssertTrue(tab(.blue, in: app).waitForExistence(timeout: 20))
        spanish(app)
        tab(.blue, in: app).tap()
        let input = app.textFields["assistantInput"]
        XCTAssertTrue(input.waitForExistence(timeout: 5))
        XCTAssertEqual(input.placeholderValue, "Buscar en Blue")
        XCTAssertTrue(app.staticTexts["Este iPhone no admite Apple Intelligence."].exists)
        screenshot(app, "blue-search-keyboard-spanish")
        input.typeText("interstellar\n")
        let result = app.buttons["result-Interstellar"]
        XCTAssertTrue(result.waitForExistence(timeout: 5))
        XCTAssertGreaterThan(input.frame.midY, result.frame.midY)
        screenshot(app, "blue-search-result-spanish")
        result.tap()
        XCTAssertTrue(app.scrollViews["recordEditor"].waitForExistence(timeout: 5))
    }
    @MainActor func testSpanishOverviewAndTouchTargets() {
        let app = launch()
        spanish(app)
        XCTAssertTrue(tab(.collections, in: app).waitForExistence(timeout: 5))
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
        XCTAssertFalse(tab(.notes, in: app).exists)
        screenshot(app, "assistant-spanish")
    }
    @MainActor func testAccessibilitySizeCalendarAndNotes() {
        let app = XCUIApplication()
        app.launchArguments = [
            "--uitest", "--uitest-reset", "--test-assistant", "-UIPreferredContentSizeCategoryName",
            "UICTContentSizeCategoryAccessibilityXXXL",
        ]
        app.launch()
        XCTAssertTrue(tab(.calendar, in: app).waitForExistence(timeout: 20))
        tab(.calendar, in: app).tap()
        XCTAssertTrue(app.datePickers.firstMatch.exists)
        screenshot(app, "calendar-accessibility-size")
        tab(.notes, in: app).tap()
        screenshot(app, "notes-accessibility-size")
    }

}
