import UIKit
import XCTest

final class BlueUITests: XCTestCase {
    @MainActor private func launch(reset: Bool = true, testAssistant: Bool = true) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments =
            ["--uitest"] + (reset ? ["--uitest-reset"] : []) + (testAssistant ? ["--test-assistant"] : [])
        app.launch()
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 20))
        return app
    }
    @MainActor private func screenshot(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
    @MainActor private func ask(_ app: XCUIApplication, _ prompt: String) {
        let input = app.descendants(matching: .any).matching(identifier: "assistantInput").firstMatch
        XCTAssertTrue(input.waitForExistence(timeout: 5))
        input.tap()
        input.typeText(prompt)
        app.buttons["assistantSend"].tap()
    }
    @MainActor private func switchToSpanish(_ app: XCUIApplication) {
        if app.buttons["collectionOptions"].exists && app.buttons["collectionOptions"].isHittable {
            app.buttons["collectionOptions"].tap()
        }
        let settings = app.buttons.matching(identifier: "settingsButton").firstMatch
        XCTAssertTrue(settings.waitForExistence(timeout: 5))
        settings.tap()
        app.buttons["languageSpanish"].tap()
        XCTAssertTrue(app.navigationBars["Ajustes"].exists)
        screenshot(app, "settings-spanish")
        app.buttons["settingsClose"].tap()
    }
    @MainActor func testAssistantExactRecordEditLanguageAndRelaunch() {
        var app = launch()
        screenshot(app, "library-english")
        ask(app, "What rating did I give Interstellar?")
        XCTAssertTrue(app.buttons["result-Interstellar"].waitForExistence(timeout: 10))
        screenshot(app, "assistant-result-english")
        switchToSpanish(app)
        if !app.buttons["result-Interstellar"].exists { app.buttons["assistantCharacter"].tap() }
        XCTAssertTrue(app.staticTexts["Ir a este elemento"].exists)
        app.buttons["result-Interstellar"].tap()
        XCTAssertTrue(app.navigationBars["Películas"].waitForExistence(timeout: 5))
        let row = app.descendants(matching: .any).matching(identifier: "row-Interstellar").firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        screenshot(app, "exact-record-spanish")
        ask(app, "Ponle un 10 a Interstellar")
        XCTAssertTrue(app.buttons["result-Interstellar"].waitForExistence(timeout: 10))
        app.buttons["result-Interstellar"].tap()
        row.tap()
        XCTAssertTrue(app.textFields["field-rating"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.textFields["field-rating"].value as? String, "10")
        app.buttons["recordSave"].tap()
        app.terminate()
        app = launch(reset: false)
        XCTAssertTrue(app.tabBars.buttons["Notas"].exists)
        app.buttons["collection-template.movies"].tap()
        let savedRow = app.descendants(matching: .any).matching(identifier: "row-Interstellar").firstMatch
        if !savedRow.isHittable { app.swipeUp() }
        savedRow.tap()
        XCTAssertEqual(app.textFields["field-rating"].value as? String, "10")
        screenshot(app, "persisted-rating")
    }
    @MainActor func testDraftSurvivesLanguageSwitchAndMarkdownSave() {
        let app = launch()
        app.buttons["createMenu"].tap()
        app.buttons["New note"].tap()
        let title = app.textFields["noteTitle"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        title.tap()
        title.typeText("My architecture notes")
        let body = app.textViews["noteBody"]
        body.tap()
        body.typeText("# Light and space\n\n**Keep it simple.**\n- [ ] Visit the pavilion")
        switchToSpanish(app)
        XCTAssertEqual(title.value as? String, "My architecture notes")
        XCTAssertTrue((body.value as? String ?? "").contains("Keep it simple"))
        app.buttons["noteSave"].tap()
        app.terminate()
        let reopened = launch(reset: false)
        let search = reopened.searchFields.firstMatch
        if !search.exists { reopened.swipeDown() }
        search.tap()
        search.typeText("architecture")
        XCTAssertTrue(reopened.staticTexts["My architecture notes"].waitForExistence(timeout: 5))
        screenshot(reopened, "saved-markdown-search")
    }
    @MainActor func testFiltersRemainVisibleAndRemovableAcrossLanguageSwitch() {
        let app = launch()
        app.buttons["collection-template.movies"].tap()
        app.buttons["openFilters"].tap()
        app.buttons["filterOption-watched"].tap()
        let rangeSwitch = app.switches["Filter by range"].firstMatch
        for _ in 0..<5 {
            if rangeSwitch.exists && rangeSwitch.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(rangeSwitch.waitForExistence(timeout: 5))
        rangeSwitch.coordinate(withNormalizedOffset: CGVector(dx: 1, dy: 0.5)).withOffset(CGVector(dx: -25, dy: 0))
            .tap()
        app.buttons["filtersClose"].tap()
        XCTAssertTrue(app.buttons["removeFilter-status"].exists)
        XCTAssertTrue(app.buttons["removeFilter-rating"].exists)
        switchToSpanish(app)
        XCTAssertTrue(app.buttons["removeFilter-status"].exists)
        screenshot(app, "filters-spanish")
        app.buttons["removeFilter-status"].tap()
        XCTAssertTrue(app.buttons["removeFilter-status"].waitForNonExistence(timeout: 3))
        app.buttons["removeFilter-rating"].tap()
        screenshot(app, "filters-removed")
        XCTAssertTrue(app.buttons["removeFilter-rating"].waitForNonExistence(timeout: 3))
    }
    @MainActor func testSimpleAndCustomCollections() {
        let app = launch()
        app.buttons["createMenu"].tap()
        app.buttons["New collection"].tap()
        app.textFields["collectionTitle"].tap()
        app.textFields["collectionTitle"].typeText("Ideas")
        app.buttons["collectionCreate"].tap()
        XCTAssertTrue(app.navigationBars["Ideas"].waitForExistence(timeout: 5))
        app.buttons["newRecord"].tap()
        app.textFields["recordTitle"].tap()
        app.textFields["recordTitle"].typeText("A tiny bookshop")
        app.buttons["recordSave"].tap()
        XCTAssertTrue(
            app.descendants(matching: .any).matching(identifier: "row-A tiny bookshop").firstMatch.waitForExistence(
                timeout: 5))
        screenshot(app, "notes-only-collection")
        ask(app, "Make a collection of hiking routes with distance and difficulty")
        XCTAssertTrue(app.buttons["resultCollection"].waitForExistence(timeout: 10))
        app.buttons["resultCollection"].tap()
        app.buttons["newRecord"].tap()
        XCTAssertTrue(app.textFields["field-distance"].waitForExistence(timeout: 5))
        screenshot(app, "custom-collection-editor")
    }
    @MainActor func testCalendarAndDisabledAlarmPersistence() {
        let app = launch()
        app.tabBars.buttons["Calendar"].tap()
        screenshot(app, "calendar-english")
        app.buttons["newAlarm"].tap()
        app.textFields["alarmTitle"].tap()
        app.textFields["alarmTitle"].typeText("Call the dentist")
        if app.buttons["keyboardDone"].exists { app.buttons["keyboardDone"].tap() }
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5))
        let enabledSwitch = app.switches["alarmEnabled"].firstMatch
        enabledSwitch.coordinate(withNormalizedOffset: CGVector(dx: 1, dy: 0.5)).withOffset(CGVector(dx: -25, dy: 0))
            .tap()
        XCTAssertEqual(enabledSwitch.value as? String, "0")
        app.buttons["alarmSave"].tap()
        XCTAssertTrue(app.staticTexts["Call the dentist"].waitForExistence(timeout: 5))
        screenshot(app, "calendar-saved-alarm")
    }
    @MainActor func testAccessibilityLabelsAndTouchTargets() throws {
        let app = launch()
        try app.performAccessibilityAudit(for: [.sufficientElementDescription, .hitRegion]) { issue in
            print("ACCESSIBILITY_ISSUE_ELEMENT=\(issue.element?.debugDescription ?? "unknown")")
            return false
        }
        app.buttons["collection-template.movies"].tap()
        XCTAssertTrue(app.buttons["collectionOptions"].waitForExistence(timeout: 5))
        // Audit the settled screen, not accessibility nodes in the navigation transition.
        Thread.sleep(forTimeInterval: 1)
        for button in app.buttons.allElementsBoundByIndex where button.isHittable {
            print("AUDIT_BUTTON \(button.identifier) \(button.frame)")
        }
        try app.performAccessibilityAudit(for: [.sufficientElementDescription, .hitRegion]) { issue in
            print("ACCESSIBILITY_ISSUE_ELEMENT=\(issue.element?.debugDescription ?? "unknown")")
            return false
        }
        app.tabBars.buttons["Calendar"].tap()
        try app.performAccessibilityAudit(for: [.sufficientElementDescription, .hitRegion])
        screenshot(app, "accessibility-calendar")
    }

    @MainActor func testLibraryAndCollectionAtConfiguredTextSize() {
        print(
            "SIMULATOR_ACCESSIBILITY textSize=\(UIApplication.shared.preferredContentSizeCategory.rawValue) reduceMotion=\(UIAccessibility.isReduceMotionEnabled)"
        )
        let app = launch()
        screenshot(app, "configured-text-library")
        app.buttons["collection-template.movies"].tap()
        screenshot(app, "configured-text-collection")
        switchToSpanish(app)
        app.buttons["newRecord"].tap()
        XCTAssertTrue(app.textFields["recordTitle"].waitForExistence(timeout: 5))
        app.textFields["recordTitle"].tap()
        app.textFields["recordTitle"].typeText("Un paseo tranquilo")
        screenshot(app, "configured-text-keyboard")
        if app.buttons["keyboardDone"].exists { app.buttons["keyboardDone"].tap() }
        app.buttons["recordSave"].tap()
        app.tabBars.buttons["Calendario"].tap()
        screenshot(app, "configured-text-calendar")
    }

    @MainActor func testChatReturnOutsideTapAndFavorites() {
        let app = launch()
        let input = app.textFields["assistantInput"]
        input.tap()
        input.typeText("Find Interstellar\n")
        XCTAssertTrue(app.buttons["result-Interstellar"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5))
        app.buttons["result-Interstellar"].tap()
        let favorite = app.buttons["favorite-Interstellar"]
        for _ in 0..<5 {
            if favorite.isHittable { break }
            app.swipeUp()
        }
        favorite.tap()
        XCTAssertEqual(favorite.value as? String, "Yes")
        input.tap()
        input.typeText("Keep this draft")
        app.tabBars.buttons["Calendar"].tap()
        XCTAssertTrue(app.navigationBars["Calendar"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5))
        app.tabBars.buttons["Notes"].tap()
        XCTAssertEqual(app.textFields["assistantInput"].value as? String, "Keep this draft")
        app.navigationBars.firstMatch.tap()
        XCTAssertTrue(app.buttons["assistantMicrophone"].exists)
        screenshot(app, "chat-dismiss-and-favorite")
        app.buttons["BackButton"].tap()
        let favorites = app.buttons["scope-favorites"]
        XCTAssertTrue(favorites.waitForExistence(timeout: 5))
        favorites.tap()
        XCTAssertEqual(favorites.value as? String, "Yes")
        favorites.tap()
        XCTAssertEqual(favorites.value as? String, "No")
        screenshot(app, "library-icon-favorites")
    }

    @MainActor func testCustomIndicatorsAcrossListDetailAndFilters() {
        let app = launch()
        ask(app, "Add Bass and Smoke indicators to Movies")
        XCTAssertTrue(app.buttons["resultCollection"].waitForExistence(timeout: 15))
        app.buttons["resultCollection"].tap()
        let bass = app.buttons["indicator-Aftersun-bass"]
        XCTAssertTrue(bass.waitForExistence(timeout: 5))
        bass.tap()
        XCTAssertEqual(bass.value as? String, "Yes")
        app.buttons["quickFilter-bass"].tap()
        XCTAssertTrue(app.buttons["row-Aftersun"].exists)
        XCTAssertFalse(app.buttons["row-Arrival"].exists)
        screenshot(app, "custom-indicator-filter")
        app.buttons["quickFilter-bass"].tap()
        app.buttons["row-Aftersun"].tap()
        XCTAssertEqual(app.buttons["field-bass"].value as? String, "Yes")
        XCTAssertTrue(app.buttons["field-smoke"].exists)
        screenshot(app, "custom-indicator-detail")
    }

    @MainActor func testSavedNoteOpensRenderedAndCanBeEdited() {
        let app = launch()
        app.buttons["scope-notes"].tap()
        let note = app.buttons.matching(identifier: "note-A slower kind of Sunday").firstMatch
        if note.exists { note.tap() } else { app.staticTexts["A slower kind of Sunday"].tap() }
        XCTAssertTrue(app.buttons["noteToggleEdit"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.textViews["noteBody"].exists)
        app.buttons["noteToggleEdit"].tap()
        XCTAssertTrue(app.textViews["noteBody"].exists)
        screenshot(app, "note-manual-edit")
    }

}
