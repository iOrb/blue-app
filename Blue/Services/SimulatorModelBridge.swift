import Foundation

#if os(macOS) || (DEBUG && targetEnvironment(simulator))
    struct ModelBridgeRequest: Codable, Sendable {
        var prompt: String
        var language: AppLanguage
        var previousRecord: UUID?
        var collectionID: UUID?
        var noteID: UUID?
        var library: LibraryState
        var surface: String? = nil
        var selectedDay: String? = nil
        var eventID: UUID? = nil
        var history: [AssistantExchange]? = nil
    }
    struct ModelBridgeResponse: Codable, Sendable {
        var library: LibraryState
        var result: AssistantResult
        var history: [AssistantExchange]? = nil
    }
#endif

#if DEBUG && targetEnvironment(simulator)
    enum SimulatorModelBridge {
        static var token: String? {
            if let token = ProcessInfo.processInfo.environment["BLUE_MODEL_BRIDGE_TOKEN"], !token.isEmpty {
                return token
            }
            let file = URL.applicationSupportDirectory.appending(path: "BlueDevelopment/model-bridge-token")
            return (try? String(contentsOf: file, encoding: .utf8))?.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        static var isConfigured: Bool { token?.isEmpty == false }
        @MainActor static func respond(
            prompt: String, language: AppLanguage, previousRecord: UUID?, collectionID: UUID?, noteID: UUID?,
            store: LibraryStore, surface: String = "all", selectedDay: String? = nil, eventID: UUID? = nil,
            history: [AssistantExchange] = []
        ) async throws -> (result: AssistantResult, changed: Bool, history: [AssistantExchange]?) {
            guard let token else { throw BlueError.modelUnavailable }
            let snapshot = store.state
            let payload = ModelBridgeRequest(
                prompt: prompt, language: language, previousRecord: previousRecord, collectionID: collectionID,
                noteID: noteID,
                library: snapshot, surface: surface, selectedDay: selectedDay, eventID: eventID,
                history: AssistantExchange.bounded(history))
            var request = URLRequest(url: URL(string: "http://127.0.0.1:7977/respond")!, timeoutInterval: 100)
            request.httpMethod = "POST"
            request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(payload)
            guard request.httpBody!.count <= 8_000_000 else { throw BlueError.invalidValue }
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200, data.count <= 8_000_000 else {
                throw BlueError.modelUnavailable
            }
            let reply = try JSONDecoder().decode(ModelBridgeResponse.self, from: data)
            try Task.checkCancellation()
            let changed = snapshot != reply.library
            if changed {
                guard store.state == snapshot,
                    reply.library.alarms == snapshot.alarms
                else { throw BlueError.staleRevision }
                for collection in reply.library.collections { try Validation.collection(collection) }
                for record in reply.library.records {
                    try Validation.title(record.title)
                    guard let collection = reply.library.collections.first(where: { $0.id == record.collectionID })
                    else { throw BlueError.invalidValue }
                    for (id, value) in record.values {
                        guard let field = collection.fields.first(where: { $0.id == id }) else {
                            throw BlueError.invalidValue
                        }
                        try Validation.field(field, value: value)
                    }
                }
                for event in reply.library.events ?? [] { try Validation.event(event) }
                for note in reply.library.notes {
                    if note.title.key == nil {
                        try Validation.title(note.title.english)
                        try Validation.title(note.title.spanish)
                    }
                    guard note.markdown.english.count <= 20000, note.markdown.spanish.count <= 20000 else {
                        throw BlueError.invalidValue
                    }
                }
                try store.update { $0 = reply.library }
            }
            return (reply.result, changed, reply.history)
        }
    }
#endif
