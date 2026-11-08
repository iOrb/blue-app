import Foundation
import FoundationModels

struct PendingCollectionChange: Codable, Equatable, Sendable {
    var original: Collection
    var proposed: Collection
    var revisions: [UUID: Int]
}

struct DescribeCollectionTool: Tool {
    let name = "describeCollection"
    let description =
        "Read a collection's exact ID, field IDs, labels, types, icons and choices before modifying its schema."
    let context: ToolContext
    @Generable struct Arguments { var name: String }
    func call(arguments: Arguments) async throws -> String { try await perform(arguments.name) }
    @MainActor private func perform(_ name: String) throws -> String {
        try context.check()
        let en = Localizer(language: .english)
        let es = Localizer(language: .spanish)
        let matches = context.store.state.collections.filter {
            en.text($0.title).localizedCaseInsensitiveCompare(name) == .orderedSame
                || es.text($0.title).localizedCaseInsensitiveCompare(name) == .orderedSame
        }
        guard matches.count == 1, let collection = matches.first else { throw BlueError.ambiguous }
        context.readCollections[collection.id] = collection
        return String(decoding: try JSONEncoder().encode(collection), as: UTF8.self)
    }
}

struct ModifyCollectionTool: Tool {
    let name = "modifyCollection"
    let description =
        "Modify a previously described collection: add/change/remove fields, change field icons and colors, or the collection icon/name. For custom yes/no indicators use checkbox with the exact user meaning, emoji icon and color. Unfilled field removal is immediate; removal of saved values requires confirmation in the app."
    let context: ToolContext
    @Generable struct Arguments {
        var collectionID: String
        var title: String?
        @Guide(description: "An emoji such as 🚬 or a valid SF Symbol name. Nil preserves the collection icon.")
        var icon: String?
        @Guide(.count(0...8)) var fields: [CreateCollectionTool.ProposedField]
        @Guide(description: "Exact existing field IDs to remove, only when the user explicitly asks.", .count(0...12))
        var removeFieldIDs: [String]
    }
    func call(arguments: Arguments) async throws -> String { try await perform(arguments) }
    @MainActor private func perform(_ arguments: Arguments) throws -> String {
        try context.check(mutation: true)
        guard let id = UUID(uuidString: arguments.collectionID), let original = context.readCollections[id],
            context.store.collection(id) == original
        else { throw BlueError.staleRevision }
        var proposed = original
        if let title = arguments.title, !title.trimmingCharacters(in: .whitespaces).isEmpty {
            try Validation.title(title)
            proposed.title = .user(title)
        }
        if let icon = arguments.icon, !icon.trimmingCharacters(in: .whitespaces).isEmpty {
            try Validation.icon(icon)
            proposed.symbol = icon
        }
        guard arguments.removeFieldIDs.allSatisfy({ id in original.fields.contains { $0.id == id } }) else {
            throw BlueError.invalidValue
        }
        proposed.fields.removeAll { arguments.removeFieldIDs.contains($0.id) }
        for input in arguments.fields {
            let field = try input.validated()
            guard !arguments.removeFieldIDs.contains(field.id) else { throw BlueError.invalidValue }
            if let index = proposed.fields.firstIndex(where: { $0.id == field.id }) {
                proposed.fields[index] = field
            } else {
                proposed.fields.append(field)
            }
        }
        try Validation.collection(proposed)
        let records = context.store.records(in: id)
        let losesValues = records.contains { record in
            record.values.contains { key, value in
                guard let field = proposed.fields.first(where: { $0.id == key }) else { return true }
                return (try? Validation.field(field, value: value)) == nil
            }
        }
        if losesValues {
            context.result = .confirmCollectionChange(
                PendingCollectionChange(
                    original: original, proposed: proposed,
                    revisions: Dictionary(uniqueKeysWithValues: records.map { ($0.id, $0.revision) })))
            return "Change prepared for user confirmation; no values have been deleted."
        }
        try context.store.saveCollection(proposed)
        context.didMutate = true
        context.result = .collection(id)
        return "Saved collection layout, fields and icons."
    }
}

struct EditNoteTool: Tool {
    let name = "editNote"
    let description =
        "Edit a previously read Markdown note. Preserve unrelated content. Return complete Markdown with the requested edits, not an explanation."
    let context: ToolContext
    @Generable struct Arguments {
        var noteID: String
        var title: String?
        @Guide(
            description:
                "Complete Markdown source. Preserve existing headings (#) and checkbox markers (- [ ]). Add requested items in the same format."
        ) var markdown: String
    }
    func call(arguments: Arguments) async throws -> String { try await perform(arguments) }
    @MainActor private func perform(_ arguments: Arguments) throws -> String {
        try context.check(mutation: true)
        guard let id = UUID(uuidString: arguments.noteID), let revision = context.readNoteRevisions[id],
            var note = context.store.state.notes.first(where: { $0.id == id }), note.revision == revision,
            arguments.markdown.count <= 20_000,
            Localizer(language: context.language).text(note.markdown).count <= 12_000
        else { throw BlueError.staleRevision }
        if let title = arguments.title, !title.trimmingCharacters(in: .whitespaces).isEmpty {
            try Validation.title(title)
            note.title = .user(title)
        }
        note.markdown = .user(
            MarkdownRequest.preservingFormat(
                arguments.markdown, prompt: context.sourcePrompt,
                existing: Localizer(language: context.language).text(note.markdown)))
        try context.store.saveNote(note, expectedRevision: revision)
        context.didMutate = true
        context.result = .notes([id])
        return "Saved the edited Markdown note."
    }
}

struct CustomizeIndicatorsTool: Tool {
    let name = "customizeIndicators"
    let description =
        "Change a collection icon and add or restyle visual on/off indicators. Each indicator has its own user-defined meaning, emoji/SF Symbol and color. Existing properties keep their type and values."
    let context: ToolContext
    @Generable struct Indicator {
        var id: String
        var english: String
        var spanish: String
        var icon: String
        var color: CreateCollectionTool.ProposedTint
    }
    @Generable struct Arguments {
        var collectionID: String
        @Guide(description: "Collection emoji or SF Symbol; empty preserves its existing icon.") var collectionIcon:
            String
        @Guide(.count(0...6)) var indicators: [Indicator]
    }
    func call(arguments: Arguments) async throws -> String { try await perform(arguments) }
    @MainActor private func perform(_ arguments: Arguments) throws -> String {
        try context.check(mutation: true)
        guard let id = UUID(uuidString: arguments.collectionID), let original = context.readCollections[id],
            context.store.collection(id) == original
        else { throw BlueError.staleRevision }
        var collection = original
        if !arguments.collectionIcon.trimmingCharacters(in: .whitespaces).isEmpty {
            try Validation.icon(arguments.collectionIcon)
            collection.symbol = arguments.collectionIcon
        }
        for input in arguments.indicators {
            guard !input.id.isEmpty else { throw BlueError.invalidValue }
            try Validation.icon(input.icon)
            if let index = collection.fields.firstIndex(where: { $0.id == input.id }) {
                collection.fields[index].label = .bilingual(input.english, input.spanish)
                collection.fields[index].icon = input.icon
                collection.fields[index].tint = IndicatorTint(rawValue: input.color.rawValue)
            } else {
                collection.fields.append(
                    FieldDefinition(
                        id: input.id, label: .bilingual(input.english, input.spanish),
                        kind: .checkbox, showInRow: true, icon: input.icon,
                        tint: IndicatorTint(rawValue: input.color.rawValue)))
            }
        }
        try context.store.saveCollection(collection)
        context.didMutate = true
        context.result = .collection(id)
        return "Saved the collection icon and its indicators."
    }
}

struct RemoveFieldsTool: Tool {
    let name = "removeFields"
    let description =
        "Remove explicitly requested field IDs from a previously described collection. If any saved values would be lost, the app shows a confirmation and keeps them until approved."
    let context: ToolContext
    @Generable struct Arguments {
        var collectionID: String
        @Guide(description: "Exact field IDs from describeCollection.", .count(1...12)) var fieldIDs: [String]
    }
    func call(arguments: Arguments) async throws -> String {
        try await ModifyCollectionTool(context: context).call(
            arguments: .init(
                collectionID: arguments.collectionID,
                title: nil, icon: nil, fields: [], removeFieldIDs: arguments.fieldIDs))
    }
}
