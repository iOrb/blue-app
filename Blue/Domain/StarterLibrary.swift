import Foundation

enum StarterLibrary {
    static func fields(for template: String) -> [FieldDefinition] {
        let states: [String]
        switch template {
        case "movies": states = ["wantWatch", "watched"]
        case "tv": states = ["wantWatch", "watching", "finished"]
        case "games": states = ["wantPlay", "playing", "finished"]
        case "artists": states = ["wantExplore", "exploring"]
        case "food": states = ["wantTry", "tried"]
        case "restaurants": states = ["wantVisit", "visited"]
        default: return []
        }
        var fields = [
            FieldDefinition(
                id: "status", label: .key("field.status"), kind: .status,
                options: states.map { FieldOption(id: $0, label: .key("status.\($0)")) }, showInRow: true)
        ]
        if ["movies", "tv", "games"].contains(template) {
            fields.append(FieldDefinition(id: "rating", label: .key("field.rating"), kind: .rating, showInRow: true))
        }
        if ["artists", "restaurants"].contains(template) {
            fields.append(
                FieldDefinition(id: "favorite", label: .key("field.favorite"), kind: .favorite, showInRow: true))
        }
        if template == "food" {
            fields.append(FieldDefinition(id: "like", label: .key("field.like"), kind: .like, showInRow: true))
        }
        return fields
    }

    static func make() -> LibraryState {
        var state = LibraryState()
        let templates = ["movies", "tv", "games", "artists", "food", "restaurants"]
        let symbols = ["film", "tv", "gamecontroller", "music.note", "fork.knife", "wineglass"]
        let examples = [
            [
                "Interstellar", "Dune", "The Godfather", "Blade Runner 2049", "Arrival", "Past Lives", "Perfect Days",
                "Aftersun", "The Grand Budapest Hotel", "Her", "Spirited Away", "The Worst Person in the World",
            ],
            ["Severance", "The Bear", "Slow Horses"],
            ["Journey", "Hollow Knight", "Zelda: Tears of the Kingdom"],
            ["Nils Frahm", "Agnes Obel", "Khruangbin"],
            ["Shakshuka", "Kimchi", "Risotto"],
            ["Bar Brutal", "Gresca", "Disfrutar"],
        ]
        for (index, template) in templates.enumerated() {
            let folder = Folder(title: .key("template.\(template)"))
            let collection = Collection(
                folderID: folder.id, title: folder.title, symbol: symbols[index], fields: fields(for: template))
            state.folders.append(folder)
            state.collections.append(collection)
            for (offset, title) in examples[index].enumerated() {
                let status = collection.fields[0].options[min(offset % 2, collection.fields[0].options.count - 1)].id
                var record = Record(collectionID: collection.id, title: title, values: ["status": .option(status)])
                if index == 0 {
                    let ratings: [Double?] = [9, 8, 10, 8, nil, 9, 9, 8.5, 8, 8.5, 10, nil]
                    if let rating = ratings[offset] {
                        record.values["rating"] = .number(rating)
                        record.values["status"] = .option("watched")
                    }
                    if offset == 0 { record.markdown = .key("demo.interstellar") }
                }
                if template == "artists" && offset == 0 { record.values["favorite"] = .flag(true) }
                state.records.append(record)
            }
        }
        state.notes = [
            Note(title: .key("demo.noteTitle"), markdown: .key("demo.noteBody")),
            Note(title: .key("demo.weekendTitle"), markdown: .key("demo.weekendBody")),
        ]
        return state
    }
}
