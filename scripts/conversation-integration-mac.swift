import Foundation
import FoundationModels

@MainActor final class AlarmService {
    func alarms(on date: Date) -> [SavedAlarm] { [] }
    func save(_ alarm: SavedAlarm) async throws { throw BlueError.unsupported }
}
@main struct ConversationIntegration {
    @MainActor static func ask(_ assistant: AssistantService, _ store: LibraryStore, _ prompt: String, _ label: String) async throws {
        let start = ContinuousClock.now
        assistant.input = prompt
        assistant.submit(store: store, alarms: AlarmService(), language: .spanish)
        while assistant.busy {
            guard start.duration(to: .now) < .seconds(110) else { assistant.cancel(); throw BlueError.cancelled }
            try await Task.sleep(for: .milliseconds(100))
        }
        print("CONVERSATION_CASE=\(label) elapsed=\(start.duration(to: .now)) result=\(String(describing: assistant.result))")
    }
    @MainActor static func main() async {
        do {
            guard SystemLanguageModel.default.isAvailable else { throw BlueError.modelUnavailable }
            let store = try LibraryStore(inMemory: true)
            let assistant = AssistantService()
            let movie = store.state.records.first { $0.title == "Interstellar" }!
            assistant.selectRecord(movie.id)
            let initial = store.state
            try await ask(assistant, store, "hola", "greeting-open-movie")
            guard case .answer(let greeting) = assistant.result, !greeting.isEmpty, !greeting.localizedCaseInsensitiveContains("Interstellar"), store.state == initial else { throw BlueError.invalidValue }
            try await ask(assistant, store, "¿Qué puedes hacer?", "capabilities")
            guard case .answer = assistant.result, store.state == initial else { throw BlueError.invalidValue }
            try await ask(assistant, store, "La puntuación de Interstellar, por favor", "explicit-read-after-chat")
            guard case .selection(let selection) = assistant.result, selection.records == [movie.id], store.state == initial else { throw BlueError.invalidValue }
            try await ask(assistant, store, "gracias", "thanks-after-read")
            guard case .answer(let thanks) = assistant.result, !thanks.isEmpty, store.state == initial else { throw BlueError.invalidValue }
            let note = Note(title: .user("Escapada"), markdown: .user("# Fin de semana\n\nComeremos junto al río.\n\nDespués de comer daremos un paseo muy largo y tranquilo por los bonitos jardines verdes que hay junto al hotel."))
            try store.saveNote(note, expectedRevision: nil)
            assistant.selectNote(note.id)
            let before = store.state
            try await ask(assistant, store, "No cambies mi nota todavía. Propón una versión más corta del segundo párrafo.", "proposal-without-saving")
            guard case .answer(let proposal) = assistant.result, proposal.count < 1000, !proposal.contains("Interstellar"), (proposal.localizedCaseInsensitiveContains("paseo") || proposal.localizedCaseInsensitiveContains("jard")), store.state == before else { throw BlueError.invalidValue }
            try await ask(assistant, store, "Sí, aplica esa propuesta al segundo párrafo", "accept-proposal")
            guard let edited = store.state.notes.first(where: { $0.id == note.id }), edited.revision == 1, edited.markdown.english.count < note.markdown.english.count, edited.markdown.english.hasPrefix("# Fin de semana\n\nComeremos junto al río."), edited.title == note.title, proposal.contains(edited.markdown.english.components(separatedBy: "\n\n").last ?? "!missing!"), store.record(movie.id) == movie else { throw BlueError.invalidValue }
            try await ask(assistant, store, "Ahora cámbiale el título a Viaje tranquilo", "followup-rename")
            guard let renamed = store.state.notes.first(where: { $0.id == note.id }), renamed.title.english == "Viaje tranquilo", renamed.markdown == edited.markdown else { throw BlueError.invalidValue }
            try await ask(assistant, store, "Hola, crea una nota llamada Lista de equipaje con el texto Pasaporte y cargador.", "greeting-with-command")
            guard store.state.notes.contains(where: { $0.title.english == "Lista de equipaje" && $0.markdown.english.contains("Pasaporte") }) else { throw BlueError.invalidValue }
            let after = store.state
            try await ask(assistant, store, "Thanks!", "english-thanks")
            guard case .answer = assistant.result, store.state == after, assistant.history.count <= 4 else { throw BlueError.invalidValue }
            print("PRODUCTION_CONVERSATION_VERIFIED=9")
        } catch { print("PRODUCTION_CONVERSATION_FAILED=\(error)"); exit(1) }
    }
}
