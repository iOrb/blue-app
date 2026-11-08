import Foundation
import FoundationModels

// Real production model/store/tools. AlarmKit is deliberately unavailable on macOS.
@MainActor final class AlarmService {
    func alarms(on date: Date) -> [SavedAlarm] { [] }
    func save(_ alarm: SavedAlarm) async throws { throw BlueError.unsupported }
}
@main struct MacModelIntegration {
    @MainActor static func ask(_ assistant: AssistantService, _ store: LibraryStore, _ prompt: String, _ label: String, language: AppLanguage = .spanish) async throws {
        let start = ContinuousClock.now
        assistant.input = prompt
        assistant.submit(store: store, alarms: AlarmService(), language: language)
        while assistant.busy {
            guard start.duration(to: .now) < .seconds(110) else { assistant.cancel(); throw BlueError.cancelled }
            try await Task.sleep(for: .milliseconds(100))
        }
        print("MODEL_CASE=\(label) elapsed=\(start.duration(to: .now)) result=\(String(describing: assistant.result))")
    }
    @MainActor static func main() async {
        do {
            print("PRODUCTION_MAC_MODEL_AVAILABILITY=\(SystemLanguageModel.default.availability)")
            guard SystemLanguageModel.default.isAvailable else { throw BlueError.modelUnavailable }
            let directory = FileManager.default.temporaryDirectory.appending(path: "blue-semantic-\(UUID())")
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: directory) }
            let url = directory.appending(path: "library.store")
            let store = try LibraryStore(url: url)
            let assistant = AssistantService()
            let record = store.state.records.first { $0.title == "Interstellar" }!
            var before = store.state
            try await ask(assistant, store, "¿Qué puntuación tiene Interstellar?", "named-read")
            guard case .selection(let namedRead) = assistant.result, namedRead.records == [record.id], namedRead.fields == ["rating"], store.state == before else { throw BlueError.invalidValue }
            assistant.selectRecord(record.id)
            try await ask(assistant, store, "¿Qué nota tiene?", "read-selected")
            guard store.state == before else { throw BlueError.invalidValue }
            guard case .selection(let read) = assistant.result, read.records == [record.id] else { throw BlueError.missing }
            try await ask(assistant, store, "A esa le daría un ocho y medio", "implicit-spanish-rating")
            guard store.record(record.id)?.values["rating"] == .number(8.5) else { throw BlueError.invalidValue }
            let reopened = try LibraryStore(url: url)
            guard reopened.record(record.id)?.values["rating"] == .number(8.5) else { throw BlueError.saveFailed }
            before = store.state
            try await ask(assistant, store, "Déjala como está, no cambies nada.", "negated-write")
            guard store.state == before else { throw BlueError.invalidValue }
            let note = Note(title: .user("Walk"), markdown: .user("# Weekend\n\nWalk by the river.\n\nWe will take a very long and leisurely walk through the green and pleasant gardens after lunch."))
            try store.saveNote(note, expectedRevision: nil); assistant.selectNote(note.id)
            try await ask(assistant, store, "Haz el segundo párrafo más corto", "open-note-context")

            let changedNote = store.state.notes.first { $0.id == note.id }
            let notePassed = changedNote?.revision == 1 && changedNote!.markdown.english.count < note.markdown.english.count && changedNote!.markdown.english.hasPrefix("# Weekend\n\nWalk by the river.") && changedNote!.title == note.title && store.record(record.id)?.values["rating"] == .number(8.5)
            if !notePassed { print("NOTE_FIXTURE_FAILURE=\(String(describing: changedNote))") }
            assistant.selectCollection(record.collectionID, store: store)
            before = store.state
            try await ask(assistant, store, "No necesito la puntuación; quita ese campo de la colección", "schema-removal-confirmation")
            guard case .confirmCollectionChange = assistant.result, store.state == before else { throw BlueError.invalidValue }
            assistant.selectSurface("calendar", day: "2026-11-09")
            try await ask(assistant, store, "Añade al calendario una cena el 9 de noviembre de 2026 a las 21:00, sin alarma", "calendar-create")
            guard let event = store.state.events?.first, event.title.lowercased().contains("cena"), store.state.alarms.isEmpty else { throw BlueError.invalidValue }
            try await ask(assistant, store, "Pasa esa cena a las diez de la noche del mismo día", "calendar-move")
            guard store.state.events?.first?.revision == 1, Calendar.current.component(.hour, from: store.state.events!.first!.date) == 22 else { throw BlueError.invalidValue }
            before = store.state
            try await ask(assistant, store, "Borra la cena del calendario", "calendar-delete-review")
            guard case .confirmDeletion(let deletion) = assistant.result, deletion.id == event.id, store.state == before else { throw BlueError.invalidValue }
            assistant.selectRecord(record.id)
            try await ask(assistant, store, "Je lui donnerais neuf sur dix", "french-rating")
            guard store.record(record.id)?.values["rating"] == .number(9) else { throw BlueError.invalidValue }
            guard notePassed else { throw BlueError.invalidValue }
            print("PRODUCTION_SEMANTIC_FLOWS_VERIFIED=10")
        } catch { print("PRODUCTION_MAC_MODEL_FAILED=\(error)"); exit(1) }
    }
}
