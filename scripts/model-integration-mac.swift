import Foundation
import FoundationModels

// AlarmKit is iOS-only. This adapter rejects alarm actions in the Mac verification harness.
// The record store, model orchestration and all seven tool schemas are production sources.
@MainActor final class AlarmService {
    func alarms(on date: Date) -> [SavedAlarm] { [] }
    func save(_ alarm: SavedAlarm) async throws { throw BlueError.unsupported }
}

@main struct MacModelIntegration {
    @MainActor static func waitForResult(_ assistant: AssistantService) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(60))
        while assistant.busy {
            guard ContinuousClock.now < deadline else {
                assistant.cancel()
                throw BlueError.cancelled
            }
            try await Task.sleep(for: .milliseconds(100))
        }
    }
    @MainActor static func main() async {
        do {
            print("PRODUCTION_MAC_MODEL_AVAILABILITY=\(SystemLanguageModel.default.availability)")
            guard SystemLanguageModel.default.isAvailable else { throw BlueError.modelUnavailable }
            let directory = FileManager.default.temporaryDirectory.appending(path: "blue-production-model-\(UUID())")
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let url = directory.appending(path: "library.store")
            let store = try LibraryStore(url: url)
            let assistant = AssistantService()
            let alarms = AlarmService()
            let start = ContinuousClock.now
            assistant.input = "What rating did I give Interstellar?"
            assistant.submit(store: store, alarms: alarms, language: .english)
            try await waitForResult(assistant)
            guard case .records(let ids, let edited) = assistant.result,
                ids.count == 1, !edited, store.record(ids[0])?.values["rating"] == .number(9)
            else {
                print("PRODUCTION_READ_RESULT=\(String(describing: assistant.result))")
                throw BlueError.invalidValue
            }
            print("PRODUCTION_MAC_FIRST_USEFUL_RESPONSE=\(start.duration(to: .now))")
            assistant.input = "Change that same Interstellar record's rating to 10."
            assistant.submit(store: store, alarms: alarms, language: .english)
            try await waitForResult(assistant)
            guard case .records(_, let edited) = assistant.result, edited else {
                print("PRODUCTION_EDIT_RESULT=\(String(describing: assistant.result))")
                throw BlueError.invalidValue
            }
            let reopened = try LibraryStore(url: url)
            guard reopened.record(ids[0])?.values["rating"] == .number(10) else { throw BlueError.saveFailed }
            print("PRODUCTION_MAC_READ_EDIT_REOPEN_VERIFIED total=\(start.duration(to: .now)) rating=10")
            assistant.input = "¿Qué puntuación le puse a Interstellar?"
            assistant.submit(store: store, alarms: alarms, language: .spanish)
            try await waitForResult(assistant)
            guard case .records(let spanishIDs, _) = assistant.result, spanishIDs == ids else {
                print("PRODUCTION_SPANISH_READ_RESULT=\(String(describing: assistant.result))")
                throw BlueError.invalidValue
            }
            assistant.input = "Ponle un 8,5 a Interstellar."
            assistant.submit(store: store, alarms: alarms, language: .spanish)
            try await waitForResult(assistant)
            let spanishReopened = try LibraryStore(url: url)
            guard spanishReopened.record(ids[0])?.values["rating"] == .number(8.5) else {
                print("PRODUCTION_SPANISH_RESULT=\(String(describing: assistant.result))")
                throw BlueError.invalidValue
            }
            print("PRODUCTION_MAC_SPANISH_READ_EDIT_REOPEN_VERIFIED rating=8.5")
            assistant.input = "Make a list of hiking routes with distance, difficulty, and notes."
            assistant.submit(store: store, alarms: alarms, language: .english)
            try await waitForResult(assistant)
            guard case .collection(let collectionID) = assistant.result,
                let collection = store.collection(collectionID),
                collection.fields.contains(where: { $0.kind == .number }),
                collection.fields.contains(where: { $0.kind == .status })
            else {
                print("PRODUCTION_COLLECTION_RESULT=\(String(describing: assistant.result))")
                throw BlueError.invalidValue
            }
            try Validation.collection(collection)
            print("PRODUCTION_MAC_CUSTOM_COLLECTION_VERIFIED fields=\(collection.fields.count)")
        } catch {
            print("PRODUCTION_MAC_MODEL_FAILED=\(error)")
            exit(1)
        }
    }
}
