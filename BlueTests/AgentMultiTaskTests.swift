import Foundation
import Testing

@testable import Blue

@MainActor
struct AgentMultiTaskTests {
    @Test func renamesAnExistingAlarmAndEditsANoteInOneRequest() async throws {
        let store = try LibraryStore(inMemory: true, seed: false)
        let scheduler = FakeScheduler()
        let notifications = FakeEventNotifications()
        let alarms = AlarmService(store: store, scheduler: scheduler, notifications: notifications)
        let event = CalendarEvent(title: "Old name", date: .now.addingTimeInterval(3600), weekdays: [2, 4])
        try await alarms.saveTimedEvent(event, expectedRevision: nil)
        let note = Note(title: .user("Ideas"), markdown: .user("Before"))
        try store.saveNote(note, expectedRevision: nil)
        let date = try #require(store.state.events?.first?.date)
        var agent = ConnectedLibraryAgent(
            store: store, alarms: alarms, language: .spanish,
            selected: ["event": event.id, "note": note.id])
        var requests = 0
        let result = try await agent.run("Renombra esa alarma a Café y cambia la nota a Después", history: []) {
            prompt in
            requests += 1
            switch requests {
            case 1:
                return #"{"action":"update","kind":"event","id":"\#(event.id.uuidString)","title":"Café"}"#
            case 2:
                #expect(prompt.contains("saved"))
                return #"{"action":"update","kind":"note","id":"\#(note.id.uuidString)","body":"Después"}"#
            default:
                return #"{"action":"answer","text":"Hecho."}"#
            }
        } search: { _ in
            []
        }
        #expect(requests == 3)
        #expect(result == .answer("Hecho."))
        #expect(store.state.events?.count == 1)
        #expect(store.state.events?.first?.title == "Café")
        #expect(store.state.events?.first?.date == date)
        #expect(store.state.events?.first?.repeatDays == [2, 4])
        #expect(store.state.notes.first?.markdown.english == "Después")
    }
    @Test func canPinAndMoveExistingEntriesWithoutLosingValues() async throws {
        let store = try LibraryStore(inMemory: true, seed: false)
        let alarms = AlarmService(store: store, scheduler: FakeScheduler(), notifications: FakeEventNotifications())
        let field = FieldDefinition(id: "rating", label: .user("Rating"), kind: .rating)
        let origin = try store.createCollection(title: "Origin", fields: [field])
        let target = try store.createCollection(title: "Target", fields: [field])
        let incompatible = try store.createCollection(title: "Incompatible", fields: [])
        let record = Record(collectionID: origin, title: "Example", values: ["rating": .number(8)])
        try store.saveRecord(record, expectedRevision: nil)
        let note = Note(title: .user("Ideas"), markdown: .user("Keep this"))
        try store.saveNote(note, expectedRevision: nil)

        var blue = ConnectedLibraryAgent(
            store: store, alarms: alarms, language: .english,
            selected: ["collection": incompatible, "record": record.id, "note": note.id])
        let rejected = Data(
            #"{"action":"update","kind":"record","id":"\#(record.id)","collectionID":"\#(incompatible)"}"#.utf8)
        await #expect(throws: BlueError.invalidValue) { try await blue.executeVoice(rejected) }
        #expect(store.record(record.id)?.collectionID == origin)

        blue = ConnectedLibraryAgent(
            store: store, alarms: alarms, language: .english,
            selected: ["collection": target, "record": record.id, "note": note.id])
        let move = Data(#"{"action":"update","kind":"record","id":"\#(record.id)","collectionID":"\#(target)"}"#.utf8)
        _ = try await blue.executeVoice(move)
        let pin = Data(#"{"action":"update","kind":"note","id":"\#(note.id)","pinned":true,"favorite":true}"#.utf8)
        _ = try await blue.executeVoice(pin)
        #expect(store.record(record.id)?.collectionID == target)
        #expect(store.record(record.id)?.values["rating"] == .number(8))
        #expect(store.state.notes.first?.pinned == true)
        #expect(store.state.notes.first?.favorite == true)
        #expect(store.state.notes.first?.markdown.english == "Keep this")
    }

}

struct VoiceTurnRecoveryTests {
    @Test func failedResponseDoesNotEndTheVoiceSession() throws {
        let wire = VoiceProtocol(
            connection: .init(provider: .openai, model: "gpt-5-mini", key: "test"), model: "gpt-live-1")
        let events = try wire.events(Data(#"{"type":"response.event","event":{"type":"response.failed"}}"#.utf8))
        #expect(events == [.turnFailed(.webUnavailable)])
        #expect(try wire.events(Data(#"{"type":"session.closed"}"#.utf8)) == [.closed])
    }
}
