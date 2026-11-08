import Foundation
import FoundationModels

struct CollectionQueryTool: Tool {
    let name = "viewCollection"
    let description =
        "Open a collection with typed filters and a sort order. Use empty filters to show all. The universal favorite filter uses fieldID __favorite and selected true. Status values use semantic option IDs; describe the collection first with no filters if its fields are unknown."
    let context: ToolContext
    @Generable struct Filter {
        var fieldID: String
        var text: String?
        var minimum: Double?
        var maximum: Double?
        var selected: Bool?
    }
    @Generable struct Arguments {
        var collectionName: String
        @Guide(description: "title or an exact property ID; rating for media ratings") var sortFieldID: String
        var ascending: Bool
        var filters: [Filter]
    }
    func call(arguments: Arguments) async throws -> String { try await perform(arguments) }
    @MainActor private func perform(_ arguments: Arguments) throws -> String {
        try context.check()
        try Validation.title(arguments.collectionName)
        let en = Localizer(language: .english)
        let es = Localizer(language: .spanish)
        let matches = context.store.state.collections.filter {
            en.text($0.title).localizedCaseInsensitiveContains(arguments.collectionName)
                || es.text($0.title).localizedCaseInsensitiveContains(arguments.collectionName)
        }
        guard matches.count == 1, let collection = matches.first else {
            throw matches.isEmpty ? BlueError.missing : BlueError.ambiguous
        }
        guard arguments.sortFieldID == "title" || collection.fields.contains(where: { $0.id == arguments.sortFieldID })
        else { throw BlueError.invalidValue }
        guard arguments.filters.count <= collection.fields.count + 1 else { throw BlueError.invalidValue }
        let filters = try arguments.filters.map { input -> RecordFilter in
            if input.fieldID == "__favorite" {
                guard let selected = input.selected, input.minimum == nil, input.maximum == nil,
                    input.text == nil || input.text == ""
                else { throw BlueError.invalidValue }
                return RecordFilter(fieldID: "__favorite", flag: selected)
            }
            guard let field = collection.fields.first(where: { $0.id == input.fieldID }) else {
                throw BlueError.invalidValue
            }
            if let min = input.minimum {
                guard min.isFinite, [.rating, .number].contains(field.kind) else { throw BlueError.invalidValue }
            }
            if let max = input.maximum {
                guard max.isFinite, [.rating, .number].contains(field.kind) else { throw BlueError.invalidValue }
            }
            if input.selected != nil { guard field.kind.isBoolean else { throw BlueError.invalidValue } }
            if let minimum = input.minimum, let maximum = input.maximum, minimum > maximum {
                throw BlueError.invalidValue
            }
            if field.kind == .rating {
                guard input.minimum.map({ (0...10).contains($0) }) ?? true,
                    input.maximum.map({ (0...10).contains($0) }) ?? true
                else { throw BlueError.invalidValue }
            }
            if let text = input.text {
                guard text.count <= 240, [.text, .tags, .status].contains(field.kind) else {
                    throw BlueError.invalidValue
                }
            }
            if let text = input.text, field.kind == .status {
                guard field.options.contains(where: { $0.id == text }) else { throw BlueError.invalidValue }
            }
            return RecordFilter(
                fieldID: input.fieldID, text: input.text ?? "", minimum: input.minimum, maximum: input.maximum,
                flag: input.selected)
        }
        guard Set(filters.map(\.id)).count == filters.count else { throw BlueError.invalidValue }
        let query = CollectionQuery(sortField: arguments.sortFieldID, ascending: arguments.ascending, filters: filters)
        let records = query.apply(
            to: context.store.records(in: collection.id), fields: collection.fields, locale: context.language.locale)
        context.result = .collectionView(collection.id, query)
        let schema = String(decoding: try JSONEncoder().encode(collection.fields), as: UTF8.self)
        return "Collection \(collection.id.uuidString), \(records.count) matching items. Fields: \(schema)"
    }
}

struct CreateNoteTool: Tool {
    let name = "createNote"
    let description =
        "Create one Markdown note from the user's request, in the selected language. Keep user-provided names and wording."
    let context: ToolContext
    @Generable struct Arguments {
        var title: String
        @Guide(
            description:
                "Markdown source. Preserve requested formatting: headings start with # and checklist items with - [ ]. Use actual newlines."
        ) var markdown: String
    }
    func call(arguments: Arguments) async throws -> String { try await perform(arguments) }
    @MainActor private func perform(_ arguments: Arguments) throws -> String {
        try context.check(mutation: true)
        try Validation.title(arguments.title)
        guard arguments.markdown.count <= 20_000 else { throw BlueError.invalidValue }
        let note = Note(
            title: .user(arguments.title),
            markdown: .user(arguments.markdown))
        try context.store.saveNote(note, expectedRevision: nil)
        context.didMutate = true
        context.result = .notes([note.id])
        return "Saved note \(note.id.uuidString)."
    }
}
