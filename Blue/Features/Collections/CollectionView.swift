import SwiftUI

struct RecordRow: View {
    let record: Record
    let collection: Collection
    var directActions = true
    var showsFavoriteIndicator = true
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(record.title).font(.title3.weight(.medium)).frame(
                maxWidth: .infinity, minHeight: 44, alignment: .leading)
            if showsFavoriteIndicator {
                RecordIndicators(record: record, collection: collection, interactive: directActions)
            }
        }.contentShape(Rectangle())
    }
}

struct CollectionView: View {
    let collectionID: UUID
    @Environment(LibraryStore.self) private var store
    @Environment(Localizer.self) private var l
    @Environment(NavigationState.self) private var navigation
    @State private var showFilters = false
    @State private var confirmDelete = false
    @State private var title = ""
    @State private var error: String?
    private var query: CollectionQuery { navigation.queries[collectionID] ?? CollectionQuery() }
    private var queryBinding: Binding<CollectionQuery> {
        Binding(get: { query }, set: { navigation.queries[collectionID] = $0 })
    }
    var body: some View {
        if let collection = store.collection(collectionID) {
            VStack(spacing: 0) {
                FilterControls(collection: collection, query: queryBinding, compact: true).padding(.horizontal, 24)
                List {
                    ForEach(
                        query.apply(to: store.records(in: collectionID), fields: collection.fields, locale: l.locale)
                    ) { record in
                        VStack(alignment: .leading, spacing: 0) {
                            Button {
                                navigation.path.append(.record(record.id))
                            } label: {
                                Text(record.title).font(.title3.weight(.medium)).frame(
                                    maxWidth: .infinity, minHeight: 44, alignment: .leading
                                ).contentShape(Rectangle())
                            }.buttonStyle(.plain).accessibilityIdentifier("row-\(record.title)")
                            RecordIndicators(record: record, collection: collection, interactive: true)
                        }.padding(.vertical, 6).listRowBackground(Color.clear)
                    }
                    ErrorLine(key: error ?? navigation.noticeKey).listRowSeparator(.hidden)
                }.listStyle(.plain).scrollDismissesKeyboard(.interactively)
            }.background(Color(uiColor: .systemBackground)).navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .principal) {
                        TextField(
                            l("title"),
                            text: Binding(
                                get: { title },
                                set: { value in
                                    title = value
                                    guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                                    var updated = collection
                                    updated.title = .user(value)
                                    do {
                                        try store.saveCollection(updated)
                                        error = nil
                                    } catch { self.error = (error as? BlueError ?? .saveFailed).key }
                                })
                        ).font(.title2.weight(.semibold)).accessibilityIdentifier("collectionTitle")
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        QuietButton(key: "filters.title", symbol: "line.3.horizontal.decrease") { showFilters = true }
                            .accessibilityIdentifier("openFilters")
                    }.sharedBackgroundVisibility(.hidden)
                    ToolbarItem(placement: .topBarTrailing) {
                        NavigationLink(value: Route.newRecord(collectionID)) {
                            Image(systemName: "plus").frame(width: 44, height: 44)
                        }
                        .buttonStyle(.plain).frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())
                        .accessibilityLabel(l("record.new")).accessibilityIdentifier("newRecord")
                    }.sharedBackgroundVisibility(.hidden)
                    ToolbarItem(placement: .bottomBar) { EmptyView() }
                }
                .blueSheet(isPresented: $showFilters, title: l("filters.title")) {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 24) {
                            FilterControls(collection: collection, query: queryBinding)
                            TextField(l("collection.search"), text: queryBinding.search).frame(minHeight: 44)
                            Menu(l("sort.titleLabel")) {
                                Button(l("title")) {
                                    navigation.queries[collectionID, default: CollectionQuery()].sortField = "title"
                                }
                                ForEach(collection.fields) { field in
                                    Button(l.text(field.label)) {
                                        navigation.queries[collectionID, default: CollectionQuery()].sortField =
                                            field.id
                                    }
                                }
                                Button(l(query.ascending ? "sort.descending" : "sort.ascending")) {
                                    navigation.queries[collectionID, default: CollectionQuery()].ascending.toggle()
                                }
                            }.frame(minHeight: 44)
                            Button(l("delete"), role: .destructive) { confirmDelete = true }.frame(minHeight: 44)
                        }.padding(.horizontal, 24)
                    }
                    .confirmationDialog(
                        l("collection.confirmDelete"), isPresented: $confirmDelete, titleVisibility: .visible
                    ) {
                        Button(l("delete"), role: .destructive) {
                            do {
                                try store.confirmDeletion(
                                    PendingDeletion(
                                        kind: "collection", id: collectionID, collection: collection,
                                        recordRevisions: Dictionary(
                                            uniqueKeysWithValues: store.records(in: collectionID).map {
                                                ($0.id, $0.revision)
                                            })))
                                showFilters = false
                                navigation.path = []
                            } catch { self.error = (error as? BlueError ?? .saveFailed).key }
                        }
                    }
                }
                .onAppear { title = l.text(collection.title) }
                .onChange(of: l.language) { _, _ in title = l.text(collection.title) }
        }
    }
}

struct FilterControls: View {
    let collection: Collection
    @Binding var query: CollectionQuery
    var compact = false
    @Environment(Localizer.self) private var l
    var body: some View {
        PropertyFlow {
            ForEach([FieldDefinition.favoriteIndicator] + collection.fields.filter { $0.kind != .favorite }) { field in
                let active = query.filters.first { $0.fieldID == field.id }
                if !compact || field.kind.isBoolean || field.kind == .status || active != nil {
                    PropertyControl(field: field, value: value(active, field: field), filter: true) { value in
                        query.filters.removeAll { $0.fieldID == field.id }
                        if let value {
                            switch value {
                            case .flag(let on):
                                if on { query.filters.append(RecordFilter(fieldID: field.id, flag: true)) }
                            case .number(let number):
                                query.filters.append(RecordFilter(fieldID: field.id, minimum: number))
                            case .date(let date): query.filters.append(RecordFilter(fieldID: field.id, after: date))
                            default: query.filters.append(RecordFilter(fieldID: field.id, text: value.text ?? ""))
                            }
                        }
                    }.accessibilityIdentifier("quickFilter-\(field.id)")
                }
            }
            if !query.filters.isEmpty {
                Button {
                    query.filters = []
                } label: {
                    Image(systemName: "line.3.horizontal.decrease.circle").frame(width: 44, height: 44)
                }
                .accessibilityLabel(l("filters.clearAll"))
            }
        }
    }
    private func value(_ filter: RecordFilter?, field: FieldDefinition) -> FieldValue? {
        guard let filter else { return nil }
        if let flag = filter.flag { return .flag(flag) }
        if let number = filter.minimum { return .number(number) }
        if let date = filter.after { return .date(date) }
        return field.kind == .status ? .option(filter.text) : .text(filter.text)
    }
}
