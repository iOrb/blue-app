import Foundation
import Observation
import SwiftData

enum BlueSchemaV1: VersionedSchema {
    static let versionIdentifier = Schema.Version(1, 0, 0)
    static var models: [any PersistentModel.Type] { [StoredItem.self] }

    @Model
    final class StoredItem {
        @Attribute(.unique) var key: String
        var payload: Data
        init(key: String, payload: Data) {
            self.key = key
            self.payload = payload
        }
    }
}

enum BlueMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [BlueSchemaV1.self] }
    static var stages: [MigrationStage] { [] }
}

@MainActor
@Observable
final class LibraryStore {
    private(set) var state: LibraryState
    let container: ModelContainer
    private let context: ModelContext
    private var entities: [String: BlueSchemaV1.StoredItem] = [:]

    init(inMemory: Bool = false, url: URL? = nil, seed: Bool = true) throws {
        let schema = Schema(versionedSchema: BlueSchemaV1.self)
        let config: ModelConfiguration
        if let url {
            config = ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)
        } else {
            config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory, cloudKitDatabase: .none)
        }
        container = try ModelContainer(for: schema, migrationPlan: BlueMigrationPlan.self, configurations: config)
        context = ModelContext(container)
        context.autosaveEnabled = false
        let rows = try context.fetch(FetchDescriptor<BlueSchemaV1.StoredItem>())
        entities = Dictionary(uniqueKeysWithValues: rows.map { ($0.key, $0) })
        state = LibraryState()
        let decoder = JSONDecoder()
        for row in rows {
            switch row.key.split(separator: ":").first {
            case "folder": state.folders.append(try decoder.decode(Folder.self, from: row.payload))
            case "collection": state.collections.append(try decoder.decode(Collection.self, from: row.payload))
            case "record": state.records.append(try decoder.decode(Record.self, from: row.payload))
            case "note": state.notes.append(try decoder.decode(Note.self, from: row.payload))
            case "event":
                state.events = (state.events ?? []) + [try decoder.decode(CalendarEvent.self, from: row.payload)]
            case "alarm": state.alarms.append(try decoder.decode(SavedAlarm.self, from: row.payload))
            default: break
            }
        }
        state.collections.sort { $0.createdAt < $1.createdAt }
        if entities["metadata:initialized"] == nil {
            if seed { state = StarterLibrary.make() }
            try persist(state)
        }
        if !state.folders.isEmpty {
            state = Self.flattened(state)
            try persist(state)
        }
    }

    /// Payload migration: remove the legacy container layer without dropping user content.
    static func flattened(_ original: LibraryState) -> LibraryState {
        var next = original
        for folder in original.folders {
            let existing = next.collections.first { $0.folderID == folder.id }
            var destination = existing?.id
            if destination == nil {
                let collection = Collection(id: folder.id, title: folder.title, fields: [])
                next.collections.append(collection)
                destination = collection.id
            }
            if let destination {
                for note in next.notes.filter({ $0.folderID == folder.id }) {
                    next.records.append(
                        Record(
                            id: note.id, collectionID: destination,
                            title: Localizer(language: .english).text(note.title), markdown: note.markdown,
                            favorite: note.favorite, revision: note.revision, updatedAt: note.updatedAt))
                }
                next.notes.removeAll { $0.folderID == folder.id }
            }
        }
        for index in next.collections.indices { next.collections[index].folderID = nil }
        next.folders = []
        next.formatVersion = 2
        return next
    }

    private func persist(_ state: LibraryState) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        var payloads = ["metadata:initialized": Data([1])]
        func encode<T: Encodable & Identifiable>(_ values: [T], kind: String) throws where T.ID == UUID {
            for value in values { payloads["\(kind):\(value.id.uuidString)"] = try encoder.encode(value) }
        }
        try encode(state.folders, kind: "folder")
        try encode(state.collections, kind: "collection")
        try encode(state.records, kind: "record")
        try encode(state.notes, kind: "note")
        try encode(state.alarms, kind: "alarm")
        try encode(state.events ?? [], kind: "event")
        for (key, value) in payloads {
            if let entity = entities[key] {
                if entity.payload != value { entity.payload = value }
            } else {
                let entity = BlueSchemaV1.StoredItem(key: key, payload: value)
                context.insert(entity)
                entities[key] = entity
            }
        }
        for key in Array(entities.keys) where payloads[key] == nil {
            if let entity = entities.removeValue(forKey: key) { context.delete(entity) }
        }
        do { try context.save() } catch {
            context.rollback()
            entities = Dictionary(
                uniqueKeysWithValues: try context.fetch(FetchDescriptor<BlueSchemaV1.StoredItem>()).map { ($0.key, $0) }
            )
            throw BlueError.saveFailed
        }
    }

    func update(_ mutation: (inout LibraryState) throws -> Void) throws {
        var next = state
        try mutation(&next)
        try persist(next)
        state = next
    }

    func saveEvent(_ event: CalendarEvent, expectedRevision: Int?) throws {
        try Validation.event(event)
        try update { state in
            var events = state.events ?? []
            var saved = event
            if let index = events.firstIndex(where: { $0.id == event.id }) {
                guard events[index].revision == expectedRevision else { throw BlueError.staleRevision }
                saved.revision = events[index].revision + 1
                events[index] = saved
            } else {
                guard expectedRevision == nil, saved.revision == 0 else { throw BlueError.staleRevision }
                events.append(saved)
            }
            state.events = events
        }
    }

    func confirmDeletion(_ pending: PendingDeletion) throws {
        try update { state in
            switch pending.kind {
            case "record":
                guard let revision = pending.revision,
                    state.records.first(where: { $0.id == pending.id })?.revision == revision
                else { throw BlueError.staleRevision }
                state.records.removeAll { $0.id == pending.id }
            case "note":
                guard let revision = pending.revision,
                    state.notes.first(where: { $0.id == pending.id })?.revision == revision
                else { throw BlueError.staleRevision }
                state.notes.removeAll { $0.id == pending.id }
            case "event":
                guard let revision = pending.revision,
                    state.events?.first(where: { $0.id == pending.id })?.revision == revision
                else { throw BlueError.staleRevision }
                state.events?.removeAll { $0.id == pending.id }
            case "collection":
                guard let collection = pending.collection, let revisions = pending.recordRevisions,
                    state.collections.first(where: { $0.id == pending.id }) == collection,
                    Dictionary(
                        uniqueKeysWithValues: state.records.filter { $0.collectionID == pending.id }.map {
                            ($0.id, $0.revision)
                        }) == revisions
                else { throw BlueError.staleRevision }
                state.records.removeAll { $0.collectionID == pending.id }
                state.collections.removeAll { $0.id == pending.id }
            default: throw BlueError.invalidValue
            }
        }
    }

    func record(_ id: UUID) -> Record? { state.records.first { $0.id == id } }
    func collection(_ id: UUID) -> Collection? { state.collections.first { $0.id == id } }
    func records(in id: UUID) -> [Record] { state.records.filter { $0.collectionID == id } }

    func saveRecord(_ record: Record, expectedRevision: Int?) throws {
        try Validation.title(record.title)
        guard let collection = collection(record.collectionID) else { throw BlueError.missing }
        for (id, value) in record.values {
            guard let field = collection.fields.first(where: { $0.id == id }) else { throw BlueError.invalidValue }
            try Validation.field(field, value: value)
        }
        try update { state in
            var saved = record
            saved.updatedAt = Date()
            if let index = state.records.firstIndex(where: { $0.id == record.id }) {
                guard expectedRevision == state.records[index].revision else { throw BlueError.staleRevision }
                saved.revision = state.records[index].revision + 1
                state.records[index] = saved
            } else {
                guard expectedRevision == nil else { throw BlueError.missing }
                state.records.append(saved)
            }
        }
    }

    func setValue(recordID: UUID, fieldID: String, value: FieldValue?, revision: Int) throws {
        guard var record = record(recordID) else { throw BlueError.missing }
        record.values[fieldID] = value
        if collection(record.collectionID)?.fields.first(where: { $0.id == fieldID })?.kind == .favorite {
            record.favorite = value?.flag ?? false
        }
        try saveRecord(record, expectedRevision: revision)
    }

    func createCollection(title: String, fields: [FieldDefinition], folderID: UUID? = nil) throws -> UUID {
        try Validation.title(title)
        let collection = Collection(folderID: folderID, title: .user(title), fields: fields)
        try Validation.collection(collection)
        try update { state in
            state.collections.append(collection)
        }
        return collection.id
    }

    func saveCollection(_ collection: Collection) throws {
        try Validation.collection(collection)
        try update { state in
            guard let index = state.collections.firstIndex(where: { $0.id == collection.id }) else {
                throw BlueError.missing
            }
            state.collections[index] = collection
            for index in state.records.indices where state.records[index].collectionID == collection.id {
                let old = state.records[index].values
                state.records[index].values = old.filter { key, value in
                    guard let field = collection.fields.first(where: { $0.id == key }) else { return false }
                    return (try? Validation.field(field, value: value)) != nil
                }
                state.records[index].revision += 1
            }
        }
    }

    func saveNote(_ note: Note, expectedRevision: Int?) throws {
        if note.title.key == nil {
            try Validation.title(note.title.english)
            try Validation.title(note.title.spanish)
        }
        guard note.markdown.english.count <= 20_000, note.markdown.spanish.count <= 20_000 else {
            throw BlueError.invalidValue
        }
        try update { state in
            var saved = note
            saved.updatedAt = Date()
            if let index = state.notes.firstIndex(where: { $0.id == note.id }) {
                guard expectedRevision == state.notes[index].revision else { throw BlueError.staleRevision }
                saved.revision += 1
                state.notes[index] = saved
            } else {
                guard expectedRevision == nil else { throw BlueError.missing }
                state.notes.append(saved)
            }
        }
    }

    func saveFolder(_ folder: Folder) throws {
        try Validation.folder(parentID: folder.parentID, in: state.folders)
        guard folder.parentID != folder.id else { throw BlueError.folderDepth }
        if folder.parentID != nil && state.folders.contains(where: { $0.parentID == folder.id }) {
            throw BlueError.folderDepth
        }
        try update { state in
            if let index = state.folders.firstIndex(where: { $0.id == folder.id }) {
                state.folders[index] = folder
            } else {
                state.folders.append(folder)
            }
        }
    }

    func deleteFolder(_ id: UUID) throws {
        guard state.folders.contains(where: { $0.id == id }) else { throw BlueError.missing }
        let folderIDs = Set([id] + state.folders.filter { $0.parentID == id }.map(\.id))
        let collectionIDs = Set(state.collections.filter { $0.folderID.map(folderIDs.contains) ?? false }.map(\.id))
        try update { state in
            state.records.removeAll { collectionIDs.contains($0.collectionID) }
            state.collections.removeAll { collectionIDs.contains($0.id) }
            state.notes.removeAll { $0.folderID.map(folderIDs.contains) ?? false }
            state.folders.removeAll { folderIDs.contains($0.id) }
        }
    }

    func export() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(state)
    }

    /// Add collections and notes from a version 2 export in one save. Keep local edits and alarm state.
    func importBackup(_ data: Data) throws {
        guard data.count <= 10_000_000 else { throw BlueError.invalidValue }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let backup = try decoder.decode(LibraryState.self, from: data)
        guard backup.formatVersion == 2, backup.folders.isEmpty,
            Set(backup.collections.map(\.id)).count == backup.collections.count,
            Set(backup.records.map(\.id)).count == backup.records.count,
            Set(backup.notes.map(\.id)).count == backup.notes.count
        else { throw BlueError.invalidValue }

        let currentCollections = Set(state.collections.map(\.id))
        let currentRecords = Set(state.records.map(\.id))
        let currentNotes = Set(state.notes.map(\.id))
        let collections = backup.collections.filter { !currentCollections.contains($0.id) }
        let byID = Dictionary(uniqueKeysWithValues: collections.map { ($0.id, $0) })
        let records = backup.records.filter { byID[$0.collectionID] != nil && !currentRecords.contains($0.id) }
        let notes = backup.notes.filter { !currentNotes.contains($0.id) }
        for collection in collections {
            guard collection.folderID == nil else { throw BlueError.invalidValue }
            try Validation.collection(collection)
        }
        for record in records {
            try Validation.title(record.title)
            for (id, value) in record.values {
                guard let field = byID[record.collectionID]?.fields.first(where: { $0.id == id }) else {
                    throw BlueError.invalidValue
                }
                try Validation.field(field, value: value)
            }
        }
        for note in notes {
            guard note.folderID == nil, note.markdown.english.count <= 20_000, note.markdown.spanish.count <= 20_000
            else { throw BlueError.invalidValue }
            if note.title.key == nil {
                try Validation.title(note.title.english)
                try Validation.title(note.title.spanish)
            }
        }
        try update { state in
            state.collections += collections
            state.records += records
            state.notes += notes
        }
    }
}
