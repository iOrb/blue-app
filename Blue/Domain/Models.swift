import Foundation

enum AppLanguage: String, Codable, CaseIterable, Sendable {
    case english = "en"
    case spanish = "es"
    var locale: Locale { Locale(identifier: self == .spanish ? "es_ES" : "en_US") }
}

struct LocalText: Codable, Hashable, Sendable {
    var key: String?
    var english: String
    var spanish: String
    static func key(_ key: String) -> Self { Self(key: key, english: "", spanish: "") }
    static func user(_ value: String) -> Self { Self(english: value, spanish: value) }
    static func bilingual(_ en: String, _ es: String) -> Self { Self(english: en, spanish: es) }
}

enum FieldKind: String, Codable, CaseIterable, Sendable {
    case text, number, rating, date, status, checkbox, like, favorite, tags
    var labelKey: String { "field.\(rawValue)" }
    var isBoolean: Bool { [.checkbox, .like, .favorite].contains(self) }
    var symbol: String {
        switch self {
        case .text: "text.alignleft"
        case .number: "number"
        case .rating: "number.circle"
        case .date: "calendar"
        case .status: "circle.lefthalf.filled"
        case .checkbox: "checkmark.circle"
        case .like: "heart"
        case .favorite: "star"
        case .tags: "tag"
        }
    }
}

struct FieldOption: Codable, Hashable, Identifiable, Sendable {
    var id: String
    var label: LocalText
}

enum IndicatorTint: String, Codable, CaseIterable, Sendable {
    case blue, purple, orange, green, red, pink, yellow
}

struct FieldDefinition: Codable, Hashable, Identifiable, Sendable {
    var id: String
    var label: LocalText
    var kind: FieldKind
    var options: [FieldOption] = []
    var showInRow = false
    var icon: String?
    var tint: IndicatorTint?
}

enum FieldValue: Codable, Hashable, Sendable {
    case text(String)
    case number(Double)
    case date(Date)
    case option(String)
    case flag(Bool)
    case tags([String])
    var number: Double? { if case .number(let value) = self { value } else { nil } }
    var text: String? {
        switch self {
        case .text(let value), .option(let value): value
        case .tags(let values): values.joined(separator: ", ")
        default: nil
        }
    }
    var flag: Bool { if case .flag(let value) = self { value } else { false } }
}

struct Folder: Codable, Hashable, Identifiable, Sendable {
    var id = UUID()
    var title: LocalText
    var parentID: UUID?
}

struct Collection: Codable, Hashable, Identifiable, Sendable {
    var id = UUID()
    var folderID: UUID?
    var title: LocalText
    var symbol: String = "list.bullet"
    var fields: [FieldDefinition]
    var createdAt = Date()
}

struct WebSource: Codable, Hashable, Sendable {
    var title: String
    var summary: String
    var url: URL
}

struct Record: Codable, Hashable, Identifiable, Sendable {
    var id = UUID()
    var collectionID: UUID
    var title: String
    var markdown: LocalText = .user("")
    var values: [String: FieldValue] = [:]
    var favorite: Bool?
    var sources: [WebSource]?
    var isFavorite: Bool { favorite ?? values["favorite"]?.flag ?? false }
    var revision = 0
    var updatedAt = Date()
}

struct Note: Codable, Hashable, Identifiable, Sendable {
    var id = UUID()
    var folderID: UUID?
    var title: LocalText
    var markdown: LocalText
    var favorite: Bool?
    var revision = 0
    var updatedAt = Date()
}

struct SavedAlarm: Codable, Hashable, Identifiable, Sendable {
    var id = UUID()
    var title: String
    var date: Date
    /// Calendar weekday values: Sunday = 1 ... Saturday = 7.
    var weekdays: [Int] = []
    var enabled = false
    var timeZoneID = TimeZone.current.identifier
    var revision = 0
}

struct LibraryState: Codable, Equatable, Sendable {
    var formatVersion = 2
    var folders: [Folder] = []
    var collections: [Collection] = []
    var records: [Record] = []
    var notes: [Note] = []
    var alarms: [SavedAlarm] = []
}

enum BlueError: Error, Equatable {
    case missing, ambiguous, invalidValue, staleRevision, folderDepth, permissionDenied
    case alarmFailed, saveFailed, modelUnavailable, cancelled, unsupported, emptyTitle, webUnavailable
    var key: String { "error.\(String(describing: self))" }
}

struct RecordFilter: Codable, Hashable, Identifiable, Sendable {
    var id: String { fieldID }
    var fieldID: String
    var text: String = ""
    var minimum: Double?
    var maximum: Double?
    var flag: Bool?
    var after: Date?
    var before: Date?
}

struct CollectionQuery: Codable, Equatable, Sendable {
    var search = ""
    var sortField = "title"
    var ascending = true
    var filters: [RecordFilter] = []

    func apply(to records: [Record], fields: [FieldDefinition], locale: Locale) -> [Record] {
        records.filter { record in
            let matchesSearch =
                search.isEmpty
                || record.title.range(of: search, options: [.caseInsensitive, .diacriticInsensitive], locale: locale)
                    != nil
            return matchesSearch
                && filters.allSatisfy { filter in
                    guard
                        let value = filter.fieldID == "__favorite"
                            ? FieldValue.flag(record.isFavorite) : record.values[filter.fieldID]
                    else { return false }
                    if let min = filter.minimum, (value.number ?? -.infinity) < min { return false }
                    if let max = filter.maximum, (value.number ?? .infinity) > max { return false }
                    if let flag = filter.flag, value.flag != flag { return false }
                    if let after = filter.after {
                        guard case .date(let date) = value, date >= after else { return false }
                    }
                    if let before = filter.before {
                        guard case .date(let date) = value, date <= before else { return false }
                    }
                    if !filter.text.isEmpty {
                        if case .option(let option) = value { return option == filter.text }
                        return value.text?.range(
                            of: filter.text, options: [.caseInsensitive, .diacriticInsensitive], locale: locale) != nil
                    }
                    return true
                }
        }.sorted { lhs, rhs in
            let comparison: ComparisonResult
            if sortField == "title" {
                comparison = lhs.title.compare(rhs.title, options: [.caseInsensitive, .numeric], locale: locale)
            } else {
                let left = lhs.values[sortField]
                let right = rhs.values[sortField]
                // Missing values always appear last, independently of direction.
                if left == nil && right != nil { return false }
                if left != nil && right == nil { return true }
                switch (left, right) {
                case (.number(let a), .number(let b)):
                    comparison = a == b ? .orderedSame : (a < b ? .orderedAscending : .orderedDescending)
                case (.date(let a), .date(let b)): comparison = a.compare(b)
                case (.option(let a), .option(let b)):
                    let options = fields.first { $0.id == sortField }?.options.map(\.id) ?? []
                    let ai = options.firstIndex(of: a) ?? Int.max
                    let bi = options.firstIndex(of: b) ?? Int.max
                    comparison = ai == bi ? .orderedSame : (ai < bi ? .orderedAscending : .orderedDescending)
                case (.flag(let a), .flag(let b)):
                    comparison = a == b ? .orderedSame : (!a ? .orderedAscending : .orderedDescending)
                default:
                    comparison = (left?.text ?? "").compare(
                        right?.text ?? "", options: [.caseInsensitive, .numeric], locale: locale)
                }
            }
            if comparison == .orderedSame { return lhs.id.uuidString < rhs.id.uuidString }
            return ascending ? comparison == .orderedAscending : comparison == .orderedDescending
        }
    }
}

enum Validation {
    static func field(_ field: FieldDefinition, value: FieldValue) throws {
        let valid: Bool
        switch (field.kind, value) {
        case (.text, .text(let value)): valid = value.count <= 10_000
        case (.number, .number(let value)): valid = value.isFinite
        case (.rating, .number(let value)): valid = value.isFinite && (0...10).contains(value)
        case (.date, .date): valid = true
        case (.status, .option(let id)): valid = field.options.contains { $0.id == id }
        case (.checkbox, .flag), (.favorite, .flag), (.like, .flag): valid = true
        case (.tags, .tags(let tags)): valid = tags.count <= 30 && tags.allSatisfy { $0.count <= 80 }
        default: valid = false
        }
        guard valid else { throw BlueError.invalidValue }
    }

    static func icon(_ value: String) throws {
        guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, value.count <= 60,
            !value.contains("\n")
        else { throw BlueError.invalidValue }
    }
    static func collection(_ collection: Collection) throws {
        try icon(collection.symbol)
        guard collection.fields.count <= 12, Set(collection.fields.map(\.id)).count == collection.fields.count else {
            throw BlueError.invalidValue
        }
        for field in collection.fields {
            if let icon = field.icon { try self.icon(icon) }
            guard !field.id.isEmpty, field.id.count <= 80 else { throw BlueError.invalidValue }
            if field.label.key == nil {
                guard !field.label.english.trimmingCharacters(in: .whitespaces).isEmpty,
                    !field.label.spanish.trimmingCharacters(in: .whitespaces).isEmpty,
                    field.label.english.count <= 120, field.label.spanish.count <= 120
                else { throw BlueError.invalidValue }
            }
            if field.kind == .status {
                guard !field.options.isEmpty, field.options.count <= 12,
                    Set(field.options.map(\.id)).count == field.options.count
                else { throw BlueError.invalidValue }
                for option in field.options {
                    guard !option.id.isEmpty, option.id.count <= 80 else { throw BlueError.invalidValue }
                    if option.label.key == nil {
                        guard !option.label.english.trimmingCharacters(in: .whitespaces).isEmpty,
                            !option.label.spanish.trimmingCharacters(in: .whitespaces).isEmpty,
                            option.label.english.count <= 120, option.label.spanish.count <= 120
                        else { throw BlueError.invalidValue }
                    }
                }
            }
        }
    }

    static func folder(parentID: UUID?, in folders: [Folder]) throws {
        if let parentID {
            guard let parent = folders.first(where: { $0.id == parentID }) else { throw BlueError.missing }
            guard parent.parentID == nil else { throw BlueError.folderDepth }
        }
    }

    static func title(_ value: String) throws {
        guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw BlueError.emptyTitle }
        guard value.count <= 240 else { throw BlueError.invalidValue }
    }
}

/// A model can only receive write tools after an explicit user action word.
/// Unknown phrasing fails closed; inference still chooses and validates every tool argument.
enum MutationIntent {
    static func isExplicit(_ prompt: String) -> Bool {
        let text = prompt.folding(
            options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US_POSIX")
        ).lowercased().replacingOccurrences(of: "’", with: "'")
        let words = text.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
        guard let first = words.first else { return false }
        if [
            "what", "why", "how", "when", "where", "who", "which", "que", "como", "cuando", "donde", "quien", "cual",
            "no", "never", "nunca",
        ].contains(first) {
            return false
        }
        if text.contains("don't") || text.contains("do not") || text.contains("no cambies") { return false }
        let actions: Set<String> = [
            "change", "set", "update", "add", "create", "make", "delete", "remove", "rename", "move", "cancel",
            "schedule", "enable", "disable", "mark", "rate", "save", "cambia", "cambiar", "pon", "ponle", "poner",
            "actualiza", "actualizar", "anade", "anadir", "agrega", "crea", "crear", "haz", "hacer", "elimina",
            "eliminar", "borra", "borrar", "quita", "renombra", "mueve", "programa", "activa", "desactiva", "marca",
            "puntua", "guarda", "modifica", "modify", "personaliza", "apunta", "anota", "rellena", "completa",
            "enriquece", "fill", "enrich", "complete",
            "capture",
        ]
        return !actions.isDisjoint(with: words)
    }
}

/// Prevent numeric drift (especially Spanish decimal commas) and unsupported personal values.
enum UserValueEvidence {
    static func contains(number: Double, in prompt: String) -> Bool {
        let expression = try! NSRegularExpression(pattern: "[+-]?[0-9]+(?:[.,][0-9]+)?")
        let range = NSRange(prompt.startIndex..., in: prompt)
        for match in expression.matches(in: prompt, range: range) {
            if let range = Range(match.range, in: prompt),
                Double(prompt[range].replacingOccurrences(of: ",", with: ".")) == number
            {
                return true
            }
        }
        for locale in ["en_US", "es_ES"] {
            let formatter = NumberFormatter()
            formatter.locale = Locale(identifier: locale)
            formatter.numberStyle = .spellOut
            if prompt.components(separatedBy: .whitespacesAndNewlines).contains(where: {
                formatter.number(from: $0)?.doubleValue == number
            }) {
                return true
            }
        }
        return false
    }
}

enum PublicLookupIntent {
    static func allowed(prompt: String, collectionName: String) -> Bool {
        let text = (prompt + " " + collectionName).folding(
            options: [.caseInsensitive, .diacriticInsensitive], locale: .init(identifier: "en_US"))
        let words = Set(text.components(separatedBy: CharacterSet.alphanumerics.inverted))
        return !Set([
            "web", "wikipedia", "internet", "online", "movie", "movies", "film", "films", "pelicula", "peliculas",
            "peli", "pelis", "series", "tv", "game", "games", "juego", "juegos", "artist", "artists", "artista",
            "artistas", "album", "book", "books", "libro", "libros", "restaurant", "restaurants", "restaurante",
            "restaurantes",
        ]).isDisjoint(with: words)
    }
}

enum MarkdownRequest {
    static func preservingFormat(_ markdown: String, prompt: String, existing: String = "") -> String {
        let wantsChecklist =
            ["checklist", "check list", "casillas", "lista de tareas"].contains {
                prompt.localizedCaseInsensitiveContains($0)
            } || existing.contains("- [")
        guard wantsChecklist else { return markdown }
        return markdown.components(separatedBy: "\n").map { line in
            if line.hasPrefix("- ") && !line.hasPrefix("- [") { return "- [ ] " + line.dropFirst(2) }
            return line
        }.joined(separator: "\n")
    }
}
