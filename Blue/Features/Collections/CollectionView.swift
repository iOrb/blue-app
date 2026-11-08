import SwiftUI

struct RecordRow: View {
    let record: Record
    let collection: Collection
    var directActions = true
    var showsFavoriteIndicator = true
    @Environment(Localizer.self) private var l
    @Environment(\.dynamicTypeSize) private var textSize
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(record.title).font(.body.weight(.medium)).foregroundStyle(.primary)
                Spacer(minLength: 8)

            }
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: textSize.isAccessibilitySize ? 300 : 130), alignment: .leading)],
                alignment: .leading, spacing: 6
            ) {
                ForEach(collection.fields.filter { !$0.kind.isBoolean && record.values[$0.id] != nil }) { field in
                    let value = record.values[field.id]
                    Label {
                        Text(l.text(field.label) + ": " + l.value(value, field: field))
                    } icon: {
                        Image(
                            systemName: field.kind.isBoolean && value?.flag == true
                                ? field.kind.symbol + ".fill" : field.kind.symbol)
                    }.font(.caption).foregroundStyle(.secondary).lineLimit(textSize.isAccessibilitySize ? nil : 2)
                        .frame(
                            maxWidth: .infinity, alignment: .leading)
                }
            }
            if showsFavoriteIndicator { RecordIndicators(record: record, collection: collection) }
            if !l.text(record.markdown).isEmpty {
                Label(l.text(record.markdown), systemImage: "text.alignleft")
                    .font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
            }
        }.padding(.vertical, 9).frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
            .accessibilityElement(children: .combine)
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
                VStack(spacing: 0) {
                    controls(collection).padding(.horizontal, 16).padding(.vertical, 8).background(.background)
                    List {
                        if let notice = navigation.noticeKey {
                            HStack {
                                Text(l(notice)).font(.caption).foregroundStyle(.secondary)
                                Spacer()
                                QuietButton(key: "close", symbol: "xmark") { navigation.noticeKey = nil }
                            }
                        }
                        if query.filters.contains(where: { $0.flag == nil }) {
                            activeFilters(collection).listRowSeparator(.hidden)
                        }
                        ForEach(records) { record in
                            VStack(alignment: .leading, spacing: 0) {
                                Button {
                                    navigation.path.append(.record(record.id))
                                } label: {
                                    RecordRow(
                                        record: record, collection: collection, directActions: false,
                                        showsFavoriteIndicator: false)
                                }
                                .buttonStyle(.plain).frame(minHeight: 44).accessibilityIdentifier("row-\(record.title)")
                                RecordIndicators(record: record, collection: collection, interactive: true).padding(
                                    .bottom, 9)

                            }
                            .id(record.id)
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
                }
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
                        NavigationLink(value: Route.newRecord(collectionID)) {
                            Image(systemName: "plus").frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())
                        }
                        .accessibilityLabel(l("record.new")).accessibilityIdentifier("newRecord")
                    }.sharedBackgroundVisibility(.hidden)
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
    private func controls(_ collection: Collection) -> some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 44, maximum: 44), spacing: 8)], alignment: .leading,
            spacing: 8
        ) {
            ForEach(
                [FieldDefinition.favoriteIndicator]
                    + collection.fields.filter { $0.kind.isBoolean && $0.kind != .favorite }
            ) { field in
                IndicatorControl(
                    field: field,
                    selected: query.filters.contains { $0.fieldID == field.id && $0.flag == true }
                ) {
                    var updated = query
                    if updated.filters.contains(where: { $0.fieldID == field.id }) {
                        updated.filters.removeAll { $0.fieldID == field.id }
                    } else {
                        updated.filters.append(RecordFilter(fieldID: field.id, flag: true))
                    }
                    navigation.queries[collectionID] = updated
                }.accessibilityIdentifier("quickFilter-\(field.id)")
            }
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
                Image(systemName: "ellipsis").font(.system(size: 20, weight: .medium))
                    .frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(l("collection.options")).accessibilityIdentifier("collectionOptions")
            QuietButton(key: "filters.title", symbol: "line.3.horizontal.decrease") { showFilters = true }
                .accessibilityIdentifier("openFilters")
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
    @ViewBuilder private func activeFilters(_ collection: Collection) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                ForEach(query.filters.filter { $0.flag == nil }.prefix(2)) { filter in filterChip(filter, collection) }
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
                ForEach(Array(query.filters.filter { $0.flag == nil }.dropFirst(skip))) { filter in
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
            Section {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 44, maximum: 44), spacing: 8)], alignment: .leading,
                    spacing: 8
                ) {
                    ForEach(
                        [FieldDefinition.favoriteIndicator]
                            + collection.fields.filter { $0.kind.isBoolean && $0.kind != .favorite }
                    ) { field in
                        IndicatorControl(
                            field: field, selected: query.filters.contains { $0.fieldID == field.id && $0.flag == true }
                        ) {
                            if query.filters.contains(where: { $0.fieldID == field.id }) {
                                remove(field.id)
                            } else {
                                set(RecordFilter(fieldID: field.id, flag: true))
                            }
                        }
                    }
                }
            }
            ForEach(collection.fields.filter { !$0.kind.isBoolean }) { field in
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
                        QuickChoice(
                            title: l.text(field.label), symbol: field.kind.symbol,
                            selected: active?.flag == true
                        ) {
                            if active?.flag == true {
                                remove(field.id)
                            } else {
                                set(RecordFilter(fieldID: field.id, flag: true))
                            }
                        }
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
