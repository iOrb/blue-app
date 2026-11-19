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
