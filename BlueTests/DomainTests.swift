import Foundation
import Testing

@testable import Blue

struct DomainTests {
    @Test func readQuestionsAndNegationsCannotAuthorizeWrites() {
        for prompt in [
            "What rating did I give Interstellar?", "¿Qué puntuación le puse a Interstellar?", "Don't change Dune",
            "Don’t change Dune", "Never change Dune",
            "No cambies la nota", "Why did you change this?",
        ] {
            #expect(!MutationIntent.isExplicit(prompt))
        }
        for prompt in [
            "Change Interstellar's rating to 10", "Ponle un 8,5 a Interstellar", "¿Puedes crear una nota?",
            "Make a hiking collection",
        ] {
            #expect(MutationIntent.isExplicit(prompt))
        }
    }
    @Test func ratingsRejectInvalidNumbers() throws {
        let field = FieldDefinition(id: "rating", label: .key("field.rating"), kind: .rating)
        #expect(throws: BlueError.invalidValue) { try Validation.field(field, value: .number(11)) }
        #expect(throws: BlueError.invalidValue) { try Validation.field(field, value: .number(.nan)) }
        #expect(throws: BlueError.invalidValue) { try Validation.field(field, value: .text("9")) }
        try Validation.field(field, value: .number(9))
    }
    @Test func numericSortKeepsMissingValuesLastAndStable() {
        let id = UUID()
        let records = [
            Record(collectionID: id, title: "Ten", values: ["rating": .number(10)]),
            Record(collectionID: id, title: "Two", values: ["rating": .number(2)]),
            Record(collectionID: id, title: "Missing"),
        ]
        let query = CollectionQuery(sortField: "rating", ascending: false)
        #expect(
            query.apply(to: records, fields: [], locale: .init(identifier: "en_US")).map(\.title) == [
                "Ten", "Two", "Missing",
            ])
        let ascending = CollectionQuery(sortField: "rating")
        #expect(ascending.apply(to: records, fields: [], locale: .current).map(\.title) == ["Two", "Ten", "Missing"])
    }
    @Test func filtersCombineTypedValues() {
        let id = UUID()
        let records = [
            Record(collectionID: id, title: "One", values: ["rating": .number(9), "status": .option("watched")]),
            Record(collectionID: id, title: "Two", values: ["rating": .number(10), "status": .option("pending")]),
        ]
        let query = CollectionQuery(filters: [
            RecordFilter(fieldID: "rating", minimum: 8), RecordFilter(fieldID: "status", text: "watched"),
        ])
        #expect(query.apply(to: records, fields: [], locale: .current).map(\.title) == ["One"])
        #expect(records.count == 2)
    }
    @Test func folderHierarchyRejectsThirdLevel() throws {
        let root = Folder(title: .user("Root"))
        let child = Folder(title: .user("Child"), parentID: root.id)
        try Validation.folder(parentID: root.id, in: [root, child])
        #expect(throws: BlueError.folderDepth) { try Validation.folder(parentID: child.id, in: [root, child]) }
    }
    @Test func collectionRejectsDuplicateFields() {
        let field = FieldDefinition(id: "same", label: .user("Name"), kind: .text)
        let collection = Collection(folderID: UUID(), title: .user("Ideas"), fields: [field, field])
        #expect(throws: BlueError.invalidValue) { try Validation.collection(collection) }
    }
    @Test func starterCollectionsHaveIndependentNotesAndRatings() {
        let state = StarterLibrary.make()
        #expect(state.folders.count == 6)
        #expect(state.collections.count == 6)
        let movie = state.records.first { $0.title == "Interstellar" }!
        #expect(movie.values["rating"] == .number(9))
        #expect(movie.markdown.key == "demo.interstellar")
    }
}

@MainActor
struct PersistenceTests {
    @Test func recordEditSurvivesRelaunchAndDoesNotReseed() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appending(path: "test.store")
        let id: UUID
        do {
            let store = try LibraryStore(url: url)
            let record = store.state.records.first { $0.title == "Interstellar" }!
            id = record.id
            try store.setValue(recordID: id, fieldID: "rating", value: .number(10), revision: record.revision)
            try store.update { $0.records.removeAll { $0.title == "Dune" } }
        }
        let reopened = try LibraryStore(url: url)
        #expect(reopened.record(id)?.values["rating"] == .number(10))
        #expect(!reopened.state.records.contains { $0.title == "Dune" })
        #expect(reopened.state.collections.count == 6)
    }
    @Test func staleEditCannotOverwriteNewValue() throws {
        let store = try LibraryStore(inMemory: true)
        let record = store.state.records.first { $0.title == "Dune" }!
        try store.setValue(recordID: record.id, fieldID: "rating", value: .number(9), revision: 0)
        #expect(throws: BlueError.staleRevision) {
            try store.setValue(recordID: record.id, fieldID: "rating", value: .number(3), revision: 0)
        }
        #expect(store.record(record.id)?.values["rating"] == .number(9))
    }
    @Test func deletingAllContentDoesNotReseedOnRelaunch() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appending(path: "test.store")
        do {
            let store = try LibraryStore(url: url)
            try store.update { $0 = LibraryState() }
        }
        let reopened = try LibraryStore(url: url)
        #expect(reopened.state.records.isEmpty)
        #expect(reopened.state.folders.isEmpty)
    }
    @Test func undoRestoresRecordsButPreservesSystemAlarmState() throws {
        let store = try LibraryStore(inMemory: true)
        let before = store.state.records.count
        try store.update { $0.records.removeFirst() }
        let alarm = SavedAlarm(title: "Test", date: Date().addingTimeInterval(3600))
        try store.update(undoable: false) { $0.alarms.append(alarm) }
        try store.undo()
        #expect(store.state.records.count == before)
        #expect(store.state.alarms == [alarm])
    }
    @Test func exactNavigationRemovesOnlyConflictingFilters() throws {
        let store = try LibraryStore(inMemory: true)
        let record = store.state.records.first { $0.title == "Interstellar" }!
        let navigation = NavigationState()
        navigation.queries[record.collectionID] = CollectionQuery(
            sortField: "rating", ascending: false,
            filters: [RecordFilter(fieldID: "rating", minimum: 8), RecordFilter(fieldID: "status", text: "wantWatch")])
        navigation.jump(to: record, store: store, locale: .current)
        #expect(navigation.path == [.collection(record.collectionID)])
        #expect(navigation.highlightedRecord == record.id)
        #expect(navigation.queries[record.collectionID]?.sortField == "rating")
        #expect(navigation.queries[record.collectionID]?.filters.map(\.fieldID) == ["rating"])
    }
    @Test func exportIsVersionedAndRoundTripsTypedData() throws {
        let store = try LibraryStore(inMemory: true)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let exported = try decoder.decode(LibraryState.self, from: store.export())
        #expect(exported.formatVersion == 2)
        #expect(exported.records.map(\.values) == store.state.records.map(\.values))
    }
    @Test func readOnlyContextRejectsModelInitiatedMutation() throws {
        let store = try LibraryStore(inMemory: true)
        let context = ToolContext(
            store: store, alarms: AlarmService(store: store, scheduler: FakeScheduler()), language: .english,
            previous: nil)
        #expect(!context.mutationsAllowed)
        _ = try context.search("Interstellar")
        let record = store.state.records.first { $0.title == "Interstellar" }!
        #expect(throws: BlueError.unsupported) {
            try context.edit(id: record.id, fieldID: "rating", value: .number(10))
        }
        #expect(store.record(record.id)?.values["rating"] == .number(9))
    }
    @Test func ambiguousToolReadCannotBeEdited() throws {
        let store = try LibraryStore(inMemory: true)
        let original = store.state.records.first { $0.title == "Dune" }!
        try store.saveRecord(Record(collectionID: original.collectionID, title: "Dune"), expectedRevision: nil)
        let context = ToolContext(
            store: store, alarms: AlarmService(store: store, scheduler: FakeScheduler()), language: .english,
            previous: nil)
        context.mutationsAllowed = true
        _ = try context.search("Dune")
        #expect(throws: BlueError.ambiguous) {
            try context.edit(id: original.id, fieldID: "rating", value: .number(10))
        }
        #expect(store.record(original.id)?.values["rating"] == .number(8))
    }
    @Test func toolsRejectSecondMutationAndCancelledRequests() throws {
        let store = try LibraryStore(inMemory: true)
        let record = store.state.records.first { $0.title == "Interstellar" }!
        let context = ToolContext(
            store: store, alarms: AlarmService(store: store, scheduler: FakeScheduler()), language: .english,
            previous: nil)
        context.mutationsAllowed = true
        _ = try context.search("Interstellar")
        _ = try context.edit(id: record.id, fieldID: "rating", value: .number(10))
        #expect(throws: BlueError.staleRevision) {
            try context.edit(id: record.id, fieldID: "rating", value: .number(3))
        }
        context.active = false
        #expect(throws: BlueError.cancelled) { try context.search("Dune") }
    }
    @Test func assistantRejectsInvalidCollectionFilters() async throws {
        let store = try LibraryStore(inMemory: true)
        let context = ToolContext(
            store: store, alarms: AlarmService(store: store, scheduler: FakeScheduler()), language: .english,
            previous: nil)
        let tool = CollectionQueryTool(context: context)
        await #expect(throws: BlueError.invalidValue) {
            try await tool.call(
                arguments: .init(
                    collectionName: "Movies", sortFieldID: "rating", ascending: false,
                    filters: [.init(fieldID: "status", text: "invented", minimum: nil, maximum: nil, selected: nil)]))
        }
        _ = try await tool.call(
            arguments: .init(
                collectionName: "Movies", sortFieldID: "rating", ascending: false,
                filters: [.init(fieldID: "status", text: "watched", minimum: nil, maximum: nil, selected: nil)]))
        guard case .collectionView(let id, let query) = context.result else {
            Issue.record("Expected a validated collection query")
            return
        }
        #expect(query.filters.first?.text == "watched")
        #expect(!query.apply(to: store.records(in: id), fields: store.collection(id)!.fields, locale: .current).isEmpty)
        _ = try await tool.call(
            arguments: .init(
                collectionName: "Movies", sortFieldID: "title", ascending: true,
                filters: [.init(fieldID: "__favorite", text: nil, minimum: nil, maximum: nil, selected: true)]))
        guard case .collectionView(_, let favorites) = context.result else {
            Issue.record("Expected a universal favorite filter")
            return
        }
        #expect(favorites.filters.first?.fieldID == "__favorite")
        #expect(
            favorites.apply(to: store.records(in: id), fields: store.collection(id)!.fields, locale: .current)
                .allSatisfy { $0.isFavorite })
    }
    @Test func modelFailureUsesLocalizedAvailabilityMessage() {
        let error = NSError(domain: "com.apple.UnifiedAssetFramework", code: 5000)
        #expect(AssistantService.errorKey(error) == "assistant.modelNotReady")
        #expect(AssistantService.errorKey(BlueError.permissionDenied) == "error.permissionDenied")
    }
    @Test func cancellingAnAssistantRequestDoesNotOverwriteItsReplacement() async throws {
        let store = try LibraryStore(inMemory: true)
        let alarms = AlarmService(store: store, scheduler: FakeScheduler())
        let assistant = AssistantService(testMode: true)
        assistant.input = "Find Dune"
        assistant.submit(store: store, alarms: alarms, language: .english)
        assistant.cancel()
        assistant.input = "Find Interstellar"
        assistant.submit(store: store, alarms: alarms, language: .english)
        try await Task.sleep(for: .seconds(1))
        guard case .records(let ids, _) = assistant.result else {
            Issue.record("Replacement result was lost")
            return
        }
        #expect(ids.count == 1)
        #expect(store.record(ids[0])?.title == "Interstellar")
        #expect(!assistant.busy)
    }

    @Test func folderMigrationPreservesCollectionsAndGroupedNotes() throws {
        var original = StarterLibrary.make()
        let folder = original.folders[0]
        let note = Note(folderID: folder.id, title: .user("Keep me"), markdown: .user("Private draft"), favorite: true)
        original.notes.append(note)
        let migrated = LibraryStore.flattened(original)
        #expect(migrated.folders.isEmpty)
        #expect(migrated.collections.count == original.collections.count)
        #expect(migrated.collections.allSatisfy { $0.folderID == nil })
        #expect(migrated.records.first { $0.id == note.id }?.markdown == note.markdown)
        #expect(migrated.records.first { $0.id == note.id }?.favorite == true)
        #expect(migrated.notes.count == original.notes.count - 1)
        #expect(LibraryStore.flattened(migrated) == migrated)
        let store = try LibraryStore(inMemory: true)
        let before = store.state
        try store.update { $0.records.removeFirst() }
        try store.undo()
        #expect(store.state == before)
    }

    @Test func captureAndAdaptiveFieldsAreAtomicAndTyped() async throws {
        let store = try LibraryStore(inMemory: true, seed: false)
        let context = ToolContext(
            store: store, alarms: AlarmService(store: store, scheduler: FakeScheduler()), language: .english,
            previous: nil)
        context.mutationsAllowed = true
        context.lookup = { _ in throw BlueError.webUnavailable }
        let capture = CaptureItemTool(context: context)
        _ = try await capture.call(
            arguments: .init(
                collectionName: "Places", title: "Small bookshop", markdown: "Visit on Saturday", fields: [],
                values: [], lookupPublicFacts: true))
        #expect(store.state.collections.count == 1)
        #expect(store.state.folders.isEmpty)
        let record = try #require(store.state.records.first)
        #expect(record.sources == nil)
        #expect(record.markdown == .user("Visit on Saturday"))
        let update = ToolContext(
            store: store, alarms: AlarmService(store: store, scheduler: FakeScheduler()), language: .english,
            previous: record.id)
        update.mutationsAllowed = true
        _ = try await AdaptItemTool(context: update).call(
            arguments: .init(
                recordID: record.id.uuidString,
                fields: [
                    .init(
                        id: "distance", english: "Distance", spanish: "Distancia", kind: .number, showInRow: true,
                        options: [])
                ],
                values: [.init(fieldID: "distance", value: "3,5")]))
        #expect(store.record(record.id)?.values["distance"] == .number(3.5))
        #expect(store.record(record.id)?.markdown == record.markdown)
        let repeated = ToolContext(
            store: store, alarms: AlarmService(store: store, scheduler: FakeScheduler()), language: .english,
            previous: record.id)
        repeated.mutationsAllowed = true
        repeated.sourcePrompt = "Change distance to 4"
        _ = try await AdaptItemTool(context: repeated).call(
            arguments: .init(
                recordID: record.id.uuidString,
                fields: [
                    .init(
                        id: "distance", english: "Distance", spanish: "Distancia", kind: .text, showInRow: true,
                        options: [])
                ],
                values: [.init(fieldID: "distance", value: "4")]))
        #expect(store.record(record.id)?.values["distance"] == .number(4))
        #expect(store.collection(record.collectionID)?.fields.first?.kind == .number)
        let denied = ToolContext(
            store: store, alarms: AlarmService(store: store, scheduler: FakeScheduler()), language: .english,
            previous: record.id)
        let before = store.state
        await #expect(throws: BlueError.unsupported) {
            try await AdaptItemTool(context: denied).call(
                arguments: .init(recordID: record.id.uuidString, fields: [], values: []))
        }
        #expect(store.state == before)
    }

    @Test func schemaIconsPersistAndDestructiveChangesNeedConfirmation() async throws {
        let store = try LibraryStore(inMemory: true)
        let original = try #require(store.state.collections.first)
        let context = ToolContext(
            store: store, alarms: AlarmService(store: store, scheduler: FakeScheduler()), language: .english,
            previous: nil)
        context.mutationsAllowed = true
        context.readCollections[original.id] = original
        _ = try await ModifyCollectionTool(context: context).call(
            arguments: .init(
                collectionID: original.id.uuidString, title: nil, icon: "🚬",
                fields: [
                    .init(
                        id: "bass", english: "Bass", spanish: "Bass", kind: .checkbox, showInRow: true, icon: "🗿",
                        tint: .purple, options: [])
                ], removeFieldIDs: []))
        let updated = try #require(store.collection(original.id))
        #expect(updated.symbol == "🚬")
        #expect(updated.fields.first { $0.id == "bass" }?.icon == "🗿")
        #expect(updated.fields.first { $0.id == "bass" }?.tint == .purple)
        let removing = ToolContext(
            store: store, alarms: AlarmService(store: store, scheduler: FakeScheduler()), language: .english,
            previous: nil)
        removing.mutationsAllowed = true
        removing.readCollections[updated.id] = updated
        _ = try await ModifyCollectionTool(context: removing).call(
            arguments: .init(
                collectionID: updated.id.uuidString, title: nil, icon: nil, fields: [], removeFieldIDs: ["rating"]))
        #expect(store.collection(updated.id)?.fields.contains { $0.id == "rating" } == true)
        guard case .confirmCollectionChange(let change) = removing.result else {
            Issue.record("Missing deletion review")
            return
        }
        #expect(!change.proposed.fields.contains { $0.id == "rating" })
        #expect(!removing.didMutate)
    }

    @Test func numericEvidencePreservesSpanishDecimals() {
        #expect(UserValueEvidence.contains(number: 8.5, in: "Ponle un 8,5"))
        #expect(!UserValueEvidence.contains(number: 85, in: "Ponle un 8,5"))
        #expect(UserValueEvidence.contains(number: 5, in: "Save distance five"))
    }

    @Test func favoritesDecodeOldRecordsAndPersistNewOnes() throws {
        let store = try LibraryStore(inMemory: true)
        var record = try #require(store.state.records.first)
        record.favorite = true
        try store.saveRecord(record, expectedRevision: record.revision)
        #expect(store.record(record.id)?.isFavorite == true)
        var encoded = try JSONSerialization.jsonObject(with: JSONEncoder().encode(record)) as! [String: Any]
        encoded.removeValue(forKey: "favorite")
        encoded.removeValue(forKey: "sources")
        let old = try JSONDecoder().decode(Record.self, from: JSONSerialization.data(withJSONObject: encoded))
        #expect(old.favorite == nil)
        #expect(old.sources == nil)
    }
    @Test func propertyChangePreservesCompatibleValues() throws {
        let store = try LibraryStore(inMemory: true)
        let record = store.state.records.first { $0.title == "Interstellar" }!
        var collection = store.collection(record.collectionID)!
        collection.fields.removeAll { $0.id == "rating" }
        try store.saveCollection(collection)
        #expect(store.record(record.id)?.values["rating"] == nil)
        #expect(store.record(record.id)?.values["status"] == .option("watched"))
        #expect(store.record(record.id)?.markdown == record.markdown)
    }
}

@MainActor
final class FakeScheduler: AlarmScheduling {
    var ids: Set<UUID> = []
    var denial = false
    var failure = false
    func authorize() async throws { if denial { throw BlueError.permissionDenied } }
    func schedule(_ alarm: SavedAlarm) async throws {
        if failure { throw BlueError.alarmFailed }
        ids.insert(alarm.id)
    }
    func cancel(_ id: UUID) throws {
        if failure { throw BlueError.alarmFailed }
        ids.remove(id)
    }
    func scheduledIDs() throws -> Set<UUID> { ids }
}

@MainActor
struct AlarmTests {
    @Test func permissionDenialDoesNotSaveEnabledAlarm() async throws {
        let store = try LibraryStore(inMemory: true)
        let scheduler = FakeScheduler()
        scheduler.denial = true
        let service = AlarmService(store: store, scheduler: scheduler)
        let alarm = SavedAlarm(title: "Coffee", date: Date().addingTimeInterval(3600), enabled: true)
        await #expect(throws: BlueError.permissionDenied) { try await service.save(alarm) }
        #expect(store.state.alarms.isEmpty)
    }
    @Test func schedulingFailurePreservesExistingState() async throws {
        let store = try LibraryStore(inMemory: true)
        let scheduler = FakeScheduler()
        let service = AlarmService(store: store, scheduler: scheduler)
        let alarm = SavedAlarm(title: "Coffee", date: Date().addingTimeInterval(3600))
        try await service.save(alarm)
        var edit = store.state.alarms[0]
        edit.enabled = true
        scheduler.failure = true
        await #expect(throws: BlueError.alarmFailed) { try await service.save(edit) }
        #expect(store.state.alarms[0].enabled == false)
    }
    @Test func cancellationAndReconciliationMatchSystem() async throws {
        let store = try LibraryStore(inMemory: true)
        let scheduler = FakeScheduler()
        let service = AlarmService(store: store, scheduler: scheduler)
        let alarm = SavedAlarm(title: "Coffee", date: Date().addingTimeInterval(3600), enabled: true)
        try await service.save(alarm)
        #expect(scheduler.ids.contains(alarm.id))
        #expect(store.state.alarms[0].enabled)
        scheduler.ids.removeAll()
        service.reconcile()
        #expect(!store.state.alarms[0].enabled)
        try await service.delete(store.state.alarms[0])
        #expect(store.state.alarms.isEmpty)
    }
    @Test func timeZoneChangesPreserveWeeklyWallClockAndFixedInstants() throws {
        let store = try LibraryStore(inMemory: true)
        let scheduler = FakeScheduler()
        let date = Date(timeIntervalSince1970: 1_794_225_600)
        let weekly = SavedAlarm(title: "Weekly", date: date, weekdays: [2], timeZoneID: "Europe/Madrid")
        let fixed = SavedAlarm(title: "Fixed", date: date, timeZoneID: "Europe/Madrid")
        try store.update(undoable: false) { $0.alarms = [weekly, fixed] }
        let target = TimeZone(identifier: "America/New_York")!
        AlarmService(store: store, scheduler: scheduler).reconcile(timeZone: target, now: date)
        var oldCalendar = Calendar(identifier: .gregorian)
        oldCalendar.timeZone = TimeZone(identifier: "Europe/Madrid")!
        var newCalendar = Calendar(identifier: .gregorian)
        newCalendar.timeZone = target
        #expect(
            oldCalendar.component(.hour, from: weekly.date)
                == newCalendar.component(.hour, from: store.state.alarms[0].date))
        #expect(store.state.alarms[1].date == date)
        #expect(store.state.alarms.allSatisfy { $0.timeZoneID == target.identifier })
    }
    @Test func repeatingAlarmsAppearOnSelectedWeekday() async throws {
        let store = try LibraryStore(inMemory: true)
        let scheduler = FakeScheduler()
        let service = AlarmService(store: store, scheduler: scheduler)
        let monday = Date(timeIntervalSince1970: 1_794_225_600)
        let weekday = Calendar.current.component(.weekday, from: monday)
        let alarm = SavedAlarm(title: "Weekly", date: monday, weekdays: [weekday])
        try await service.save(alarm)
        #expect(service.alarms(on: monday).count == 1)
        #expect(service.alarms(on: monday.addingTimeInterval(86400)).isEmpty)
    }
}
