import Foundation
import FoundationModels

@Generable enum LibraryEntityKind: String { case record, note, collection, event }
@Generable enum AssistantOperation { case read, write, delete, clarify }
@Generable enum SemanticReference { case openEntity, namedEntities, newEntity }
@Generable struct AssistantDecision {
    @Guide(
        description:
            "namedEntities for explicit titles such as Interstellar; newEntity for creating new content such as a new calendar event; openEntity only for pronouns/unnamed properties when a saved entity is actually open."
    )
    var reference: SemanticReference
    @Guide(
        description:
            "Exact property IDs requested for display; rating for numeric movie scores/nota. Empty for all properties.",
        .count(0...12))
    var fieldIDs: [String]
    @Guide(
        description:
            "records for a collection item or its numeric rating (nota/puntuación in Spanish); notes only for a standalone written document. Pronouns refer to the open entity. schema for collection properties/icons."
    )
    var area: AssistantArea
    @Guide(
        description:
            "read for questions, write only for a requested change, delete to prepare confirmation, clarify if intent or identity is uncertain. Negated changes are read."
    )
    var operation: AssistantOperation
    @Guide(
        description:
            "Allow public lookup only for published works, public places/people or explicitly requested public facts. Never for private notes or personal topics."
    )
    var publicLookup: Bool
    @Guide(
        description:
            "True if the user asks for a proposal, rewrite suggestion or discussion of saved content without saving. False for simply displaying saved values or making an edit."
    ) var discussion: Bool
    var clarification: String?
}

/// Paginated identity catalog and exact-ID reads. The model interprets meaning; this tool never parses the request.
struct ReadLibraryTool: Tool {
    let name = "readLibrary"
    let description =
        "Read saved data. Empty ids lists a page of titles and IDs (not a search). Select exact IDs semantically, then call again with those IDs to read their content before editing. Never guess IDs. Continue pages using nextOffset. fields restricts the displayed item properties; empty shows all."
    let context: ToolContext
    @Generable struct Arguments {
        var kind: LibraryEntityKind
        @Guide(
            description:
                "Exact UUIDs from context/catalog; use @selected for the currently open entity of this kind. Empty to browse.",
            .count(0...8)) var ids: [String]
        var offset: Int
        @Guide(.count(0...12)) var fields: [String]
    }
    func call(arguments: Arguments) async throws -> String { try await perform(arguments) }
    @MainActor private func perform(_ args: Arguments) throws -> String {
        try context.check()
        guard args.offset >= 0, args.offset <= 100_000 else { throw BlueError.invalidValue }
        let l = Localizer(language: context.language)
        let state = context.store.state
        if args.ids.isEmpty {
            let catalog: [[String: String]]
            switch args.kind {
            case .record:
                catalog = state.records.map {
                    ["id": $0.id.uuidString, "title": $0.title, "collectionID": $0.collectionID.uuidString]
                }
            case .note: catalog = state.notes.map { ["id": $0.id.uuidString, "title": l.text($0.title)] }
            case .collection:
                catalog = state.collections.map { ["id": $0.id.uuidString, "title": l.text($0.title)] }
            case .event:
                catalog = (state.events ?? []).map {
                    ["id": $0.id.uuidString, "title": $0.title, "date": $0.date.ISO8601Format()]
                }
            }
            let page = Array(catalog.dropFirst(args.offset).prefix(24))
            let object: [String: Any] = [
                "items": page, "nextOffset": args.offset + page.count < catalog.count ? args.offset + page.count : -1,
                "total": catalog.count,
            ]
            return String(
                decoding: try JSONSerialization.data(withJSONObject: object, options: .sortedKeys), as: UTF8.self)
        }
        #if os(macOS)
            FileHandle.standardError.write(Data("MODEL_READ_KIND=\(args.kind) COUNT=\(args.ids.count)\n".utf8))
        #endif
        let ids = try args.ids.map { raw in
            if raw == "@selected" {
                let selected: UUID? =
                    switch args.kind {
                    case .record: context.selectedRecordID
                    case .note: context.selectedNoteID
                    case .collection: context.selectedCollectionID
                    case .event: context.selectedEventID
                    }
                guard let selected else { throw BlueError.ambiguous }
                return selected
            }
            guard let id = UUID(uuidString: raw) else { throw BlueError.invalidValue }
            return id
        }
        let valid: Bool =
            switch args.kind {
            case .record: ids.allSatisfy { id in state.records.contains { $0.id == id } }
            case .note: ids.allSatisfy { id in state.notes.contains { $0.id == id } }
            case .collection: ids.allSatisfy { id in state.collections.contains { $0.id == id } }
            case .event: ids.allSatisfy { id in state.events?.contains { $0.id == id } == true }
            }
        guard valid else {
            return
                "No such ID for this kind. Browse the catalog with empty ids, or use @selected for the open entity. No change was made."
        }
        var selection = AssistantSelection(fields: args.fields)
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        encoder.dateEncodingStrategy = .iso8601
        let data: Data
        switch args.kind {
        case .record:
            let records = try ids.map { id in
                guard let record = context.store.record(id) else { throw BlueError.missing }
                return record
            }
            for record in records { context.readRevisions[record.id] = record.revision }
            let validFields = Set(
                ["__favorite", "markdown"]
                    + records.flatMap { context.store.collection($0.collectionID)?.fields.map(\.id) ?? [] })
            if !args.fields.allSatisfy(validFields.contains) {
                return "Use exact semantic field IDs, not translated labels. Available fields: "
                    + validFields.sorted().joined(separator: ", ") + ". Call readLibrary again."
            }
            selection.records = ids
            let recordsData = try encoder.encode(
                records.map { record in
                    var copy = record
                    copy.markdown = .user(String(l.text(record.markdown).prefix(1800)))
                    copy.sources = record.sources?.prefix(2).map {
                        WebSource(title: $0.title, summary: String($0.summary.prefix(600)), url: $0.url)
                    }
                    return copy
                })
            let schemas = state.collections.filter { collection in records.contains { $0.collectionID == collection.id }
            }
            data = try JSONSerialization.data(
                withJSONObject: [
                    "records": JSONSerialization.jsonObject(with: recordsData),
                    "schemas": JSONSerialization.jsonObject(with: encoder.encode(schemas)),
                ], options: .sortedKeys)
        case .note:
            let notes = try ids.map { id in
                guard let note = state.notes.first(where: { $0.id == id }) else { throw BlueError.missing }
                return note
            }
            for note in notes { context.readNoteRevisions[note.id] = note.revision }
            selection.notes = ids
            data = try encoder.encode(
                notes.map { note in
                    var copy = note
                    copy.markdown = .user(String(l.text(note.markdown).prefix(12000)))
                    return copy
                })
        case .collection:
            let collections = try ids.map { id in
                guard let collection = context.store.collection(id) else { throw BlueError.missing }
                return collection
            }
            for collection in collections { context.readCollections[collection.id] = collection }
            selection.collections = ids
            data = try encoder.encode(collections)
        case .event:
            let events = try ids.map { id in
                guard let event = state.events?.first(where: { $0.id == id }) else { throw BlueError.missing }
                return event
            }
            for event in events { context.readEventRevisions[event.id] = event.revision }
            selection.events = ids
            data = try encoder.encode(events)
        }
        guard data.count <= 24_000 else { throw BlueError.invalidValue }
        context.result = .selection(selection)
        return String(decoding: data, as: UTF8.self)
    }
}

struct CalendarEventsTool: Tool {
    let name = "calendarEvents"
    let description =
        "Find, create or update standard calendar events. Alarm and reminder mean event. Every future event rings on the iPhone and notifies. Only name, day, time, optional weekly repeat and notes are editable. Never invent recurrence."
    let context: ToolContext
    @Generable enum Action { case find, create, update }
    @Generable struct Arguments {
        var action: Action
        var eventID: String?
        var title: String?
        @Guide(
            description:
                "ISO8601 timestamp including timezone. Keep the existing date unless the user asks to change it.")
        var dateISO8601: String
        var notes: String?
        @Guide(
            description:
                "Only when the user explicitly requests weekly repetition: 1 Sunday through 7 Saturday. Empty clears repetition; omitted preserves it."
        ) var weekdays: [Int]?
    }
    func call(arguments: Arguments) async throws -> String { try await perform(arguments) }
    @MainActor private func perform(_ args: Arguments) async throws -> String {
        try context.check(mutation: args.action != .find)
        guard let date = ISO8601DateFormatter().date(from: args.dateISO8601) else { throw BlueError.invalidValue }
        if args.action == .find {
            let events = (context.store.state.events ?? []).filter { $0.occurs(on: date) }
            for event in events { context.readEventRevisions[event.id] = event.revision }
            context.result = .events(events.map(\.id))
            let items = events.map { event -> [String: Any] in
                [
                    "id": event.id.uuidString, "title": event.title, "date": event.date.ISO8601Format(),
                    "weekdays": event.repeatDays, "notes": event.notes ?? "",
                ]
            }
            return String(decoding: try JSONSerialization.data(withJSONObject: items), as: UTF8.self)
        }
        var event = CalendarEvent(title: Localizer(language: context.language)("event.title"), date: date)
        var revision: Int?
        if args.action == .update {
            guard let raw = args.eventID, let id = UUID(uuidString: raw), let read = context.readEventRevisions[id],
                let existing = context.store.state.events?.first(where: { $0.id == id }), existing.revision == read
            else { throw BlueError.staleRevision }
            event = existing
            event.date = date
            revision = read
        }
        if let title = args.title, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            event.title = title
        }
        if let notes = args.notes { event.notes = notes.isEmpty ? nil : notes }
        if let weekdays = args.weekdays { event.repeatDays = weekdays }
        try Validation.event(event)
        #if os(iOS)
            try await context.alarms.saveTimedEvent(event, expectedRevision: revision)
        #else
            try context.store.saveEvent(event, expectedRevision: revision)
        #endif
        context.didMutate = true
        context.result = .events([event.id])
        return "Saved calendar event \(event.id)."
    }
}

struct ProposeDeletionTool: Tool {
    let name = "proposeDeletion"
    let description =
        "Prepare deletion of one previously read item, note, collection or calendar event. Nothing is deleted until the user confirms in the app."
    let context: ToolContext
    @Generable struct Arguments {
        var kind: LibraryEntityKind
        var id: String
    }
    func call(arguments: Arguments) async throws -> String { try await perform(arguments) }
    @MainActor private func perform(_ args: Arguments) throws -> String {
        try context.check(mutation: true)
        guard let id = UUID(uuidString: args.id) else { throw BlueError.invalidValue }
        var pending = PendingDeletion(kind: args.kind.rawValue, id: id)
        switch args.kind {
        case .record:
            guard let revision = context.readRevisions[id] else { throw BlueError.ambiguous }
            pending.revision = revision
        case .note:
            guard let revision = context.readNoteRevisions[id] else { throw BlueError.ambiguous }
            pending.revision = revision
        case .event:
            guard let revision = context.readEventRevisions[id] else { throw BlueError.ambiguous }
            pending.revision = revision
        case .collection:
            guard let collection = context.readCollections[id] else { throw BlueError.ambiguous }
            pending.collection = collection
            pending.recordRevisions = Dictionary(
                uniqueKeysWithValues: context.store.records(in: id).map { ($0.id, $0.revision) })
        }
        context.result = .confirmDeletion(pending)
        return "Deletion prepared. Awaiting user confirmation; nothing has been removed."
    }
}

@Generable struct SemanticTargets {
    @Guide(
        description:
            "True when the request refers to the currently open entity without explicitly naming a different entity: it, that, its rating, esa, su nota, that paragraph. False when creating something new or naming another entity."
    )
    var useOpenEntity: Bool
    @Guide(
        description:
            "Indices of the exact existing entities referred to in this request. Choose semantically using titles, collection and open selection. Empty for a new entity or a greeting. Never pick an unrelated entity. Multiple same-title matches must all be included for clarification.",
        .count(0...8))
    var indices: [Int]
    @Guide(
        description:
            "Exact saved field IDs requested for display, e.g. rating for a movie score/nota. Empty for all properties or if no property was requested. Do not translate IDs.",
        .count(0...12))
    var fields: [String]
}

@Generable struct NoteRevisionDraft {
    @Guide(
        description:
            "True only when the user asks to change the note's title. A heading inside the text is not the title.")
    var editTitle: Bool
    @Guide(
        description:
            "True only when the user asks to change the written body or its paragraphs. False when only renaming the note; preserve its body and headings exactly."
    ) var editBody: Bool
    @Generable struct Edit {
        @Guide(
            description:
                "Index of the existing Markdown block to edit. -1 only if explicitly renaming the document; block count appends new content."
        ) var blockIndex: Int
        @Guide(
            description:
                "A standalone editing instruction for this one block, in English. Resolve paragraph references now; for example: Make this text more concise. Do not copy the block content."
        ) var instruction: String
        @Guide(
            description:
                "Verbatim replacement only when the user supplies the exact new text, such as a new title. Preserve its language and spelling. Nil when the task is to rewrite or shorten existing text."
        ) var literalReplacement: String?
    }
    @Guide(
        description: "Only the blocks the user requested to change. Preserve all other blocks by omitting them.",
        .count(1...6)) var edits: [Edit]
}

@Generable struct SemanticSchemaEdit {
    @Generable enum Operation { case removeFields, customizeIndicators, modify }
    var operation: Operation
    @Guide(description: "Exact saved field IDs to remove; empty for other operations.", .count(0...12)) var fieldIDs:
        [String]
}

@Generable struct ConversationalTurn {
    @Generable enum Kind { case greeting, acknowledgement, capabilities, generalConversation, savedContent }
    @Guide(
        description:
            "Classify what the message is asking for. Use savedContent for any request about the user's notes, items, properties, collections, calendar, or a previously proposed edit. A question asking for an item's score needs savedContent."
    ) var kind: Kind
}

@Generable struct ChangePermission {
    @Guide(
        description:
            "Explain whether the user asks to save a change now, or only to discuss/read/propose without saving. Preserve any negation or 'not yet' constraint."
    ) var reason: String
    @Guide(
        description:
            "True only if this message authorizes a saved change now. A suggestion or proposal that the user has not accepted is false."
    ) var saveNow: Bool
    @Guide(description: "True if the user requests a suggested rewrite or discussion without saving it yet.")
    var proposal: Bool
}

@Generable struct ProposalAcceptance {
    @Generable enum Action { case acceptExistingProposal, differentEdit, discussion }
    @Guide(
        description:
            "Classify the current message: accepting the exact existing proposal, requesting a different edit such as renaming, or discussing without saving."
    ) var action: Action
}

@Generable struct NoteReadIntent {
    @Guide(
        description:
            "True when the user wants candidate wording: a shorter version, rewrite, suggested title or replacement paragraph, even when asking not to save it yet. False for explaining, summarizing or answering a question about the note."
    )
    var rewriteProposal: Bool
}
