import Foundation
import Testing

@testable import Blue

@MainActor struct SemanticLibraryTests {
    private func context(_ store: LibraryStore, writes: Bool = true) -> ToolContext {
        let context = ToolContext(
            store: store, alarms: AlarmService(store: store, scheduler: FakeScheduler()), language: .spanish,
            previous: nil)
        context.mutationsAllowed = writes
        return context
    }
    @Test func calendarPersistsAndRejectsStaleEditsAndDeletion() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "events.store")
        let store = try LibraryStore(url: url, seed: false)
        var event = CalendarEvent(title: "Dinner", date: Date(), day: "2026-11-08")
        try store.saveEvent(event, expectedRevision: nil)
        let pending = PendingDeletion(kind: "event", id: event.id, revision: 0)
        event.title = "Dinner together"
        try store.saveEvent(event, expectedRevision: 0)
        #expect(throws: BlueError.staleRevision) { try store.confirmDeletion(pending) }
        #expect(throws: BlueError.staleRevision) { try store.saveEvent(event, expectedRevision: 0) }
        let reopened = try LibraryStore(url: url, seed: false)
        #expect(reopened.state.events?.first?.title == "Dinner together")
        try store.confirmDeletion(PendingDeletion(kind: "event", id: event.id, revision: 1))
        #expect(store.state.events?.isEmpty == true)
    }
    @Test func deletionIsOnlyAProposalAndNeedsAnExactRead() async throws {
        let store = try LibraryStore(inMemory: true)
        let record = try #require(store.state.records.first)
        let context = context(store)
        _ = try await ReadLibraryTool(context: context).call(
            arguments: .init(kind: .record, ids: [record.id.uuidString], offset: 0, fields: ["rating"]))
        _ = try await ProposeDeletionTool(context: context).call(
            arguments: .init(kind: .record, id: record.id.uuidString))
        #expect(store.record(record.id) != nil)
        guard case .confirmDeletion(let pending) = context.result else {
            Issue.record("Missing confirmation")
            return
        }
        try store.confirmDeletion(pending)
        #expect(store.record(record.id) == nil)
        #expect(throws: BlueError.staleRevision) {
            try store.confirmDeletion(PendingDeletion(kind: "note", id: UUID()))
        }
    }
    @Test func readOnlyCalendarCannotMutate() async throws {
        let store = try LibraryStore(inMemory: true, seed: false)
        let context = context(store, writes: false)
        await #expect(throws: BlueError.unsupported) {
            try await CalendarEventsTool(context: context).call(
                arguments: .init(
                    action: .create, title: "Dinner", dateISO8601: "2026-11-08T20:00:00+01:00", day: "2026-11-08",
                    allDay: false, color: .blue))
        }
        #expect(store.state.events?.isEmpty == true)
    }
    @Test func emptyFieldRemovalStillNeedsConfirmation() async throws {
        let store = try LibraryStore(inMemory: true, seed: false)
        let id = try store.createCollection(
            title: "Films", fields: [FieldDefinition(id: "director", label: .user("Director"), kind: .text)])
        let context = context(store)
        context.readCollections[id] = store.collection(id)
        _ = try await ModifyCollectionTool(context: context).call(
            arguments: .init(collectionID: id.uuidString, fields: [], removeFieldIDs: ["director"]))
        guard case .confirmCollectionChange = context.result else {
            Issue.record("Missing confirmation")
            return
        }
        #expect(store.collection(id)?.fields.count == 1)
    }
    @Test func presentationMetadataValidatesAndDecodesOlderFields() throws {
        let old = FieldDefinition(id: "score", label: .user("Score"), kind: .number)
        var field = old
        field.minimum = 1
        field.maximum = 5
        field.step = 1
        try Validation.collection(Collection(title: .user("Films"), fields: [field]))
        #expect(throws: BlueError.invalidValue) { try Validation.field(field, value: .number(6)) }
        field.step = 0
        #expect(throws: BlueError.invalidValue) {
            try Validation.collection(Collection(title: .user("Films"), fields: [field]))
        }
        let data = try JSONEncoder().encode(old)
        #expect(try JSONDecoder().decode(FieldDefinition.self, from: data).minimum == nil)
    }
}
