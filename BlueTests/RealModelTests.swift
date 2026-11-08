import Foundation
import FoundationModels
import Testing

@testable import Blue

@MainActor
struct RealModelTests {
    @Test
    func realModelReadsAndEditsPersistedRecord() async throws {
        #expect(SystemLanguageModel.default.isAvailable)
        guard SystemLanguageModel.default.isAvailable else { return }
        let store = try LibraryStore(inMemory: true)
        let scheduler = FakeScheduler()
        let context = ToolContext(
            store: store, alarms: AlarmService(store: store, scheduler: scheduler), language: .english, previous: nil)
        let session = LanguageModelSession(
            model: SystemLanguageModel.default,
            tools: [FindRecordsTool(context: context), EditRecordTool(context: context)],
            instructions:
                "Use tools to read and edit saved data. Never invent data. Ratings use fieldID rating and valueType number. Do not perform an edit until asked. Use the exact ID returned by findRecords."
        )
        let clock = ContinuousClock()
        let start = clock.now
        _ = try await session.respond(to: "Find the saved record with title Interstellar. What rating did I give it?")
        guard case .records(let ids, _) = context.result else {
            Issue.record("The real model did not call findRecords")
            return
        }
        #expect(ids.count == 1)
        #expect(store.record(ids[0])?.values["rating"] == .number(9))
        let readElapsed = start.duration(to: clock.now)
        context.mutationsAllowed = true
        _ = try await session.respond(to: "Change that same Interstellar record's rating to 10 using editRecord.")
        #expect(context.didMutate)
        #expect(store.record(ids[0])?.values["rating"] == .number(10))
        print("REAL_MODEL_READ_DURATION=\(readElapsed)")
        print("REAL_MODEL_TOTAL_DURATION=\(start.duration(to: clock.now))")
    }
}
