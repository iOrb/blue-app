import Foundation
import FoundationModels

enum ProbeError: Error { case invalidValue }

actor FixtureStore {
    let file: URL
    private(set) var reads = 0
    private(set) var edits = 0
    init(file: URL) throws {
        self.file = file
        try Data("9".utf8).write(to: file, options: .atomic)
    }
    func read() throws -> String {
        reads += 1
        return try String(contentsOf: file, encoding: .utf8)
    }
    func update(_ rating: Int) throws -> String {
        guard (0...10).contains(rating) else { throw ProbeError.invalidValue }
        try Data(String(rating).utf8).write(to: file, options: .atomic)
        edits += 1
        return try read()
    }
}
struct ReadFixture: Tool {
    let name = "readInterstellar"
    let description = "Read the Interstellar movie rating from a saved local test fixture."
    let store: FixtureStore
    @Generable struct Arguments { var title: String }
    func call(arguments: Arguments) async throws -> String {
        guard arguments.title.lowercased() == "interstellar" else { return "No exact match" }
        return "Interstellar rating: \(try await store.read())"
    }
}
struct EditFixture: Tool {
    let name = "editInterstellar"
    let description = "Save a new integer rating for Interstellar."
    let store: FixtureStore
    @Generable struct Arguments { @Guide(.range(0...10)) var rating: Int }
    func call(arguments: Arguments) async throws -> String {
        "Saved rating: \(try await store.update(arguments.rating))"
    }
}
@main struct ModelSmoke {
    static func main() async {
        let file = FileManager.default.temporaryDirectory.appending(path: "blue-model-smoke-\(UUID().uuidString).txt")
        defer { try? FileManager.default.removeItem(at: file) }
        do {
            print("MAC_MODEL_AVAILABILITY=\(SystemLanguageModel.default.availability)")
            guard SystemLanguageModel.default.isAvailable else { return }
            let store = try FixtureStore(file: file)
            let session = LanguageModelSession(
                model: SystemLanguageModel.default, tools: [ReadFixture(store: store), EditFixture(store: store)],
                instructions:
                    "Use the tools to read and change the local fixture. Never invent a rating. Only edit when the user asks."
            )
            let start = ContinuousClock.now
            let read = try await session.respond(to: "What rating did I give Interstellar? Read it using the tool.")
            guard await store.reads > 0, await store.edits == 0 else { throw ProbeError.invalidValue }
            print("MAC_FIRST_USEFUL_RESPONSE_DURATION=\(start.duration(to: .now))")
            print("MAC_READ_RESPONSE=\(read.content)")
            let edit = try await session.respond(to: "Change Interstellar's rating to 10 using the tool.")
            print("MAC_EDIT_RESPONSE=\(edit.content)")
            let saved = try await store.read()
            guard saved == "10", await store.edits == 1 else { throw CocoaError(.fileWriteUnknown) }
            print("MAC_REAL_READ_EDIT_VERIFIED duration=\(start.duration(to: .now)) persisted=\(saved)")
        } catch {
            print("MAC_REAL_MODEL_FAILED=\(error)")
            exit(1)
        }
    }
}
