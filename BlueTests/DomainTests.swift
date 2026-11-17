import Foundation
import SwiftData
import Testing
import UIKit
import UserNotifications

@testable import Blue

struct DomainTests {
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
    @Test func localProposalDoesNotOverwriteInterveningEdits() async throws {
        let store = try LibraryStore(inMemory: true, seed: false)
        let id = try store.createCollection(title: "Films", fields: [])
        let original = try #require(store.collection(id))
        let proposal = LocalAssistantProposal.rename(collection: original, title: "Suggested")
        #expect(store.collection(id)?.title == .user("Films"))
        var changed = original
        changed.title = .user("My edit")
        try store.saveCollection(changed)
        await #expect(throws: BlueError.staleRevision) {
            _ = try await proposal.apply(store: store, language: .english)
        }
        #expect(store.collection(id)?.title == .user("My edit"))
    }
    @Test func localBatchRollsBackIfAnItemUsesAnInvalidField() async throws {
        let store = try LibraryStore(inMemory: true, seed: false)
        let id = try store.createCollection(title: "Films", fields: [])
        let collection = try #require(store.collection(id))
        let note = LocalAssistantProposal.note(title: "Recados", body: "Comprar entradas")
        let invalid = LocalAssistantProposal.item(
            collection: collection, title: "Dune", values: ["missing": .flag(true)])
        await #expect(throws: BlueError.invalidValue) {
            _ = try await LocalAssistantProposal.batch([note, invalid]).apply(store: store, language: .spanish)
        }
        #expect(store.state.notes.isEmpty)
        #expect(store.state.records.isEmpty)
        let item = LocalAssistantProposal.item(collection: collection, title: "Dune")
        _ = try await LocalAssistantProposal.batch([note, item]).apply(store: store, language: .spanish)
        #expect(store.state.notes.map(\.title) == [.user("Recados")])
        #expect(store.state.records.map(\.title) == ["Dune"])
    }

    @Test func connectedAssistantRoutesCredentialsAndReadsCitations() throws {
        let openAI = ConnectedAssistant(connection: .init(provider: .openai, model: "gpt-5-mini", key: "test"))
        let gemini = ConnectedAssistant(connection: .init(provider: .gemini, model: "gemini-3.8-flash", key: "test"))
        let grok = ConnectedAssistant(connection: .init(provider: .grok, model: "grok-4.7", key: "test"))
        let openRequest = try openAI.request(instructions: "Test", prompt: "Hello")
        let geminiRequest = try gemini.request(instructions: "Test", prompt: "Hello")
        let grokRequest = try grok.request(instructions: "Test", prompt: "Hello")
        #expect(openRequest.url?.host == "api.openai.com")
        #expect(openRequest.value(forHTTPHeaderField: "Authorization") == "Bearer test")
        #expect(geminiRequest.url?.host == "generativelanguage.googleapis.com")
        #expect(geminiRequest.value(forHTTPHeaderField: "x-goog-api-key") == "test")
        #expect(grokRequest.url?.host == "api.x.ai")
        let stream = Data(#"{"type":"response.output_text.delta","delta":"Hello"}"#.utf8)
        #expect(try ConnectedAssistant.chunk(stream, provider: .openai).text == "Hello")
        let grounding = Data(
            #"{"candidates":[{"finishReason":"STOP","content":{"parts":[{"text":"Hola"}]},"groundingMetadata":{"groundingChunks":[{"web":{"uri":"https://example.com","title":"Source"}},{"web":{"uri":"http://example.com","title":"Unsafe"}}]}}]}"#
                .utf8)
        let result = try ConnectedAssistant.chunk(grounding, provider: .gemini)
        #expect(result.completed && result.text == "Hola")
        #expect(result.sources.count == 1)
        #expect(!AssistantConnection.isValidModel("../private"))
    }

    @Test func openAILibraryActionsUseTheCompletedStructuredResponse() throws {
        let client = ConnectedAssistant(connection: .init(provider: .openai, model: "gpt-5.6-luna", key: "test"))
        let request = try client.request(
            instructions: "Return JSON", prompt: "hola", webSearch: false, libraryAction: true)
        let body = try #require(request.httpBody)
        let payload = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
        let text = try #require(payload["text"] as? [String: Any])
        let format = try #require(text["format"] as? [String: Any])
        #expect(payload["stream"] as? Bool == false)
        #expect(format["type"] as? String == "json_schema")
        #expect(format["strict"] as? Bool == true)
        let action = #"{"action":"answer","text":"¡Hola!"}"#
        let completed = try JSONSerialization.data(withJSONObject: [
            "status": "completed",
            "output": [["type": "message", "content": [["type": "output_text", "text": action]]]],
        ])
        #expect(try ConnectedAssistant.completedAction(completed).text == action)
    }

    @Test func liveProtocolUsesTheSelectedProviderAndDecodesAudioAndTools() throws {
        let connection = AssistantConnection(provider: .openai, model: "gpt-5-mini", key: "test")
        let live = VoiceProtocol(connection: connection, model: "gpt-realtime")
        let start = live.start(language: .spanish)
        let settings = try #require(start["session"] as? [String: Any])
        #expect(AssistantProvider.openai.liveModels.first == "gpt-live-1")
        #expect(start["type"] as? String == "session.update")
        #expect(settings["type"] as? String == "realtime")
        #expect(settings["delegation"] == nil)
        #expect(settings["output_modalities"] as? [String] == ["audio"])
        let audio = try #require(settings["audio"] as? [String: Any])
        let input = try #require(audio["input"] as? [String: Any])
        #expect(input["transcription"] == nil)
        #expect(live.microphone(Data([0, 1]))["type"] as? String == "input_audio_buffer.append")
        #expect(try live.events(Data(#"{"type":"session.updated"}"#.utf8)) == [.ready])
        #expect(
            try live.events(Data(#"{"type":"response.output_audio.delta","delta":"AAE="}"#.utf8)) == [
                .audio(Data([0, 1]))
            ])
        let arguments = #"{"action":"create","kind":"note","title":"Prueba"}"#
        let item = ["type": "function_call", "name": "blue_library", "call_id": "call_1", "arguments": arguments]
        let call = VoiceProtocol.ToolCall(id: "call_1", arguments: Data(arguments.utf8))
        let directCall = try JSONSerialization.data(withJSONObject: [
            "type": "response.done", "response": ["status": "completed", "output": [item]],
        ])
        #expect(try live.events(directCall) == [.tool(call), .toolsReady, .turnFinished])
        let interruptedCall = try JSONSerialization.data(withJSONObject: [
            "type": "response.done", "response": ["status": "cancelled", "output": [item]],
        ])
        #expect(try live.events(interruptedCall).isEmpty)
        #expect(try live.toolOutput(call, result: "Guardado")["type"] as? String == "conversation.item.create")
        #expect(live.continueResponse?["type"] as? String == "response.create")
        let exactLive = VoiceProtocol(connection: connection, model: "gpt-live-1")
        let exactSession = try #require(exactLive.start(language: .spanish)["session"] as? [String: Any])
        #expect(exactSession["model"] as? String == "gpt-live-1")
        let exactAudio = try #require(exactSession["audio"] as? [String: Any])
        let exactOutput = try #require(exactAudio["output"] as? [String: Any])
        #expect(exactOutput["voice"] as? String == "marin")
        let exactDelegation = try #require(exactSession["delegation"] as? [String: Any])
        let backend = try #require(exactDelegation["responses"] as? [String: Any])
        #expect(backend["model"] as? String == connection.model)
        let delegated = try JSONSerialization.data(withJSONObject: [
            "type": "response.event", "event": ["type": "response.output_item.done", "item": item],
        ])
        #expect(try exactLive.events(delegated) == [.tool(call), .toolsReady])
        #expect(try exactLive.toolOutput(call, result: "Guardado")["type"] as? String == "response.item.create")
        #expect(
            try live.events(Data(#"{"error":{"code":"invalid_api_key"}}"#.utf8)) == [.failure(.assistantCredentials)])
        let gemini = VoiceProtocol(
            connection: .init(provider: .gemini, model: "gemini-3.8-flash", key: "test"), model: "gemini-3.8-live")
        #expect(try gemini.events(Data(#"{"setupComplete":{}}"#.utf8)) == [.ready])
        #expect(gemini.inputRate == 16_000)
        let grok = VoiceProtocol(
            connection: .init(provider: .grok, model: "grok-4.7", key: "test"), model: "grok-voice-latest")
        #expect(try grok.events(Data(#"{"type":"session.updated"}"#.utf8)) == [.ready])
        let dictation = try DictationService.transcriptionRequest(
            Data([0, 1]), connection: connection, model: "gpt-transcribe", language: .spanish)
        #expect(dictation.url?.path == "/v1/audio/transcriptions")
        #expect(String(decoding: dictation.httpBody ?? Data(), as: UTF8.self).contains("gpt-transcribe"))
        #expect(throws: BlueError.invalidValue) {
            _ = try DictationService.transcriptionRequest(
                Data([0, 1]), connection: connection, model: "gpt-live-1", language: .english)
        }
    }

    @Test func voicePlaybackIgnoresIdleSilenceAndPreservesBriefPauses() {
        var gate = VoicePlaybackGate()
        let silence = Data(repeating: 0, count: 2_400)
        let voice = Data(repeating: 8, count: 2_400)
        #expect(gate.classify(silence, followingSpeech: false) == .skip)
        #expect(gate.classify(voice, followingSpeech: false) == .speech)
        for _ in 0..<3 { #expect(gate.classify(silence, followingSpeech: true) == .gap) }
        #expect(gate.classify(silence, followingSpeech: true) == .skip)
        #expect(gate.classify(voice, followingSpeech: false) == .speech)
        #expect(gate.classify(silence, followingSpeech: true) == .gap)
    }

    @Test func connectedModelCatalogOffersSupportedTextModelsAndAliases() throws {
        let grok = Data(
            #"{"data":[{"id":"grok-4-0709","aliases":["grok-4","grok-4"]},{"id":"grok-imagine-video"}]}"#.utf8)
        #expect(try ConnectedAssistant.models(from: grok, provider: .grok) == ["grok-4", "grok-4-0709"])

        let gemini = Data(
            #"{"models":[{"name":"models/gemini-flash","supportedGenerationMethods":["generateContent"]},{"name":"models/gemini-embed","supportedGenerationMethods":["embedContent"]}]}"#
                .utf8)
        #expect(try ConnectedAssistant.models(from: gemini, provider: .gemini) == ["gemini-flash"])
    }

    @Test func connectionSetupDistinguishesCredentialsModelsAndTemporaryFailures() async {
        let service = AssistantService()
        await service.checkConnection(nil)
        #expect(service.connectionStatus == .needsSetup)

        let connection = AssistantConnection(provider: .gemini, model: "gemini-flash", key: "test")
        await service.checkConnection(connection) { _ in throw URLError(.notConnectedToInternet) }
        #expect(service.connectionStatus == .unavailable)
        await service.checkConnection(connection) { _ in throw BlueError.assistantCredentials }
        #expect(service.connectionStatus == .needsSetup)

        let replacement = AssistantConnection(provider: .gemini, model: "gemini-flash", key: "replacement")
        await service.checkConnection(replacement) { _ in ["gemini-pro"] }
        #expect(service.connectionStatus == .needsSetup)
        #expect(service.recordCatalog(["gemini-flash"], for: replacement))
        #expect(service.connectionStatus == .ready)
        service.recordConnection(.needsSetup, for: replacement, requestRejected: true)
        #expect(!service.recordCatalog(["gemini-flash"], for: replacement))
        #expect(service.connectionStatus == .needsSetup)

        let invalidKey = Data(#"{"error":{"details":[{"reason":"API_KEY_INVALID"}]}}"#.utf8)
        #expect(ConnectedAssistant.invalidGeminiKey(in: invalidKey))
        #expect(!ConnectedAssistant.invalidGeminiKey(in: Data("{}".utf8)))
    }

    @Test func importingCollectionsPreservesLocalEditsAndRejectsInvalidRecords() throws {
        let source = try LibraryStore(inMemory: true, seed: false)
        let target = try LibraryStore(inMemory: true, seed: false)
        let id = try source.createCollection(title: "Films", fields: [])
        var movie = Record(collectionID: id, title: "Interstellar")
        try source.saveRecord(movie, expectedRevision: nil)
        try source.saveNote(
            Note(title: .user("My note"), markdown: .user("First line\nSecond line")), expectedRevision: nil)
        let backup = try source.export()
        try target.importBackup(backup)
        #expect(target.state.notes.count == 1)
        #expect(target.record(movie.id)?.title == "Interstellar")
        movie.title = "My edit"
        try target.saveRecord(movie, expectedRevision: target.record(movie.id)?.revision)
        try target.importBackup(backup)
        #expect(target.state.collections.count == 1)
        #expect(target.state.notes.count == 1)
        #expect(target.record(movie.id)?.title == "My edit")

        let newID = try source.createCollection(title: "Invalid record collection", fields: [])
        try source.update { $0.records.append(Record(collectionID: newID, title: "")) }
        let invalidBackup = try source.export()
        #expect(throws: BlueError.emptyTitle) { try target.importBackup(invalidBackup) }
        #expect(target.collection(newID) == nil)
        #expect(target.record(movie.id)?.title == "My edit")
    }
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
        #expect(exported.formatVersion == 3)
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
        let serviceFailure = NSError(domain: "FoundationModels.LanguageModelSession.GenerationError", code: -1)
        #expect(AssistantService.errorKey(serviceFailure) == "assistant.unavailable")
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
    @Test func legacyArchivedContentReturnsToTheLibrary() throws {
        let store = try LibraryStore(inMemory: true)
        var backup = try #require(JSONSerialization.jsonObject(with: store.export()) as? [String: Any])
        for kind in ["collections", "records", "notes"] {
            var rows = try #require(backup[kind] as? [[String: Any]])
            rows[0]["archived"] = true
            backup[kind] = rows
        }
        let imported = try LibraryStore(inMemory: true, seed: false)
        try imported.importBackup(JSONSerialization.data(withJSONObject: backup))
        #expect(imported.state.collections.map(\.id) == store.state.collections.map(\.id))
        #expect(imported.state.records.map(\.id) == store.state.records.map(\.id))
        #expect(imported.state.notes.map(\.id) == store.state.notes.map(\.id))
    }

    @Test func connectedAgentReadsActualRatingAndCommitsClearEdit() async throws {
        let store = try LibraryStore(inMemory: true)
        let movie = try #require(store.state.records.first { $0.title == "Interstellar" })
        var agent = ConnectedLibraryAgent(
            store: store, alarms: AlarmService(store: store), language: .spanish, selected: [:])
        var requests = 0
        let rating = try await agent.run("¿Qué nota tiene Interstellar?", history: []) { prompt in
            requests += 1
            if requests == 1 {
                #expect(!prompt.contains("Interstellar |"))
                return #"{"action":"lookup","kind":"record","query":"Interstellar"}"#
            }
            #expect(prompt.contains(movie.id.uuidString))
            return #"{"action":"show","kind":"record","id":"\#(movie.id.uuidString)","field":"rating"}"#
        } search: { _ in
            Issue.record("Private values should not trigger web lookup")
            return []
        }
        #expect(rating == .answer("9"))
        let saved = try await agent.run("Ponle un 8,5 a Interstellar.", history: []) { _ in
            return
                #"{"action":"update","kind":"record","id":"\#(movie.id.uuidString)","properties":[{"field":"rating","value":"8,5"}]}"#
        } search: { _ in
            []
        }
        #expect(saved == .message("local.changesSaved"))
        #expect(store.record(movie.id)?.values["rating"] == .number(8.5))
    }

    @Test func connectedAssistantSavesWrappedTextActionsAndDirectVoiceActions() async throws {
        let store = try LibraryStore(inMemory: true, seed: false)
        let films = try store.createCollection(title: "Películas", fields: [])
        var agent = ConnectedLibraryAgent(
            store: store, alarms: AlarmService(store: store), language: .spanish, selected: ["collection": films])
        let note = try await agent.run("Añade una nota llamada Ideas", history: []) { prompt in
            #expect(prompt.contains("Películas"))
            return #"{"action":"create","arguments":{"kind":"note","title":"Ideas"}}"#
        } search: { _ in
            []
        }
        #expect(note == .message("local.changesSaved"))
        #expect(store.state.notes.first?.title.english == "Ideas")
        let record = try await agent.executeVoice(
            Data(
                #"{"action":"create","kind":"record","title":"La llegada","collectionID":"\#(films.uuidString)"}"#
                    .utf8))
        #expect(record.result == .message("local.changesSaved"))
        #expect(store.records(in: films).first?.title == "La llegada")
    }

    @Test func connectedAgentRecoversFormatAndUsesSavedCandidatesAfterAMiss() async throws {
        let store = try LibraryStore(inMemory: true, seed: false)
        let films = try store.createCollection(title: "Películas", fields: [])
        let original = store.state
        var agent = ConnectedLibraryAgent(
            store: store, alarms: AlarmService(store: store), language: .spanish, selected: [:])
        let input = "meteme Solaris en las pelis xfa"
        var requests = 0
        let result = try await agent.run(input, history: []) { prompt in
            #expect(prompt.contains(input))
            if requests < 3 { #expect(store.state == original) }
            requests += 1
            if requests == 1 { return #"{"action":"lookup","kind":"movie","query":"pelis"}"# }
            if requests == 2 {
                #expect(prompt.contains("Invalid action format"))
                return #"{"action":"lookup","kind":"collection","query":"pelis"}"#
            }
            #expect(prompt.contains("candidates"))
            #expect(prompt.contains(films.uuidString))
            return
                #"{"action":"create","kind":"record","title":"Solaris","collectionID":"\#(films.uuidString)"}"#
        } search: { _ in
            []
        }
        #expect(requests == 4)
        #expect(result == .message("local.changesSaved"))
        #expect(store.records(in: films).map(\.title) == ["Solaris"])
    }

    @Test func recordDeletionValidatesTheWholeSelectionBeforeRemovingAnything() throws {
        let store = try LibraryStore(inMemory: true, seed: false)
        let films = try store.createCollection(title: "Films", fields: [])
        let other = try store.createCollection(title: "Other", fields: [])
        let first = Record(collectionID: films, title: "First")
        var second = Record(collectionID: films, title: "Second")
        let outside = Record(collectionID: other, title: "Outside")
        for record in [first, second, outside] { try store.saveRecord(record, expectedRevision: nil) }

        second.title = "Edited second"
        try store.saveRecord(second, expectedRevision: second.revision)
        #expect(throws: BlueError.staleRevision) {
            try store.confirmRecordDeletions(in: films, revisions: [first.id: 0, second.id: 0])
        }
        #expect(throws: BlueError.staleRevision) {
            try store.confirmRecordDeletions(in: films, revisions: [first.id: 0, outside.id: 0])
        }
        #expect(store.state.records.count == 3)
        let latest = try #require(store.record(second.id))
        try store.confirmRecordDeletions(in: films, revisions: [first.id: 0, second.id: latest.revision])
        #expect(store.state.records.map(\.id) == [outside.id])
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
    var scheduleCount = 0
    func authorize() async throws { if denial { throw BlueError.permissionDenied } }
    func schedule(_ alarm: SavedAlarm) async throws {
        if failure || ids.contains(alarm.id) { throw BlueError.alarmFailed }
        scheduleCount += 1
        ids.insert(alarm.id)
    }
    func cancel(_ id: UUID) throws {
        if failure { throw BlueError.alarmFailed }
        ids.remove(id)
    }
    func scheduledIDs() throws -> Set<UUID> { ids }
}

@MainActor
final class FakeEventNotifications: EventNotificationScheduling {
    var scheduled: [UUID: CalendarEvent] = [:]
    var denial = false
    func schedule(_ event: CalendarEvent) async throws {
        if denial { throw BlueError.notificationPermissionDenied }
        scheduled[event.id] = event
    }
    func cancelNotification(for id: UUID) { scheduled.removeValue(forKey: id) }
}

@MainActor
struct AlarmTests {
    @Test func connectedVoiceEventUsesTheNextOccurrenceAndChecksScheduling() async throws {
        let store = try LibraryStore(inMemory: true, seed: false)
        let scheduler = FakeScheduler()
        let notifications = FakeEventNotifications()
        let service = AlarmService(store: store, scheduler: scheduler, notifications: notifications)
        var agent = ConnectedLibraryAgent(store: store, alarms: service, language: .spanish, selected: [:])
        let request = Data(#"{"action":"create","kind":"event","hour":3,"minute":55}"#.utf8)
        scheduler.denial = true
        await #expect(throws: BlueError.permissionDenied) { try await agent.executeVoice(request) }
        #expect(store.state.alarms.isEmpty)
        scheduler.denial = false
        let result = try await agent.executeVoice(request)
        let saved = try #require(store.state.alarms.first)
        #expect(result.result == .events([saved.id]))
        #expect(store.state.events?.first?.id == saved.id)
        #expect(store.state.events?.first?.title == "Evento")
        #expect(store.state.events?.first?.repeatDays.isEmpty == true)
        #expect(notifications.scheduled[saved.id] != nil)
        #expect(scheduler.ids == [saved.id])
        #expect(saved.enabled)
        #expect(saved.date > .now)
        let components = Calendar.current.dateComponents([.hour, .minute], from: saved.date)
        #expect(components.hour == 3)
        #expect(components.minute == 55)
        await #expect(throws: BlueError.invalidAlarmTime) {
            try await agent.executeVoice(Data(#"{"action":"create","kind":"event","hour":3,"minute":75}"#.utf8))
        }
        #expect(store.state.alarms.count == 1)
    }

    @Test func spokenEventFeedbackOnlyClaimsConfirmedAlarms() async throws {
        let store = try LibraryStore(inMemory: true, seed: false)
        let scheduler = FakeScheduler()
        let notifications = FakeEventNotifications()
        let service = AlarmService(store: store, scheduler: scheduler, notifications: notifications)
        let assistant = AssistantService()
        let perform = assistant.voiceToolHandler(store: store, alarms: service, language: .spanish)
        func arguments(_ date: Date) throws -> Data {
            try JSONSerialization.data(withJSONObject: [
                "action": "create", "kind": "event", "date": date.ISO8601Format(),
            ])
        }
        let past = try await perform(.init(id: "past", arguments: arguments(Date().addingTimeInterval(-86_400))))
        #expect(past.contains(Localizer(language: .spanish)("event.noAlarm")))
        #expect(scheduler.ids.isEmpty)
        let future = try await perform(.init(id: "future", arguments: arguments(Date().addingTimeInterval(3_600))))
        #expect(future.contains(Localizer(language: .spanish)("event.alertsScheduled")))
        #expect(scheduler.ids.count == 1)
        #expect(notifications.scheduled.count == 1)
    }

    @Test func timedEventRequiresBothSchedulesAndRollsBackAnAlarmFailure() async throws {
        let store = try LibraryStore(inMemory: true)
        let alarms = FakeScheduler()
        let notifications = FakeEventNotifications()
        let service = AlarmService(store: store, scheduler: alarms, notifications: notifications)
        let event = CalendarEvent(title: "Train", date: Date().addingTimeInterval(3600))
        notifications.denial = true
        await #expect(throws: BlueError.notificationPermissionDenied) {
            try await service.saveTimedEvent(event, expectedRevision: nil)
        }
        #expect(alarms.ids.isEmpty)
        notifications.denial = false
        alarms.denial = true
        await #expect(throws: BlueError.permissionDenied) {
            try await service.saveTimedEvent(event, expectedRevision: nil)
        }
        #expect(notifications.scheduled.isEmpty)
        #expect(store.state.events?.isEmpty == true)
        alarms.denial = false
        try await service.saveTimedEvent(event, expectedRevision: nil)
        let saved = try #require(store.state.events?.first)
        #expect(saved.notification == true)
        #expect(alarms.ids == [event.id])
        #expect(notifications.scheduled[event.id]?.date == event.date)

        var edit = saved
        edit.date += 1800
        alarms.denial = true
        await #expect(throws: BlueError.permissionDenied) {
            try await service.saveTimedEvent(edit, expectedRevision: saved.revision)
        }
        #expect(notifications.scheduled[event.id]?.date == saved.date)
        #expect(store.state.events?.first?.date == saved.date)
        alarms.denial = false
        try await service.deleteEvent(saved)
        #expect(notifications.scheduled.isEmpty)
        #expect(alarms.ids.isEmpty)
    }

    @Test func pastEventsSaveAndMovingAnEventBackCancelsItsAlerts() async throws {
        let store = try LibraryStore(inMemory: true)
        let alarms = FakeScheduler()
        let notifications = FakeEventNotifications()
        let service = AlarmService(store: store, scheduler: alarms, notifications: notifications)

        let past = CalendarEvent(title: "Yesterday", date: Date().addingTimeInterval(-86_400))
        try await service.saveTimedEvent(past, expectedRevision: nil)
        #expect(store.state.events?.first?.date == past.date)
        #expect(alarms.ids.isEmpty)
        #expect(notifications.scheduled.isEmpty)

        let future = CalendarEvent(title: "Train", date: Date().addingTimeInterval(3600))
        try await service.saveTimedEvent(future, expectedRevision: nil)
        var moved = try #require(store.state.events?.first { $0.id == future.id })
        moved.date = past.date
        try await service.saveTimedEvent(moved, expectedRevision: moved.revision)
        #expect(store.state.events?.first { $0.id == future.id }?.date == past.date)
        #expect(store.state.events?.first { $0.id == future.id }?.notification == false)
        #expect(store.state.alarms.isEmpty)
        #expect(alarms.ids.isEmpty)
        #expect(notifications.scheduled.isEmpty)
    }

    @Test func eventAlarmIsCommittedAndDeletedWithItsEvent() async throws {
        let store = try LibraryStore(inMemory: true)
        let scheduler = FakeScheduler()
        let service = AlarmService(store: store, scheduler: scheduler)
        let event = CalendarEvent(title: "Train", date: Date().addingTimeInterval(3600))
        scheduler.denial = true
        await #expect(throws: BlueError.permissionDenied) {
            try await service.saveEvent(event, expectedRevision: nil, ringing: true)
        }
        #expect(store.state.events?.isEmpty == true)
        #expect(store.state.alarms.isEmpty)
        scheduler.denial = false
        try await service.saveEvent(event, expectedRevision: nil, ringing: true)
        #expect(scheduler.ids == [event.id])
        let saved = try #require(store.state.events?.first)
        #expect(store.state.alarms.first?.date == saved.date)
        try await service.deleteEvent(saved)
        #expect(scheduler.ids.isEmpty)
        #expect(store.state.alarms.isEmpty)
        #expect(store.state.events?.isEmpty == true)
    }

    @Test func editingEventReplacesAnAlarmOnlyWhenItsScheduleChanges() async throws {
        let store = try LibraryStore(inMemory: true)
        let scheduler = FakeScheduler()
        let service = AlarmService(store: store, scheduler: scheduler)
        let event = CalendarEvent(title: "Train", date: Date().addingTimeInterval(3600))
        try await service.saveEvent(event, expectedRevision: nil, ringing: true)

        var edit = try #require(store.state.events?.first)
        edit.notes = "Platform 4"
        try await service.saveEvent(edit, expectedRevision: edit.revision, ringing: true)
        #expect(scheduler.scheduleCount == 1)

        edit = try #require(store.state.events?.first)
        edit.date += 1800
        try await service.saveEvent(edit, expectedRevision: edit.revision, ringing: true)
        #expect(scheduler.scheduleCount == 2)
        #expect(scheduler.ids == [event.id])
        #expect(store.state.alarms.first?.date == edit.date)
        #expect(store.state.events?.first?.notes == "Platform 4")
    }

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
        try store.update { $0.alarms = [weekly, fixed] }
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

@MainActor
struct EventRecurrenceTests {
    @Test func legacyAlarmsMigrateToEventsOnceWithoutLosingSchedules() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "legacy.store")
        let alarm = SavedAlarm(
            title: "Wake up", date: Date().addingTimeInterval(3_600), weekdays: [2, 6], enabled: true, revision: 4)
        let existing = CalendarEvent(title: "Train", date: .now, notes: "Keep these notes")
        do {
            let schema = Schema(versionedSchema: BlueSchemaV1.self)
            let container = try ModelContainer(
                for: schema, migrationPlan: BlueMigrationPlan.self,
                configurations: ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none))
            let context = ModelContext(container)
            let encoder = JSONEncoder()
            for (key, payload) in [
                ("metadata:initialized", Data([1])), ("alarm:" + alarm.id.uuidString, try encoder.encode(alarm)),
                ("event:" + existing.id.uuidString, try encoder.encode(existing)),
            ] {
                context.insert(BlueSchemaV1.StoredItem(key: key, payload: payload))
            }
            try context.save()
        }
        do {
            let store = try LibraryStore(url: url, seed: false)
            #expect(store.state.events?.count == 2)
            #expect(store.state.events?.first(where: { $0.id == alarm.id })?.repeatDays == [2, 6])
            #expect(store.state.events?.first(where: { $0.id == existing.id })?.notes == "Keep these notes")
            #expect(store.state.alarms == [alarm])
            #expect(store.state.formatVersion == 3)
        }
        let reopened = try LibraryStore(url: url, seed: false)
        #expect(reopened.state.events?.count == 2)
        #expect(LibraryStore.eventsOnly(reopened.state) == reopened.state)
    }

    @Test func weeklyEventsFollowSelectedDaysAndKeepWallClockAcrossDST() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "Europe/Madrid"))
        let friday = try #require(ISO8601DateFormatter().date(from: "2027-03-26T07:00:00+01:00"))
        let monday = try #require(ISO8601DateFormatter().date(from: "2027-03-29T00:00:00+02:00"))
        let sunday = try #require(calendar.date(byAdding: .day, value: -1, to: monday))
        var event = CalendarEvent(title: "Morning", date: friday, weekdays: [2, 6])
        #expect(event.occurs(on: monday, calendar: calendar))
        #expect(!event.occurs(on: sunday, calendar: calendar))
        let occurrence = try #require(event.nextOccurrence(after: friday, calendar: calendar))
        #expect(calendar.component(.weekday, from: occurrence) == 2)
        #expect(calendar.component(.hour, from: occurrence) == 7)
        #expect(occurrence.timeIntervalSince(friday) == 71 * 3_600)
        event.weekdays = [2, 2]
        #expect(throws: BlueError.invalidValue) { try Validation.event(event) }
        event.weekdays = [8]
        #expect(throws: BlueError.invalidValue) { try Validation.event(event) }
        let spanish = Localizer(language: .spanish)
        let english = Localizer(language: .english)
        #expect(spanish.orderedWeekdays.first == 2)
        #expect(english.orderedWeekdays.first == 1)
        #expect(spanish.repeatSummary([]) == "Nunca")
        #expect(english.repeatSummary(Array(1...7)) == "Every day")
    }

    @Test func repeatingNotificationsUseOnlyTheChosenWeekdays() throws {
        let event = CalendarEvent(title: "Morning", date: Date().addingTimeInterval(3_600), weekdays: [2, 4, 6])
        let requests = SystemEventNotifications.requests(for: event, content: UNMutableNotificationContent())
        #expect(requests.count == 3)
        let triggers = requests.compactMap { $0.trigger as? UNCalendarNotificationTrigger }
        #expect(triggers.allSatisfy { $0.repeats })
        #expect(triggers.compactMap { $0.dateComponents.weekday } == [2, 4, 6])
        #expect(Set(requests.map(\.identifier)).count == 3)
    }

    @Test func voiceEventsRejectExtraFieldsAndPreserveOrClearExplicitRepeat() async throws {
        let store = try LibraryStore(inMemory: true, seed: false)
        let scheduler = FakeScheduler()
        let notifications = FakeEventNotifications()
        let service = AlarmService(store: store, scheduler: scheduler, notifications: notifications)
        var agent = ConnectedLibraryAgent(store: store, alarms: service, language: .spanish, selected: [:])
        for extra in [#""color":"red""#, #""properties":[{"field":"repeat","value":"every day"}]"#, #""enabled":true"#]
        {
            let arguments = Data((#"{"action":"create","kind":"event","hour":7,"minute":0,"# + extra + "}").utf8)
            await #expect(throws: BlueError.invalidValue) { try await agent.executeVoice(arguments) }
        }
        await #expect(throws: BlueError.assistantResponseInvalid) {
            try await agent.executeVoice(Data(#"{"action":"create","kind":"alarm","hour":7,"minute":0}"#.utf8))
        }
        #expect(store.state.events?.isEmpty == true)
        _ = try await agent.executeVoice(
            Data(#"{"action":"create","kind":"event","hour":7,"minute":0,"weekdays":[2,4],"body":"Coffee"}"#.utf8))
        let event = try #require(store.state.events?.first)
        #expect(event.repeatDays == [2, 4])
        #expect(store.state.alarms.first?.weekdays == [2, 4])
        #expect(notifications.scheduled[event.id]?.repeatDays == [2, 4])
        _ = try await agent.executeVoice(Data(#"{"action":"lookup","kind":"event"}"#.utf8))
        let edit = #"{"action":"update","kind":"event","id":""# + event.id.uuidString + #"","title":"Morning"}"#
        _ = try await agent.executeVoice(Data(edit.utf8))
        #expect(store.state.events?.first?.repeatDays == [2, 4])
        #expect(store.state.events?.first?.notes == "Coffee")
        let clear = #"{"action":"update","kind":"event","id":""# + event.id.uuidString + #"","weekdays":[]}"#
        scheduler.failure = true
        await #expect(throws: BlueError.alarmFailed) { try await agent.executeVoice(Data(clear.utf8)) }
        #expect(store.state.events?.first?.repeatDays == [2, 4])
        #expect(notifications.scheduled[event.id]?.repeatDays == [2, 4])
        scheduler.failure = false
        _ = try await agent.executeVoice(Data(clear.utf8))
        #expect(store.state.events?.first?.repeatDays.isEmpty == true)
        #expect(store.state.alarms.first?.weekdays.isEmpty == true)
    }
}

@MainActor
struct BackupAndArtworkTests {
    @Test func folderCopiesIncludeAllContentAndDoNotOverwriteOtherDevices() async throws {
        let directory = URL.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let suiteA = "blue.backup.test." + UUID().uuidString
        let suiteB = "blue.backup.test." + UUID().uuidString
        let defaultsA = try #require(UserDefaults(suiteName: suiteA))
        let defaultsB = try #require(UserDefaults(suiteName: suiteB))
        defer {
            defaultsA.removePersistentDomain(forName: suiteA)
            defaultsB.removePersistentDomain(forName: suiteB)
        }
        let first = FolderBackupService(defaults: defaultsA)
        let second = FolderBackupService(defaults: defaultsB)
        var state = LibraryState()
        state.notes = [Note(title: .user("Private fixture"), markdown: .user("Line 1\nLine 2"))]
        state.events = [CalendarEvent(title: "Morning", date: .now, weekdays: [2, 6])]
        try await first.connect(to: directory, state: state)
        let original = try Data(contentsOf: directory.appending(path: first.filename))
        var another = state
        another.notes = [Note(title: .user("Other device"), markdown: .user("Other content"))]
        try await second.connect(to: directory, state: another)
        #expect(first.filename != second.filename)
        #expect(try Data(contentsOf: directory.appending(path: first.filename)) == original)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let copy = try decoder.decode(LibraryState.self, from: original)
        #expect(copy.notes.first?.markdown.english == "Line 1\nLine 2")
        #expect(copy.events?.first?.repeatDays == [2, 6])
        #expect(first.savedAt != nil)
        var newest = state
        newest.notes = [Note(title: .user("Latest edit"), markdown: .user("Persisted automatically"))]
        first.schedule(another, delay: .milliseconds(80))
        first.schedule(newest, delay: .milliseconds(80))
        var updated: LibraryState?
        for _ in 0..<40 {
            try await Task.sleep(for: .milliseconds(25))
            let bytes = try Data(contentsOf: directory.appending(path: first.filename))
            updated = try decoder.decode(LibraryState.self, from: bytes)
            if updated?.notes.first?.title.english == "Latest edit" { break }
        }
        #expect(updated?.notes.first?.title.english == "Latest edit")
        let previous = directory.appending(
            path: first.filename.replacingOccurrences(of: ".json", with: "-previous.json"))
        #expect(!FileManager.default.fileExists(atPath: previous.path))
        let invalid = directory.appending(path: "not-a-folder")
        try Data([1]).write(to: invalid)
        await #expect(throws: BlueError.saveFailed) { try await first.connect(to: invalid, state: state) }
        #expect(first.folderName == directory.lastPathComponent)
        first.disconnect()
        #expect(first.folderName == nil)
        #expect(FileManager.default.fileExists(atPath: directory.appending(path: first.filename).path))
    }

    @Test func removedFolderReportsFailureInsteadOfLastSuccess() async throws {
        let directory = URL.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let suite = "blue.backup.missing." + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let backup = FolderBackupService(defaults: defaults)
        try await backup.connect(to: directory, state: LibraryState())
        #expect(backup.savedAt != nil)
        try FileManager.default.removeItem(at: directory)
        backup.schedule(LibraryState(), delay: .zero)
        for _ in 0..<80 {
            if backup.errorKey != nil { break }
            try await Task.sleep(for: .milliseconds(25))
        }
        #expect(backup.errorKey == "backup.failed")
        #expect(backup.savedAt == nil)
    }

    @Test func coverImageIsBoundedAndSurvivesExport() throws {
        let data = UIGraphicsImageRenderer(size: CGSize(width: 1200, height: 900)).pngData { context in
            UIColor.systemBlue.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 1200, height: 900))
        }
        let artwork = try CollectionArtworkService.prepare(data)
        #expect(artwork.jpeg.count <= 1_000_000)
        let image = try #require(UIImage(data: artwork.jpeg))
        #expect(max(image.size.width, image.size.height) <= 768)
        let store = try LibraryStore(inMemory: true, seed: false)
        let id = try store.createCollection(title: "Cover fixture", fields: [])
        var collection = try #require(store.collection(id))
        collection.artwork = artwork
        try store.saveCollection(collection)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let exported = try decoder.decode(LibraryState.self, from: store.export())
        #expect(exported.collections.first?.artwork == artwork)
        #expect(throws: BlueError.invalidValue) { try CollectionArtworkService.prepare(Data([1, 2, 3])) }
        let request = try CollectionArtworkService.request(
            prompt: "Blue forest", style: "Watercolor", model: "gpt-image-2.5-flare", key: "test-key")
        let requestData = try #require(request.httpBody)
        let body = try #require(try JSONSerialization.jsonObject(with: requestData) as? [String: Any])
        #expect(request.url?.host == "api.openai.com")
        #expect(body["n"] as? Int == 4)
        #expect(body["output_format"] as? String == "jpeg")
        #expect((body["prompt"] as? String)?.contains("Blue forest") == true)
    }
}
