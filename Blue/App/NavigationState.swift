import Foundation
import Observation

enum Route: Hashable {
    case collection(UUID)
    case record(UUID)
    case note(UUID)
    case newRecord(UUID)
    case newNote, newCollection
    case collectionSettings(UUID)
}

@MainActor
@Observable
final class NavigationState {
    var tab = 0
    var path: [Route] = []
    var selectedDate = Date()
    var highlightedRecord: UUID?
    var highlightedAlarm: UUID?
    var queries: [UUID: CollectionQuery] = [:]
    var noticeKey: String?
    var assistantFocused = false
    var assistantExpanded = false
    func jump(to record: Record, store: LibraryStore, locale: Locale) {
        tab = 0
        var query = queries[record.collectionID] ?? CollectionQuery()
        let fields = store.collection(record.collectionID)?.fields ?? []
        if query.apply(to: [record], fields: fields, locale: locale).isEmpty {
            query.filters = query.filters.filter { filter in
                CollectionQuery(filters: [filter]).apply(to: [record], fields: fields, locale: locale).count == 1
            }
            query.search = ""
            queries[record.collectionID] = query
            noticeKey = "filters.adjusted"
        }
        path = [.collection(record.collectionID)]
        highlightedRecord = record.id
    }
    func jump(to alarm: SavedAlarm) {
        tab = 1
        selectedDate = alarm.date
        highlightedAlarm = alarm.id
    }
}
