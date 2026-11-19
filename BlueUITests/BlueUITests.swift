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

    @MainActor private func launch(reset: Bool = true, arguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments =
            ["--uitest", "--test-assistant", "--test-event-scheduling"] + (reset ? ["--uitest-reset"] : []) + arguments
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
        let close = app.buttons["closeSheet"]
        XCTAssertTrue(close.waitForExistence(timeout: 5))
        let picker = app.buttons["languagePicker"]
        for _ in 0..<4 where !picker.isHittable { app.swipeUp() }
        XCTAssertTrue(picker.isHittable)
        picker.tap()
        let spanish = app.buttons["Español (España)"]
        XCTAssertTrue(spanish.waitForExistence(timeout: 5))
        spanish.tap()
        close.tap()
        XCTAssertTrue(close.waitForNonExistence(timeout: 5))
    }
    @MainActor func testCleanOverviewAndCalendarDaySheet() {
        let app = launch()
        XCTAssertFalse(app.buttons["row-Interstellar"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["assistantInput"].firstMatch.exists)
        XCTAssertEqual(app.tabBars.firstMatch.buttons.count, 4)
        assertHeaderAligned(app, with: "createMenu")
        screenshot(app, "overview-english")
        tab(.notes, in: app).tap()
        assertHeaderAligned(app, with: "createMenu")
        screenshot(app, "notes-titles-only")
        tab(.calendar, in: app).tap()
        assertHeaderAligned(app, with: "newEvent")
        app.buttons["day-8"].tap()
        XCTAssertTrue(app.staticTexts["calendarAgendaTitle"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.otherElements["sheetBackdrop"].exists)
        XCTAssertTrue(app.buttons["newEvent"].isHittable)
        screenshot(app, "calendar-inline-agenda")
        spanish(app)
        assertHeaderAligned(app, with: "newEvent")
        screenshot(app, "calendar-spanish")
    }
    @MainActor func testEventSavesWithTickAndDeleteCancellation() {
        var app = launch()
        tab(.calendar, in: app).tap()
        let calendar = Calendar.current
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: Date())!
        let day = calendar.component(.day, from: tomorrow)
        let monthDays = calendar.range(of: .day, in: .month, for: tomorrow)!
        let targetDay = monthDays.contains(day + 1) ? day + 1 : day - 1
        let nextMonth = day == 1
        if nextMonth { app.buttons["Next month"].tap() }
        app.buttons["day-\(day)"].tap()
        app.buttons["newEvent"].press(forDuration: 1)
        let title = app.textFields["eventTitle"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        let finish = app.buttons["finishEvent"]
        XCTAssertTrue(finish.isEnabled)
        XCTAssertFalse(app.switches["eventRing"].exists)
        XCTAssertFalse(app.switches["eventNotification"].exists)
        XCTAssertEqual(title.placeholderValue, "Event name")
        XCTAssertEqual(app.pickerWheels.count, 0)
        let dayControl = app.buttons["eventDay"]
        let timeControl = app.buttons["eventTime"]
        XCTAssertTrue(dayControl.exists)
        XCTAssertGreaterThan(dayControl.frame.midY, title.frame.midY)
        XCTAssertLessThan(dayControl.frame.midY, app.textFields["eventNotes"].frame.midY)
        XCTAssertLessThan(timeControl.frame.midY, dayControl.frame.midY)
        XCTAssertEqual(app.staticTexts["sheetTitle"].label, "Event")
        XCTAssertEqual(app.staticTexts["sheetTitle"].frame.midX, app.frame.midX, accuracy: 2)
        screenshot(app, "event-editor-rows")
        timeControl.tap()
        XCTAssertTrue(app.pickerWheels.firstMatch.waitForExistence(timeout: 5))
        XCTAssertEqual(app.pickerWheels.count, 2, app.pickerWheels.debugDescription)
        app.pickerWheels.element(boundBy: 0).adjust(toPickerWheelValue: "17")
        app.pickerWheels.element(boundBy: 1).adjust(toPickerWheelValue: "35")
        XCTAssertEqual(timeControl.value as? String, "17:35")
        XCTAssertFalse(app.buttons["detailOptions"].exists)
        XCTAssertTrue(finish.isEnabled)
        screenshot(app, "event-time-wheels")
        dayControl.tap()
        XCTAssertTrue(app.pickerWheels.element(boundBy: 2).waitForExistence(timeout: 5))
        XCTAssertEqual(app.pickerWheels.count, 3)
        app.pickerWheels.element(boundBy: 1).adjust(toPickerWheelValue: "\(targetDay)")
        XCTAssertEqual(timeControl.value as? String, "17:35")
        screenshot(app, "event-date-wheels")
        title.tap()
        title.typeText("Calendar persistence")
        XCTAssertEqual(app.pickerWheels.count, 0)
        screenshot(app, "calendar-editor-keyboard")
        finish.tap()
        let eventID = "calendar-event-Calendar persistence"
        XCTAssertTrue(app.buttons["closeSheet"].waitForNonExistence(timeout: 5))
        app.buttons["day-\(targetDay)"].tap()
        XCTAssertTrue(app.buttons[eventID].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons[eventID].label.contains("17:35"))
        app.terminate()
        app = launch(reset: false)
        tab(.calendar, in: app).tap()
        if nextMonth { app.buttons["Next month"].tap() }
        app.buttons["day-\(targetDay)"].tap()
        XCTAssertTrue(app.buttons[eventID].waitForExistence(timeout: 5))
        app.buttons[eventID].tap()
        let reopened = app.textFields["eventTitle"]
        XCTAssertTrue(reopened.waitForExistence(timeout: 5))
        XCTAssertEqual(reopened.value as? String, "Calendar persistence")
        XCTAssertEqual(app.buttons["eventTime"].value as? String, "17:35")
        XCTAssertFalse(finish.exists)
        XCTAssertFalse(app.buttons["detailOptions"].exists)
        screenshot(app, "event-saved")
        replace(reopened, "Discard this edit")
        XCTAssertTrue(finish.exists)
        app.buttons["closeSheet"].tap()
        XCTAssertTrue(reopened.waitForNonExistence(timeout: 5))
        XCTAssertFalse(app.buttons["calendar-event-Discard this edit"].exists)
        app.buttons[eventID].tap()
        let notes = app.textFields["eventNotes"]
        XCTAssertTrue(notes.waitForExistence(timeout: 5))
        notes.tap()
        notes.typeText("Updated from the calendar")
        finish.tap()
        XCTAssertTrue(notes.waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.buttons[eventID].label.contains("Updated from the calendar"))
        app.buttons[eventID].press(forDuration: 1)
        app.buttons["Delete"].tap()
        XCTAssertTrue(app.buttons["closeConfirmation"].waitForExistence(timeout: 5))
        screenshot(app, "delete-modal")
        app.buttons["closeConfirmation"].tap()
        XCTAssertTrue(app.buttons[eventID].waitForExistence(timeout: 5))
    }
    @MainActor func testPastEventSavesOnSelectedDay() {
        let app = launch()
        spanish(app)
        tab(.calendar, in: app).tap()
        let calendar = Calendar.current
        let now = Date()
        let yesterday = calendar.date(byAdding: .day, value: -1, to: now)!
        if !calendar.isDate(yesterday, equalTo: now, toGranularity: .month) {
            app.buttons["Mes anterior"].tap()
        }
        app.buttons["day-\(calendar.component(.day, from: yesterday))"].tap()
        app.buttons["newEvent"].tap()
        let title = app.textFields["eventTitle"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        let date = app.buttons["eventDay"]
        XCTAssertEqual(date.label, "Fecha")
        XCTAssertEqual(app.buttons["eventTime"].label, "Hora")
        XCTAssertEqual(title.placeholderValue, "Nombre del evento")
        XCTAssertEqual(app.pickerWheels.count, 0)
        screenshot(app, "event-editor-rows-spanish")
        date.tap()
        XCTAssertTrue(app.pickerWheels.element(boundBy: 2).waitForExistence(timeout: 5))
        screenshot(app, "event-date-wheels-spanish")
        title.tap()
        title.typeText("Yesterday's appointment")
        app.buttons["closeSheet"].tap()
        XCTAssertTrue(title.waitForNonExistence(timeout: 5))
        XCTAssertFalse(app.buttons["calendar-event-Yesterday's appointment"].exists)
        app.buttons["newEvent"].tap()
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        let finish = app.buttons["finishEvent"]
        XCTAssertTrue(finish.isEnabled)
        finish.tap()
        XCTAssertTrue(title.waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.buttons["calendar-event-Evento"].waitForExistence(timeout: 5))
    }

    @MainActor func testEventRepeatPersistsAndLocalizes() {
        let app = launch()
        tab(.calendar, in: app).tap()
        app.buttons["newEvent"].tap()
        let title = app.textFields["eventTitle"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Never")).firstMatch.exists)
        let today = Calendar.current.component(.weekday, from: Date())
        let second = today % 7 + 1
        let todayButton = app.buttons["eventRepeatDay-\(today)"]
        XCTAssertLessThan(app.buttons["eventDay"].frame.midY, todayButton.frame.midY)
        XCTAssertLessThan(todayButton.frame.midY, app.textFields["eventNotes"].frame.midY)
        todayButton.tap()
        app.buttons["eventRepeatDay-\(second)"].tap()
        title.tap()
        title.typeText("Weekly routine")
        app.buttons["finishEvent"].tap()
        let row = app.buttons["calendar-event-Weekly routine"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["eventRepeatDay-\(today)"].isSelected)
        XCTAssertTrue(app.buttons["eventRepeatDay-\(second)"].isSelected)
        XCTAssertFalse(app.buttons["finishEvent"].exists)
        screenshot(app, "event-repeat-english")
        app.buttons["closeSheet"].tap()
        spanish(app)
        row.tap()
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Repetir")).firstMatch.exists)
        XCTAssertEqual(app.buttons["eventRepeatDay-2"].label, "lunes")
        XCTAssertTrue(app.buttons["eventRepeatDay-\(today)"].isSelected)
        screenshot(app, "event-repeat-spanish")
        for day in 1...7 {
            let button = app.buttons["eventRepeatDay-\(day)"]
            if button.isSelected { button.tap() }
        }
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Nunca")).firstMatch.exists)
        XCTAssertTrue(app.buttons["finishEvent"].exists)
        app.buttons["finishEvent"].tap()
        XCTAssertTrue(title.waitForNonExistence(timeout: 5))
    }

    @MainActor func testCollectionCoverAndIconMenu() {
        let app = launch(arguments: ["--test-collection-cover"])
        let row = app.buttons["collection-Cover preview"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()
        XCTAssertTrue(app.textFields["collectionTitle"].waitForExistence(timeout: 5))
        screenshot(app, "collection-cover-header")
        app.buttons["collectionBack"].tap()
        row.press(forDuration: 1)
        let change = app.buttons["Icon or cover"]
        XCTAssertTrue(change.waitForExistence(timeout: 5))
        XCTAssertGreaterThan(change.frame.midY, app.buttons["Pin"].frame.midY)
        screenshot(app, "collection-native-context-menu")
        change.tap()
        let field = app.textFields["collectionSymbolInput"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        screenshot(app, "collection-cover-picker")
        app.segmentedControls["artworkMode"].buttons["AI"].tap()
        XCTAssertTrue(app.textFields["artworkSubject"].waitForExistence(timeout: 5))
        screenshot(app, "collection-ai-cover-picker")
        app.segmentedControls["artworkMode"].buttons["Icon"].tap()
        app.buttons["collectionSymbol-star"].tap()
        app.buttons["saveCollectionArtwork"].tap()
        XCTAssertTrue(field.waitForNonExistence(timeout: 5))
        row.press(forDuration: 1)
        change.tap()
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        XCTAssertEqual(field.value as? String, "star")
        app.buttons["closeSheet"].tap()
    }

    @MainActor func testCoverSetupRoutesToAssistant() {
        let app = launch(arguments: ["--test-collection-cover"])
        app.buttons["collection-Cover preview"].press(forDuration: 1)
        app.buttons["Icon or cover"].tap()
        let modes = app.segmentedControls["artworkMode"]
        XCTAssertTrue(modes.waitForExistence(timeout: 5))
        modes.buttons["AI"].tap()
        app.buttons["Configure OpenAI in Settings"].tap()
        XCTAssertTrue(app.buttons["assistantProvider"].waitForExistence(timeout: 5))
        XCTAssertFalse(modes.exists)
        screenshot(app, "cover-needs-configuration")
    }

    @MainActor func testSettingsSectionsCollapseAndCalendarSwipeDelete() {
        let app = launch()
        app.buttons["settingsButton"].tap()
        let assistantSection = app.buttons["settingsSection-assistant"]
        XCTAssertTrue(assistantSection.waitForExistence(timeout: 5))
        assistantSection.tap()
        XCTAssertTrue(app.buttons["assistantProvider"].waitForNonExistence(timeout: 5))
        let storage = app.buttons["settingsSection-storage"]
        XCTAssertTrue(storage.exists)
        storage.tap()
        XCTAssertFalse(app.buttons["backupFolder"].exists)
        screenshot(app, "settings-collapsed")
        app.buttons["closeSheet"].tap()
        tab(.calendar, in: app).tap()
        app.buttons["newEvent"].tap()
        let title = app.textFields["eventTitle"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        title.tap()
        title.typeText("Swipe event")
        app.buttons["finishEvent"].tap()
        let row = app.buttons["calendar-event-Swipe event"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.swipeLeft()
        let trash = app.buttons["Delete"]
        XCTAssertTrue(trash.waitForExistence(timeout: 5))
        screenshot(app, "calendar-swipe-delete")
        trash.tap()
        XCTAssertTrue(app.buttons["confirmDelete"].waitForExistence(timeout: 5))
        app.buttons["closeConfirmation"].tap()
        XCTAssertTrue(row.waitForExistence(timeout: 5))
    }

    @MainActor func testNoteAutosavesAndSurvivesRelaunch() {
        var app = launch()
        tab(.notes, in: app).tap()
        app.buttons["createMenu"].tap()
        let title = app.textFields["noteTitle"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["finishNote"].exists)
        XCTAssertNotEqual(title.placeholderValue, "Name")
        replace(title, "Quiet notes")
        let body = app.descendants(matching: .any).matching(identifier: "noteBody").firstMatch
        XCTAssertNotEqual(body.placeholderValue, "Notes")
        body.tap()
        body.typeText("First line\nSecond line")
        app.buttons["noteBack"].tap()
        let note = app.buttons["note-Quiet notes"]
        XCTAssertTrue(note.waitForExistence(timeout: 5))
        app.terminate()
        app = launch(reset: false)
        tab(.notes, in: app).tap()
        app.buttons["note-Quiet notes"].tap()
        XCTAssertTrue(body.waitForExistence(timeout: 5))
        XCTAssertEqual(body.value as? String, "First line\nSecond line")
        screenshot(app, "note-first-line-title")
    }
    @MainActor func testCreateKeepsPlaceholdersOutOfTheLibrary() {
        let app = launch()
        app.buttons["collection-template.movies"].tap()
        XCTAssertTrue(app.staticTexts["12 items"].waitForExistence(timeout: 5))
        for _ in 0..<2 {
            app.buttons["newRecord"].tap()
            let title = app.textFields["recordTitle"]
            XCTAssertTrue(title.waitForExistence(timeout: 5))
            XCTAssertEqual(title.placeholderValue, "Name")
            app.buttons["closeSheet"].tap()
            XCTAssertTrue(title.waitForNonExistence(timeout: 5))
            XCTAssertTrue(app.staticTexts["12 items"].exists)
        }
        XCTAssertFalse(app.buttons["row-Name"].exists)

        tab(.notes, in: app).tap()
        app.buttons["createMenu"].tap()
        let noteTitle = app.textFields["noteTitle"]
        XCTAssertTrue(noteTitle.waitForExistence(timeout: 5))
        XCTAssertNotEqual(noteTitle.placeholderValue, "Name")
        app.buttons["noteBack"].tap()
        XCTAssertTrue(noteTitle.waitForNonExistence(timeout: 5))
        XCTAssertFalse(app.buttons["note-Name"].exists)

        tab(.collections, in: app).tap()
        app.buttons["createMenu"].tap()
        let collectionTitle = app.textFields["collectionTitle"]
        XCTAssertTrue(collectionTitle.waitForExistence(timeout: 5))
        XCTAssertEqual(collectionTitle.placeholderValue, "Name")
        app.buttons["collectionBack"].tap()
        XCTAssertTrue(collectionTitle.waitForNonExistence(timeout: 5))
        XCTAssertFalse(app.buttons["collection-Name"].exists)

        app.buttons["createMenu"].tap()
        XCTAssertTrue(collectionTitle.waitForExistence(timeout: 5))
        collectionTitle.tap()
        collectionTitle.typeText("Weekend plans\n")
        XCTAssertTrue(app.buttons["newRecord"].waitForExistence(timeout: 5))
        XCTAssertEqual(collectionTitle.value as? String, "Weekend plans")
        app.buttons["collectionBack"].tap()
        XCTAssertTrue(app.buttons["collection-Weekend plans"].waitForExistence(timeout: 5))
    }

    @MainActor func testCollectionSortIconsNumberWheelAndRelaunch() {
        let app = launch()
        app.buttons["collection-template.movies"].tap()
        let filters = app.buttons["collectionFilters"]
        XCTAssertTrue(filters.waitForExistence(timeout: 5))
        filters.tap()
        XCTAssertTrue(app.staticTexts["Filters"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Sort by"].exists)
        let updated = app.buttons["sort-choice-updated"]
        XCTAssertTrue(updated.exists)
        updated.tap()
        XCTAssertTrue(updated.isSelected)
        app.buttons["sort-choice-title"].tap()
        screenshot(app, "native-filters")
        let descending = app.buttons["Descending"]
        XCTAssertTrue(descending.waitForExistence(timeout: 5))
        descending.tap()
        app.buttons["Ascending"].tap()
        let heading = app.staticTexts["Filters"]
        heading.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .press(forDuration: 0.08, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: 0.97)))
        XCTAssertTrue(app.buttons["closeSheet"].waitForNonExistence(timeout: 5))
        screenshot(app, "collection-compact-header")
        app.buttons["row-Interstellar"].tap()
        let rating = app.scrollViews["recordEditor"].buttons["property-rating"]
        XCTAssertTrue(rating.waitForExistence(timeout: 5))
        rating.tap()
        let wheel = app.pickerWheels.firstMatch
        XCTAssertTrue(wheel.waitForExistence(timeout: 5))
        wheel.adjust(toPickerWheelValue: "8.5")
        screenshot(app, "native-number-wheel")
        app.buttons["closeSheet"].firstMatch.tap()
        XCTAssertTrue(wheel.waitForNonExistence(timeout: 5))
        XCTAssertEqual(app.scrollViews["recordEditor"].buttons["property-rating"].value as? String, "8.5")
        XCTAssertFalse(app.buttons["recordSave"].exists)
        screenshot(app, "record-visual-properties")
        app.terminate()
        let reopened = launch(reset: false)
        reopened.buttons["collection-template.movies"].tap()
        reopened.buttons["row-Interstellar"].tap()
        let reopenedRating = reopened.scrollViews["recordEditor"].buttons["property-rating"]
        XCTAssertTrue(reopenedRating.waitForExistence(timeout: 5))
        XCTAssertEqual(reopenedRating.value as? String, "8.5")
        reopenedRating.tap()
        reopened.buttons["Clear"].tap()
        XCTAssertTrue(reopened.pickerWheels.firstMatch.waitForNonExistence(timeout: 5))
        let empty = reopenedRating.value as? String
        XCTAssertNotNil(empty)
        XCTAssertNotEqual(empty, "8.5")
        screenshot(reopened, "empty-rating-in-record")
        reopened.buttons["closeSheet"].firstMatch.tap()
        XCTAssertTrue(reopened.scrollViews["recordEditor"].waitForNonExistence(timeout: 5))
        let row = reopened.buttons["row-Interstellar"].frame
        let rowRating = reopened.buttons.matching(identifier: "property-rating").allElementsBoundByIndex.first {
            abs($0.frame.midY - row.midY) < 10
        }
        XCTAssertNotNil(rowRating)
        XCTAssertEqual(rowRating?.value as? String, empty)
        screenshot(reopened, "empty-rating-in-collection")
    }
    @MainActor func testLiveVoiceOpensFirstAndSwitchesToText() {
        let app = XCUIApplication()
        app.launchArguments = ["--uitest", "--uitest-reset", "--test-assistant", "--test-live-assistant"]
        app.launch()
        XCTAssertTrue(tab(.blue, in: app).waitForExistence(timeout: 15))
        app.buttons["collection-template.movies"].tap()
        XCTAssertTrue(app.buttons["row-Interstellar"].waitForExistence(timeout: 5))
        tab(.blue, in: app).tap()
        let orb = app.descendants(matching: .any)["liveVoiceOrb"].firstMatch
        let input = app.descendants(matching: .any)["assistantInput"].firstMatch
        let mute = app.buttons["voiceMute"]
        let closeVoice = app.buttons["exitLiveVoice"]
        let startVoice = app.buttons["startLiveVoice"]
        XCTAssertTrue(orb.waitForExistence(timeout: 5))
        XCTAssertEqual(orb.label, "Listening")
        XCTAssertFalse(app.staticTexts["Listening"].exists)
        XCTAssertFalse(app.keyboards.firstMatch.exists)
        screenshot(app, "voice-orb")
        mute.tap()
        XCTAssertEqual(orb.label, "Microphone off")
        mute.tap()
        XCTAssertEqual(orb.label, "Listening")
        closeVoice.tap()
        XCTAssertTrue(startVoice.waitForExistence(timeout: 5))
        XCTAssertTrue(tab(.calendar, in: app).isHittable)
        screenshot(app, "chat-without-keyboard-backdrop")
        startVoice.tap()
        XCTAssertTrue(orb.waitForExistence(timeout: 5))
        input.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(orb.exists)
        XCTAssertTrue(startVoice.exists)
        let initialHeight = input.frame.height
        input.typeText("What rating did I give Interstellar in the movies collection? Please show the saved score.")
        let send = app.buttons["assistantSend"]
        XCTAssertTrue(send.waitForExistence(timeout: 5))
        XCTAssertFalse(startVoice.exists)
        XCTAssertGreaterThan(input.frame.height, initialHeight)
        screenshot(app, "voice-to-multiline-chat")
        send.tap()
        XCTAssertTrue(app.buttons["result-Interstellar"].waitForExistence(timeout: 10))
        XCTAssertFalse((input.value as? String ?? "").contains("Interstellar"))
    }

    @MainActor func testGoogleDriveConnectionIsAvailableInSettings() {
        let app = launch()
        app.buttons["settingsButton"].tap()
        let assistantSection = app.buttons["settingsSection-assistant"]
        XCTAssertTrue(assistantSection.waitForExistence(timeout: 5))
        assistantSection.tap()
        let connect = app.buttons["connectGoogleDrive"]
        XCTAssertTrue(connect.waitForExistence(timeout: 5))
        XCTAssertEqual(connect.label, "Connect Google Drive")
        XCTAssertFalse(app.buttons["backupFolder"].exists)
        screenshot(app, "google-drive-connect-settings")
    }

    @MainActor func testAppearanceCanBeChangedFromSettings() {
        let app = launch()
        app.buttons["settingsButton"].tap()
        let picker = app.segmentedControls["appearancePicker"]
        XCTAssertTrue(app.buttons["closeSheet"].waitForExistence(timeout: 5))
        for _ in 0..<4 where !picker.isHittable { app.swipeUp() }
        XCTAssertTrue(picker.isHittable)
        XCTAssertTrue(app.staticTexts["Theme"].exists)
        XCTAssertEqual(picker.buttons.count, 3)
        picker.buttons["Dark"].tap()
        XCTAssertTrue(picker.waitForExistence(timeout: 5))
        XCTAssertTrue(picker.buttons["Dark"].isSelected)
        screenshot(app, "appearance-dark")
        picker.buttons["System"].tap()
        XCTAssertTrue(picker.buttons["System"].isSelected)
    }

    @MainActor func testVoiceSettingsAreAvailableInSpanish() {
        let app = launch()
        spanish(app)
        app.buttons["settingsButton"].tap()
        let live = app.buttons["assistantVoiceModel"]
        XCTAssertTrue(live.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["assistantTranscriptionModel"].exists)
        screenshot(app, "voice-model-settings-spanish")
        let picker = app.segmentedControls["appearancePicker"]
        for _ in 0..<4 where !picker.isHittable { app.swipeUp() }
        XCTAssertTrue(app.staticTexts["Tema"].exists)
        XCTAssertTrue(picker.buttons["Sistema"].isHittable)
        XCTAssertTrue(picker.buttons["Claro"].isHittable)
        XCTAssertTrue(picker.buttons["Oscuro"].isHittable)
        screenshot(app, "appearance-spanish")
    }

    @MainActor func testAssistantSheetReturnAndDraftDismissal() {
        let app = launch()
        let blue = tab(.blue, in: app)
        let launcherFrame = blue.frame
        let calendarFrame = tab(.calendar, in: app).frame
        XCTAssertGreaterThanOrEqual(launcherFrame.minX, calendarFrame.maxX)
        XCTAssertEqual(launcherFrame.midY, calendarFrame.midY, accuracy: 5)
        blue.tap()
        let input = app.descendants(matching: .any)["assistantInput"].firstMatch
        XCTAssertTrue(input.waitForExistence(timeout: 5))
        let keyboard = app.keyboards.firstMatch
        XCTAssertTrue(keyboard.waitForExistence(timeout: 5))
        XCTAssertLessThanOrEqual(input.frame.maxY, keyboard.frame.minY + 2)
        // XCTest reports the key area below the system suggestion strip.
        XCTAssertLessThan(keyboard.frame.minY - input.frame.maxY, 80)
        XCTAssertTrue(app.buttons["clearConversation"].exists)
        XCTAssertFalse(app.buttons["clearConversation"].isEnabled)
        XCTAssertLessThan(app.buttons["closeAssistant"].frame.minY, 100)
        screenshot(app, "assistant-keyboard")
        input.typeText("What rating did I give Interstellar?\n")
        XCTAssertTrue(app.buttons["result-Interstellar"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["closeAssistant"].exists)
        XCTAssertGreaterThan(input.frame.midY, app.buttons["result-Interstellar"].frame.midY)
        XCTAssertTrue(keyboard.waitForNonExistence(timeout: 5))
        XCTAssertTrue(tab(.notes, in: app).isHittable)
        XCTAssertTrue(blue.isHittable)
        XCTAssertEqual(blue.frame.midX, launcherFrame.midX, accuracy: 2)
        screenshot(app, "assistant-history-above-tabs")
        input.tap()
        input.typeText("Draft after result")
        XCTAssertTrue(app.keyboards.firstMatch.exists)
        XCTAssertTrue(app.buttons["result-Interstellar"].exists)
        screenshot(app, "assistant-history-above-keyboard")
        app.buttons["clearConversation"].tap()
        XCTAssertFalse(app.buttons["result-Interstellar"].exists)
        XCTAssertEqual(input.value as? String, "Draft after result")
        app.buttons["closeAssistant"].tap()
        XCTAssertTrue(blue.waitForExistence(timeout: 5))
        XCTAssertTrue(keyboard.waitForNonExistence(timeout: 5))
        XCTAssertEqual(blue.frame.midY, launcherFrame.midY, accuracy: 2)
        tab(.notes, in: app).tap()
        XCTAssertFalse(input.exists)
        tab(.blue, in: app).tap()
        input.tap()
        XCTAssertEqual(input.value as? String, "Draft after result")
        app.buttons["closeAssistant"].tap()
        XCTAssertFalse(input.exists)
        tab(.blue, in: app).tap()
        XCTAssertEqual(input.value as? String, "Draft after result")
    }
    @MainActor func testUnconfiguredBlueBlocksBackgroundAndHighlightsSettings() {
        let app = XCUIApplication()
        app.launchArguments = ["--uitest", "--uitest-reset"]
        app.launch()
        let launcher = tab(.blue, in: app)
        XCTAssertTrue(launcher.waitForExistence(timeout: 15))
        let frame = launcher.frame
        let movies = app.buttons["collection-template.movies"]
        XCTAssertTrue(movies.exists)
        let behind = app.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: movies.frame.midX, dy: movies.frame.midY))
        launcher.tap()
        let configure = app.buttons["configureBlue"]
        XCTAssertTrue(configure.waitForExistence(timeout: 5))
        XCTAssertFalse(app.keyboards.firstMatch.exists)
        behind.tap()
        XCTAssertTrue(configure.isHittable)
        XCTAssertFalse(app.buttons["collectionOptions"].exists)
        screenshot(app, "blue-setup-message")
        configure.tap()
        XCTAssertTrue(app.secureTextFields["assistantAPIKey"].waitForExistence(timeout: 5))
        XCTAssertFalse(tab(.calendar, in: app).isHittable)
        screenshot(app, "blue-setup-highlight")
        app.buttons["closeSheet"].tap()
        XCTAssertTrue(app.secureTextFields["assistantAPIKey"].waitForNonExistence(timeout: 5))
        XCTAssertEqual(launcher.frame.midY, frame.midY, accuracy: 2)
        tab(.calendar, in: app).tap()
        XCTAssertTrue(app.buttons["newEvent"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.secureTextFields["assistantAPIKey"].waitForNonExistence(timeout: 5))
        XCTAssertEqual(launcher.frame.midY, frame.midY, accuracy: 2)
        spanish(app)
        launcher.tap()
        XCTAssertTrue(configure.waitForExistence(timeout: 5))
        XCTAssertEqual(configure.label, "Ups, parece que aún no me has configurado.")
        screenshot(app, "blue-setup-spanish")
    }

    @MainActor func testRejectedBlueCredentialAlwaysOffersSettings() {
        let app = XCUIApplication()
        app.launchArguments = ["--uitest", "--uitest-reset", "--test-rejected-assistant-key"]
        app.launch()
        let launcher = tab(.blue, in: app)
        let configure = app.buttons["configureBlue"]
        XCTAssertTrue(launcher.waitForExistence(timeout: 15))
        launcher.tap()
        XCTAssertTrue(configure.waitForExistence(timeout: 5))
        XCTAssertEqual(configure.label, "Oops, looks like you haven’t set me up yet.")
        XCTAssertFalse(app.keyboards.firstMatch.exists)
        launcher.tap()
        XCTAssertTrue(configure.waitForNonExistence(timeout: 5))
        launcher.tap()
        XCTAssertTrue(configure.waitForExistence(timeout: 5))
        configure.tap()
        XCTAssertTrue(app.secureTextFields["assistantAPIKey"].waitForExistence(timeout: 5))
    }

    @MainActor func testLibraryContextMenusPinAndConfirmDeletion() {
        let app = launch()
        let movies = app.buttons["collection-template.movies"]
        let collection = app.buttons["collection-template.artists"]
        XCTAssertTrue(collection.exists)
        XCTAssertGreaterThan(collection.frame.midY, movies.frame.midY)
        collection.press(forDuration: 1)
        XCTAssertTrue(app.buttons["Pin"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Archive"].exists)
        let delete = app.buttons["Delete"]
        XCTAssertTrue(delete.exists)
        screenshot(app, "collection-context-menu")
        app.buttons["Pin"].tap()
        XCTAssertTrue(collection.waitForExistence(timeout: 5))
        XCTAssertLessThan(collection.frame.midY, movies.frame.midY)
        collection.press(forDuration: 1)
        XCTAssertTrue(app.buttons["Unpin"].waitForExistence(timeout: 5))
        delete.tap()
        let collectionPrompt = app.staticTexts["Delete this collection and its items?"]
        let confirm = app.buttons["confirmDelete"]
        XCTAssertTrue(collectionPrompt.waitForExistence(timeout: 5))
        app.buttons["closeConfirmation"].tap()
        XCTAssertTrue(collectionPrompt.waitForNonExistence(timeout: 5))
        XCTAssertTrue(collection.waitForExistence(timeout: 5))
        collection.press(forDuration: 1)
        XCTAssertTrue(delete.waitForExistence(timeout: 5))
        delete.tap()
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        confirm.tap()
        XCTAssertTrue(collection.waitForNonExistence(timeout: 5))
        XCTAssertTrue(movies.exists)

        tab(.notes, in: app).tap()
        let note = app.buttons["note-A slower kind of Sunday"]
        XCTAssertTrue(note.waitForExistence(timeout: 5))
        note.press(forDuration: 1)
        XCTAssertTrue(delete.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Archive"].exists)
        screenshot(app, "note-context-menu")
        delete.tap()
        XCTAssertTrue(app.staticTexts["Delete this note?"].waitForExistence(timeout: 5))
        confirm.tap()
        XCTAssertTrue(note.waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.buttons["note-Places, spaces, ideas"].exists)
    }

    @MainActor func testRecordMultiDeleteRequiresConfirmationAndCanBeCancelled() {
        let app = launch()
        app.buttons["collection-template.movies"].tap()
        let record = app.buttons["row-Interstellar"]
        XCTAssertTrue(record.waitForExistence(timeout: 5))
        app.buttons["collectionOptions"].tap()
        let selectItems = app.buttons["selectCollectionItems"]
        let selectLabel = app.buttons["Select items"]
        XCTAssertTrue(selectLabel.waitForExistence(timeout: 5))
        screenshot(app, "collection-options")
        if selectItems.exists { selectItems.tap() } else { selectLabel.tap() }
        let zero = app.staticTexts["selectedRecordCount"]
        XCTAssertTrue(zero.waitForExistence(timeout: 5))
        XCTAssertEqual(zero.label, "0 selected")
        XCTAssertFalse(app.buttons["newRecord"].exists)
        let filters = app.buttons["collectionFilters"]
        XCTAssertTrue(filters.exists)
        filters.tap()
        XCTAssertTrue(app.buttons["closeSheet"].waitForExistence(timeout: 5))
        app.buttons["closeSheet"].tap()
        XCTAssertTrue(app.buttons["closeSheet"].waitForNonExistence(timeout: 5))
        app.buttons["cancelRecordSelection"].tap()
        XCTAssertTrue(record.waitForExistence(timeout: 5))
        record.press(forDuration: 1)
        let recordTitle = app.textFields["recordTitle"]
        XCTAssertTrue(recordTitle.waitForExistence(timeout: 5))
        XCTAssertEqual(recordTitle.value as? String, "Interstellar")
        XCTAssertFalse(app.buttons["finishRecord"].exists)
        screenshot(app, "record-long-press-detail")
        app.buttons["closeSheet"].tap()
        XCTAssertTrue(recordTitle.waitForNonExistence(timeout: 5))
        app.buttons["collectionOptions"].tap()
        selectLabel.tap()

        let selected = app.staticTexts["selectedRecordCount"]
        let first = app.buttons["select-record-Interstellar"]
        let second = app.buttons["select-record-Her"]
        let trash = app.buttons["deleteSelectedRecords"]
        let close = app.buttons["cancelRecordSelection"]
        XCTAssertTrue(selected.waitForExistence(timeout: 5))
        XCTAssertFalse(first.isSelected)
        XCTAssertEqual(selected.label, "0 selected")
        first.tap()
        XCTAssertTrue(first.isSelected)
        XCTAssertEqual(selected.label, "1 selected")
        XCTAssertFalse(tab(.blue, in: app).isHittable)
        XCTAssertFalse(app.buttons["collectionOptions"].exists)
        XCTAssertFalse(app.buttons["confirmDelete"].exists)

        first.tap()
        XCTAssertEqual(selected.label, "0 selected")
        XCTAssertFalse(trash.isEnabled)
        first.tap()
        second.tap()
        XCTAssertEqual(selected.label, "2 selected")
        screenshot(app, "record-multi-selection")
        trash.tap()
        XCTAssertTrue(app.staticTexts["Delete 2 items?"].waitForExistence(timeout: 5))
        screenshot(app, "record-multi-delete-confirmation")
        app.buttons["closeConfirmation"].tap()
        XCTAssertTrue(selected.waitForExistence(timeout: 5))
        XCTAssertEqual(selected.label, "2 selected")
        close.tap()
        XCTAssertTrue(record.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["row-Her"].exists)
        XCTAssertTrue(tab(.blue, in: app).isHittable)

        app.buttons["collectionOptions"].tap()
        selectLabel.tap()
        XCTAssertTrue(selected.waitForExistence(timeout: 5))
        first.tap()
        second.tap()
        XCTAssertEqual(selected.label, "2 selected")
        trash.tap()
        XCTAssertTrue(app.staticTexts["Delete 2 items?"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["confirmDelete"].waitForExistence(timeout: 5))
        app.buttons["confirmDelete"].tap()
        XCTAssertTrue(app.staticTexts["10 items"].waitForExistence(timeout: 5))
        XCTAssertFalse(record.exists)
        XCTAssertFalse(app.buttons["row-Her"].exists)
        XCTAssertTrue(app.buttons["row-Arrival"].exists)
        XCTAssertTrue(tab(.blue, in: app).isHittable)
    }

    @MainActor func testRestaurantIndicatorsAndBYOKSettings() {
        let app = launch()
        app.buttons["settingsButton"].tap()
        XCTAssertTrue(app.secureTextFields["assistantAPIKey"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["assistantProvider"].exists)
        XCTAssertTrue(app.buttons["assistantModel"].exists)
        XCTAssertFalse(app.staticTexts["Web search"].exists)
        screenshot(app, "assistant-byok-settings")
        app.buttons["closeSheet"].tap()
        XCTAssertTrue(app.secureTextFields["assistantAPIKey"].waitForNonExistence(timeout: 5))
        app.buttons["collection-template.restaurants"].tap()
        let restaurant = app.buttons["row-Bar Brutal"]
        XCTAssertTrue(restaurant.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["option-status-visited"].firstMatch.isEnabled)
        restaurant.tap()
        let visited = app.buttons["option-status-visited"].firstMatch
        let favorite = app.buttons.matching(NSPredicate(format: "label == %@", "Favorite")).firstMatch
        XCTAssertTrue(visited.exists)
        XCTAssertTrue(favorite.exists)
        let before = favorite.value as? String
        favorite.tap()
        XCTAssertNotEqual(favorite.value as? String, before)
        favorite.tap()
        XCTAssertEqual(favorite.value as? String, before)
        screenshot(app, "restaurants-indicators")
    }

    @MainActor func testBlueSearchWithoutLocalModel() {
        let app = XCUIApplication()
        app.launchArguments = ["--uitest", "--uitest-reset", "--test-library-search"]
        app.launch()
        XCTAssertTrue(tab(.blue, in: app).waitForExistence(timeout: 20))
        spanish(app)
        tab(.blue, in: app).tap()
        let input = app.descendants(matching: .any)["assistantInput"].firstMatch
        XCTAssertTrue(input.waitForExistence(timeout: 5))
        XCTAssertEqual(input.placeholderValue, "Buscar en Blue")
        XCTAssertFalse(app.staticTexts["Este iPhone no admite Apple Intelligence."].exists)
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
        let movies = app.buttons["collection-template.movies"]
        movies.press(forDuration: 1)
        let deleteCollection = app.buttons["Eliminar"]
        XCTAssertTrue(deleteCollection.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Archivar"].exists)
        screenshot(app, "collection-context-menu-spanish")
        app.staticTexts["sectionTitle"].tap()
        XCTAssertTrue(deleteCollection.waitForNonExistence(timeout: 5))
        movies.tap()
        screenshot(app, "collection-spanish")
        for id in ["collectionOptions", "newRecord"] {
            let button = app.buttons[id]
            XCTAssertTrue(button.exists)
            XCTAssertGreaterThanOrEqual(button.frame.height.rounded(), 44, id)
        }
        let record = app.buttons["row-Interstellar"]
        XCTAssertTrue(record.waitForExistence(timeout: 5))
        record.press(forDuration: 1)
        let detail = app.textFields["recordTitle"]
        XCTAssertTrue(detail.waitForExistence(timeout: 5))
        screenshot(app, "record-long-press-spanish")
        app.buttons["closeSheet"].tap()
        XCTAssertTrue(detail.waitForNonExistence(timeout: 5))
        app.buttons["collectionOptions"].tap()
        let select = app.buttons["Seleccionar elementos"]
        XCTAssertTrue(select.waitForExistence(timeout: 5))
        screenshot(app, "collection-options-spanish")
        select.tap()
        let count = app.staticTexts["selectedRecordCount"]
        XCTAssertTrue(count.waitForExistence(timeout: 5))
        XCTAssertEqual(count.label, "0 seleccionados")
        app.buttons["select-record-Interstellar"].tap()
        XCTAssertEqual(count.label, "1 seleccionado")
        screenshot(app, "record-multi-selection-spanish")
        app.buttons["cancelRecordSelection"].tap()
        XCTAssertTrue(record.waitForExistence(timeout: 5))
        XCTAssertGreaterThanOrEqual(tab(.blue, in: app).frame.height.rounded(), 44)
        tab(.blue, in: app).tap()
        XCTAssertTrue(app.descendants(matching: .any)["assistantInput"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["closeAssistant"].exists)
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
