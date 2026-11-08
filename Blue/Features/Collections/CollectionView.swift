import SwiftUI

struct RecordRow: View {
    let record: Record
    let collection: Collection
    var directActions = true
    var showsFavoriteIndicator = true
    @Environment(Localizer.self) private var l
    @Environment(LibraryStore.self) private var store
    @State private var error: String?
    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text(record.title).font(.body.weight(.medium)).foregroundStyle(.primary)
                let secondary = collection.fields.filter {
                    $0.showInRow && $0.kind != .rating && !$0.kind.isBoolean && record.values[$0.id] != nil
                }
                if !secondary.isEmpty {
                    Text(secondary.prefix(2).map { l.value(record.values[$0.id], field: $0) }.joined(separator: " · "))
                        .font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
                } else if !l.text(record.markdown).isEmpty {
                    Text(l.text(record.markdown)).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                }
                ErrorLine(key: error)
            }
            Spacer(minLength: 0)
            if let field = collection.fields.first(where: { $0.kind == .rating && $0.showInRow }),
                let rating = record.values[field.id]?.number
            {
                Text(l.number(rating)).font(.system(.title3, design: .rounded).weight(.medium)).monospacedDigit()
                    .accessibilityLabel(l.format("rating.value", l.number(rating)))
            }
            if let field = collection.fields.first(where: { $0.showInRow && [.favorite, .like].contains($0.kind) }) {
                let selected = record.values[field.id]?.flag == true
                if directActions {
                    Button {
                        do {
                            try store.setValue(
                                recordID: record.id, fieldID: field.id, value: .flag(!selected),
                                revision: record.revision)
                        } catch { self.error = (error as? BlueError ?? .saveFailed).key }
                    } label: {
                        Image(
                            systemName: field.kind == .like
                                ? (selected ? "heart.fill" : "heart") : (selected ? "star.fill" : "star")
                        ).frame(width: 44, height: 44)
                    }
                    .buttonStyle(.borderless).accessibilityLabel(l.text(field.label)).accessibilityValue(
                        l(selected ? "yes" : "no"))
                } else if selected && showsFavoriteIndicator {
                    Image(systemName: field.kind == .like ? "heart.fill" : "star.fill").font(.subheadline)
                }
            }
        }.padding(.vertical, 9).contentShape(Rectangle())
    }
}

struct CollectionView: View {
    let collectionID: UUID
    @Environment(LibraryStore.self) private var store
    @Environment(Localizer.self) private var l
    @Environment(NavigationState.self) private var navigation
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var textSize
    @State private var showFilters = false
    @State private var showSettings = false
    @State private var largeResults: [Record] = []
    private struct QuerySnapshot: Equatable, Sendable {
        var records: [Record]
        var fields: [FieldDefinition]
        var query: CollectionQuery
        var locale: Locale
    }
    private var query: CollectionQuery { navigation.queries[collectionID] ?? CollectionQuery() }
    private var queryBinding: Binding<CollectionQuery> {
        Binding(get: { query }, set: { navigation.queries[collectionID] = $0 })
    }
    var body: some View {
        if let collection = store.collection(collectionID) {
            ScrollViewReader { proxy in
                let snapshot = QuerySnapshot(
                    records: store.records(in: collectionID), fields: collection.fields,
                    query: query, locale: l.locale)
                let records =
                    snapshot.records.count > 500
                    ? largeResults : query.apply(to: snapshot.records, fields: collection.fields, locale: l.locale)
                List {
                    if let notice = navigation.noticeKey {
                        HStack {
                            Text(l(notice)).font(.caption).foregroundStyle(.secondary)
                            Spacer()
                            QuietButton(key: "close", symbol: "xmark") { navigation.noticeKey = nil }
                        }
                    }
                    if !query.filters.isEmpty { activeFilters(collection).listRowSeparator(.hidden) }
                    ForEach(records) { record in
                        HStack {
                            Button {
                                navigation.path.append(.record(record.id))
                            } label: {
                                RecordRow(
                                    record: record, collection: collection, directActions: false,
                                    showsFavoriteIndicator: false)
                            }
                            .buttonStyle(.plain)
                            if let field = collection.fields.first(where: {
                                $0.showInRow && [.like, .favorite].contains($0.kind)
                            }) {
                                favoriteButton(record, field)
                            }
                        }
                        .id(record.id).accessibilityIdentifier("row-\(record.title)")
                        .listRowBackground(
                            navigation.highlightedRecord == record.id ? Color.primary.opacity(0.07) : Color.clear)
                    }
                    if records.isEmpty {
                        ContentUnavailableView(
                            l(query.filters.isEmpty ? "collection.empty" : "filters.noResults"),
                            systemImage: "list.bullet", description: Text(l("collection.emptyHint"))
                        )
                        .listRowSeparator(.hidden)
                    }
                }
                .listStyle(.plain)
                .task(id: snapshot) {
                    guard snapshot.records.count > 500 else { return }
                    let worker = Task.detached(priority: .userInitiated) {
                        snapshot.query.apply(to: snapshot.records, fields: snapshot.fields, locale: snapshot.locale)
                    }
                    let results = await withTaskCancellationHandler {
                        await worker.value
                    } onCancel: {
                        worker.cancel()
                    }
                    guard !Task.isCancelled else { return }
                    largeResults = results
                }
                .searchable(text: queryBinding.search, prompt: l("collection.search"))
                .modifier(KeyboardDismissToolbar()).navigationTitle(l.text(collection.title))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            Button(l("filters.title"), systemImage: "line.3.horizontal.decrease") { showFilters = true }
                            Button(l("settings.title"), systemImage: "slider.horizontal.3") { showSettings = true }
                                .accessibilityIdentifier("settingsButton")
                            Section(l("sort.titleLabel")) {
                                sortButton("title", label: l("title"))
                                ForEach(collection.fields) { field in sortButton(field.id, label: l.text(field.label)) }
                                Button(l(query.ascending ? "sort.descending" : "sort.ascending")) {
                                    var next = query
                                    next.ascending.toggle()
                                    navigation.queries[collectionID] = next
                                }
                            }
                            NavigationLink(l("collection.properties"), value: Route.collectionSettings(collectionID))
                        } label: {
                            Image(
                                systemName: query.filters.isEmpty
                                    ? "line.3.horizontal.decrease" : "line.3.horizontal.decrease.circle.fill"
                            ).frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())
                        }
                        .accessibilityLabel(l("collection.options")).accessibilityIdentifier("collectionOptions")
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        NavigationLink(value: Route.newRecord(collectionID)) {
                            Image(systemName: "plus").frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())
                        }
                        .accessibilityLabel(l("record.new")).accessibilityIdentifier("newRecord")
                    }
                }
                .sheet(isPresented: $showSettings) { NavigationStack { SettingsView() } }
                .sheet(isPresented: $showFilters) {
                    NavigationStack { FilterEditor(collection: collection, query: queryBinding) }
                        .presentationDetents(textSize.isAccessibilitySize ? [.large] : [.medium, .large])
                }
                .animation(reduceMotion ? nil : .snappy(duration: 0.25), value: records.map(\.id))
                .task(id: navigation.highlightedRecord) {
                    guard let id = navigation.highlightedRecord else { return }
                    try? await Task.sleep(for: .milliseconds(200))
                    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.25)) {
                        proxy.scrollTo(id, anchor: .center)
                    }
                    try? await Task.sleep(for: .seconds(2))
                    if navigation.highlightedRecord == id { navigation.highlightedRecord = nil }
                }
            }
        } else {
            ContentUnavailableView(l("error.missing"), systemImage: "list.bullet")
        }
    }
    private func sortButton(_ id: String, label: String) -> some View {
        Button {
            var next = query
            next.sortField = id
            navigation.queries[collectionID] = next
        } label: {
            HStack {
                Text(label)
                if query.sortField == id { Image(systemName: "checkmark") }
            }
        }
    }
    private func favoriteButton(_ record: Record, _ field: FieldDefinition) -> some View {
        let selected = record.values[field.id]?.flag == true
        return Button {
            do {
                try store.setValue(
                    recordID: record.id, fieldID: field.id, value: .flag(!selected), revision: record.revision)
            } catch { navigation.noticeKey = (error as? BlueError ?? .saveFailed).key }
        } label: {
            Image(
                systemName: field.kind == .like
                    ? (selected ? "heart.fill" : "heart") : (selected ? "star.fill" : "star")
            ).frame(width: 44, height: 44)
        }.buttonStyle(.borderless).accessibilityLabel(l.text(field.label)).accessibilityValue(
            l(selected ? "yes" : "no"))
    }
    @ViewBuilder private func activeFilters(_ collection: Collection) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                ForEach(query.filters.prefix(2)) { filter in filterChip(filter, collection) }
                overflowFilters(collection, skip: 2)
                Spacer(minLength: 0)
            }
            if query.filters.count > 1 {
                Button(l("filters.clearAll")) {
                    var next = query
                    next.filters = []
                    navigation.queries[collectionID] = next
                }.font(.caption).padding(.vertical, 6)
            }
        }
    }
    private func filterChip(_ filter: RecordFilter, _ collection: Collection) -> some View {
        let label = collection.fields.first { $0.id == filter.fieldID }.map { l.text($0.label) } ?? filter.fieldID
        return Button {
            removeFilter(filter.id)
        } label: {
            HStack(spacing: 6) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(label).lineLimit(1)
                    Text(filterValue(filter, collection)).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
                }
                Image(systemName: "xmark").font(.caption2)
            }
            .font(.caption).padding(.horizontal, 12).frame(minHeight: 44).background(
                Color.primary.opacity(0.06), in: Capsule()
            )
            .frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
        }.buttonStyle(.borderless).accessibilityLabel(l.format("filters.remove", label)).accessibilityValue(
            filterValue(filter, collection)
        ).accessibilityIdentifier(
            "removeFilter-\(filter.id)")
    }
    private func filterValue(_ filter: RecordFilter, _ collection: Collection) -> String {
        if let field = collection.fields.first(where: { $0.id == filter.fieldID }), field.kind == .status {
            return l.value(.option(filter.text), field: field)
        }
        if let selected = filter.flag { return l(selected ? "yes" : "no") }
        if let min = filter.minimum, let max = filter.maximum { return "\(l.number(min))–\(l.number(max))" }
        if let min = filter.minimum { return "≥ \(l.number(min))" }
        if let max = filter.maximum { return "≤ \(l.number(max))" }
        if let after = filter.after { return "≥ \(l.date(after))" }
        if let before = filter.before { return "≤ \(l.date(before))" }
        return filter.text
    }
    @ViewBuilder private func overflowFilters(_ collection: Collection, skip: Int) -> some View {
        if query.filters.count > skip {
            Menu {
                ForEach(Array(query.filters.dropFirst(skip))) { filter in
                    let name =
                        collection.fields.first { $0.id == filter.fieldID }.map { l.text($0.label) } ?? filter.fieldID
                    Button(
                        l.format("filters.remove", "\(name) · \(filterValue(filter, collection))"), systemImage: "xmark"
                    ) { removeFilter(filter.id) }
                }
            } label: {
                Text(l.format("filters.more", query.filters.count - skip)).font(.caption).frame(minHeight: 44)
            }
        }
    }
    private func removeFilter(_ id: String) {
        var next = query
        next.filters.removeAll { $0.id == id }
        navigation.queries[collectionID] = next
    }
}

struct FilterEditor: View {
    let collection: Collection
    @Binding var query: CollectionQuery
    @Environment(Localizer.self) private var l
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        Form {
            ForEach(collection.fields) { field in
                Section(l.text(field.label)) {
                    let active = query.filters.first { $0.fieldID == field.id }
                    switch field.kind {
                    case .status:
                        ForEach(field.options) { option in
                            Button {
                                if active?.text == option.id {
                                    remove(field.id)
                                } else {
                                    set(RecordFilter(fieldID: field.id, text: option.id))
                                }
                            } label: {
                                HStack {
                                    Text(l.text(option.label))
                                    Spacer()
                                    if active?.text == option.id { Image(systemName: "checkmark") }
                                }
                            }
                            .accessibilityIdentifier("filterOption-\(option.id)")
                        }
                    case .checkbox, .like, .favorite:
                        Toggle(
                            l("filters.onlySelected"),
                            isOn: Binding(
                                get: { active?.flag == true },
                                set: {
                                    if $0 { set(RecordFilter(fieldID: field.id, flag: true)) } else { remove(field.id) }
                                }))
                    case .rating, .number:
                        Toggle(
                            l("filters.useRange"),
                            isOn: Binding(
                                get: { active != nil },
                                set: {
                                    if $0 { set(RecordFilter(fieldID: field.id, minimum: 0)) } else { remove(field.id) }
                                }))
                        if active != nil {
                            if field.kind == .rating {
                                Slider(
                                    value: Binding(
                                        get: { active?.minimum ?? 0 },
                                        set: {
                                            set(RecordFilter(fieldID: field.id, minimum: $0, maximum: active?.maximum))
                                        }), in: 0...10, step: 0.5
                                ) { Text(l("filters.minimum")) }
                                Text(l.format("filters.atLeast", l.number(active?.minimum ?? 0))).font(.caption)
                            } else {
                                TextField(
                                    l("filters.minimum"),
                                    value: Binding(
                                        get: { active?.minimum },
                                        set: {
                                            set(RecordFilter(fieldID: field.id, minimum: $0, maximum: active?.maximum))
                                        }), format: .number.locale(l.locale)
                                ).keyboardType(.decimalPad)
                            }
                            TextField(
                                l("filters.maximum"),
                                value: Binding(
                                    get: { active?.maximum },
                                    set: { set(RecordFilter(fieldID: field.id, minimum: active?.minimum, maximum: $0)) }
                                ), format: .number.locale(l.locale)
                            ).keyboardType(.decimalPad)
                        }
                    case .date:
                        Toggle(
                            l("filters.useDate"),
                            isOn: Binding(
                                get: { active != nil },
                                set: {
                                    if $0 {
                                        set(
                                            RecordFilter(
                                                fieldID: field.id, after: Calendar.current.startOfDay(for: Date())))
                                    } else {
                                        remove(field.id)
                                    }
                                }))
                        if active != nil {
                            DatePicker(
                                l("filters.after"),
                                selection: Binding(
                                    get: { active?.after ?? Date() },
                                    set: { set(RecordFilter(fieldID: field.id, after: $0)) }),
                                displayedComponents: .date)
                        }
                    case .text, .tags:
                        TextField(
                            l("filters.contains"),
                            text: Binding(
                                get: { active?.text ?? "" },
                                set: {
                                    if $0.isEmpty {
                                        remove(field.id)
                                    } else {
                                        set(RecordFilter(fieldID: field.id, text: $0))
                                    }
                                }))
                    }
                }
            }
        }
        .modifier(KeyboardDismissToolbar()).navigationTitle(l("filters.title")).navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                QuietButton(key: "close", symbol: "xmark") { dismiss() }.accessibilityIdentifier("filtersClose")
            }
        }
    }
    private func remove(_ id: String) { query.filters.removeAll { $0.fieldID == id } }
    private func set(_ filter: RecordFilter) {
        remove(filter.id)
        query.filters.append(filter)
    }
}
