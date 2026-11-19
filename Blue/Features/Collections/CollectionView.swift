import SwiftUI

struct RecordRow: View {
    let record: Record
    let collection: Collection
    var directActions = false
    var showsFavoriteIndicator = true
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(record.title).font(.body.weight(.medium)).frame(
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
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var confirmDelete = false
    @State private var showFilters = false
    @State private var pendingDeletion: Deletion?
    @State private var selectedIDs: Set<UUID> = []
    @State private var title = ""
    @State private var error: String?
    private enum Deletion {
        case collection(PendingDeletion)
        case records([UUID: Int])
    }

    private var isSelecting: Bool { navigation.deletingRecordsIn == collectionID }
    private var query: CollectionQuery { navigation.queries[collectionID] ?? CollectionQuery() }

    var body: some View {
        if let collection = store.collection(collectionID) {
            let activeRecords = store.records(in: collectionID)
            let visibleRecords = query.apply(to: activeRecords, fields: collection.fields, locale: l.locale)
            VStack(spacing: 0) {
                header(collection)
                List {
                    VStack(spacing: 6) {
                        if collection.artwork != nil {
                            Button {
                                navigation.collectionArtworkID = collection.id
                            } label: {
                                CollectionArtworkView(artwork: collection.artwork, size: 156)
                            }.buttonStyle(BlueRowPress())
                                .accessibilityLabel(l("artwork.title"))
                                .accessibilityIdentifier("collectionCover")
                                .disabled(isSelecting)
                                .padding(.bottom, 12)
                        }
                        Group {
                            if isSelecting {
                                Text(title)
                            } else {
                                TextField(
                                    l("title"),
                                    text: Binding(
                                        get: { title },
                                        set: { value in
                                            title = value
                                            guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                                                return
                                            }
                                            var updated = collection
                                            updated.title = .user(value)
                                            do {
                                                try store.saveCollection(updated)
                                                error = nil
                                            } catch { self.error = (error as? BlueError ?? .saveFailed).key }
                                        })
                                ).accessibilityIdentifier("collectionTitle")
                            }
                        }.font(.largeTitle.weight(.bold)).multilineTextAlignment(.center)
                        Text(l.format("collection.itemCount", activeRecords.count)).font(
                            .subheadline.weight(.medium)
                        ).foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity).padding(.vertical, 8).blueListRow()

                    HStack(spacing: 10) {
                        QuietButton(key: "filters.title", symbol: "line.3.horizontal.decrease") {
                            showFilters = true
                        }.accessibilityIdentifier("collectionFilters")
                        Spacer()
                        if !isSelecting {
                            QuietButton(key: "record.new", symbol: "plus") {
                                navigation.open(.newRecord(collectionID))
                            }.accessibilityIdentifier("newRecord")
                        }
                    }.blueListRow()
                    ForEach(visibleRecords) { record in
                        if isSelecting {
                            selectionRow(record)
                        } else {
                            recordRow(record, collection: collection)
                        }
                    }
                    if let error = error ?? navigation.noticeKey { ErrorLine(key: error).blueListRow() }
                }.listStyle(.plain).scrollContentBackground(.hidden)
                    .scrollDismissesKeyboard(.interactively)
                    .background(Color(uiColor: .systemBackground)).navigationBarTitleDisplayMode(.inline)
                    .navigationBarBackButtonHidden(true)
                    .toolbar(.hidden, for: .navigationBar)
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if isSelecting { selectionBar(activeRecords.filter { selectedIDs.contains($0.id) }) }
            }
            .blueSheet(isPresented: $showFilters, title: l("filters.title"), initialHeight: 340) {
                filterOptions(collection)
            }
            .blueConfirmation(isPresented: $confirmDelete, title: deletionTitle, confirm: completeDeletion)
            .onAppear { title = l.text(collection.title) }
            .onChange(of: l.language) { _, _ in title = l.text(collection.title) }
            .onChange(of: collection.title) { _, value in title = l.text(value) }
        }
    }

    private func header(_ collection: Collection) -> some View {
        HStack {
            if !isSelecting {
                QuietButton(key: "back", symbol: "chevron.left") { navigation.path.removeLast() }
                    .glassEffect(.regular.interactive(), in: Circle())
                    .accessibilityIdentifier("collectionBack")
            }
            Spacer()
            if isSelecting {
                QuietButton(key: "cancel", symbol: "xmark", action: endSelection)
                    .glassEffect(.regular.interactive(), in: Circle())
                    .opacity(confirmDelete ? 0 : 1)
                    .accessibilityHidden(confirmDelete)
                    .accessibilityIdentifier("cancelRecordSelection")
            } else {
                Menu {
                    CollectionMenuActions(
                        collection: collection, store: store, l: l, error: $error,
                        delete: {
                            pendingDeletion = .collection($0)
                            confirmDelete = true
                        },
                        select: { beginSelection() })
                } label: {
                    Image(systemName: "ellipsis").frame(width: 44, height: 44).contentShape(Rectangle())
                }.buttonStyle(BlueRowPress(shape: AnyShape(Circle())))
                    .glassEffect(.regular.interactive(), in: Circle())
                    .accessibilityLabel(l("options")).accessibilityIdentifier("collectionOptions")
            }
        }.padding(.horizontal, 18)
    }

    private func selectionRow(_ record: Record) -> some View {
        let selected = selectedIDs.contains(record.id)
        return Button {
            if selected { selectedIDs.remove(record.id) } else { selectedIDs.insert(record.id) }
        } label: {
            HStack(spacing: 14) {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.title3.weight(.medium))
                    .foregroundStyle(selected ? Color.blue : Color.secondary)
                    .accessibilityHidden(true)
                Text(record.title).font(.body.weight(.medium))
                Spacer(minLength: 0)
            }.padding(.horizontal, 24).frame(minHeight: 52).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("select-record-\(record.title)")
        .blueListRow(fullWidth: true)
    }

    private func selectionBar(_ records: [Record]) -> some View {
        HStack {
            QuietButton(key: "delete", symbol: "trash") {
                pendingDeletion = .records(Dictionary(uniqueKeysWithValues: records.map { ($0.id, $0.revision) }))
                confirmDelete = true
            }
            .foregroundStyle(.red)
            .disabled(records.isEmpty)
            .accessibilityIdentifier("deleteSelectedRecords")
            Spacer()
            Text(l.format(records.count == 1 ? "delete.selectedOne" : "delete.selectedCount", records.count))
                .font(.subheadline.weight(.semibold)).monospacedDigit()
                .accessibilityIdentifier("selectedRecordCount")
        }
        .padding(.horizontal, 14).frame(minHeight: 56)
        .glassEffect(.regular, in: Capsule())
        .padding(.horizontal, 16).padding(.bottom, 6)
    }

    private var deletionTitle: String {
        if case .records(let revisions) = pendingDeletion {
            return revisions.count == 1 ? l("delete.confirm") : l.format("delete.recordsConfirm", revisions.count)
        }
        return l("collection.confirmDelete")
    }

    private func beginSelection(with record: Record? = nil) {
        selectedIDs = record.map { [$0.id] } ?? []
        navigation.deletingRecordsIn = collectionID
    }

    private func endSelection() {
        selectedIDs = []
        pendingDeletion = nil
        navigation.deletingRecordsIn = nil
    }

    private func completeDeletion() {
        guard let deletion = pendingDeletion else { return }
        pendingDeletion = nil
        do {
            switch deletion {
            case .collection(let pending):
                try store.confirmDeletion(pending)
                navigation.path = []
            case .records(let revisions):
                try store.confirmRecordDeletions(in: collectionID, revisions: revisions)
                endSelection()
            }
            error = nil
        } catch { self.error = (error as? BlueError ?? .saveFailed).key }
    }

    private func recordContents(_ record: Record, collection: Collection, showIndicators: Bool = true) -> some View {
        let layout =
            typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 0))
            : AnyLayout(HStackLayout(spacing: 6))
        return layout {
            Text(record.title).font(.body.weight(.medium))
                .frame(maxWidth: .infinity, alignment: .leading)
            if showIndicators {
                RecordIndicators(record: record, collection: collection, interactive: false, compact: true)
                    .allowsHitTesting(false)
                    .frame(width: typeSize.isAccessibilitySize ? nil : 128)
            }
        }.padding(.horizontal, 20).padding(.vertical, 4).frame(minHeight: 52).contentShape(Rectangle())
    }

    private func recordRow(_ record: Record, collection: Collection) -> some View {
        Button {
            navigation.open(.record(record.id))
        } label: {
            recordContents(record, collection: collection)
        }
        .buttonStyle(BlueRowPress()).accessibilityIdentifier("row-\(record.title)")
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.43).onEnded { _ in
                UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
                navigation.open(.record(record.id))
            }
        )
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button {
                beginSelection(with: record)
            } label: {
                Image(systemName: "trash").accessibilityLabel(l("delete"))
            }.tint(.red)
        }
        .blueListRow(fullWidth: true)
    }

    private func filterOptions(_ collection: Collection) -> some View {
        let current = Binding(get: { query }, set: { navigation.queries[collectionID] = $0 })
        return ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                PropertyFlow {
                    let filters =
                        [FieldDefinition.favoriteIndicator] + collection.fields.filter { $0.kind != .favorite }
                    ForEach(filters.filter { $0.kind.isBoolean || $0.kind == .status }) { field in
                        let existing = query.filters.first { $0.fieldID == field.id }
                        PropertyControl(
                            field: field,
                            value: field.kind.isBoolean
                                ? existing?.flag.map(FieldValue.flag) : existing.map { .option($0.text) },
                            filter: true, labeled: true
                        ) { value in
                            var updated = query
                            updated.filters.removeAll { $0.fieldID == field.id }
                            if let value, field.kind.isBoolean, value.flag {
                                updated.filters.append(RecordFilter(fieldID: field.id, flag: true))
                            } else if case .option(let option) = value {
                                updated.filters.append(RecordFilter(fieldID: field.id, text: option))
                            }
                            navigation.queries[collectionID] = updated
                        }
                    }
                }
                Text(l("sort.titleLabel")).font(.headline).accessibilityAddTraits(.isHeader)
                VStack(spacing: 0) {
                    sortChoice(l("title"), id: "title", selection: current.sortField)
                    sortChoice(l("sort.updated"), id: "updated", selection: current.sortField)
                    ForEach(collection.fields) { field in
                        sortChoice(l.text(field.label), id: field.id, selection: current.sortField)
                    }
                }
                Picker(l("sort.titleLabel"), selection: current.ascending) {
                    Text(l("sort.ascending")).tag(true)
                    Text(l("sort.descending")).tag(false)
                }.pickerStyle(.segmented).accessibilityIdentifier("sortDirection")
            }
            .padding(.horizontal, 20).padding(.bottom, 18)
            .blueSheetContentSize()
        }
    }

    private func sortChoice(_ title: String, id: String, selection: Binding<String>) -> some View {
        let selected = selection.wrappedValue == id
        return Button {
            selection.wrappedValue = id
        } label: {
            HStack {
                Text(title).font(.body.weight(selected ? .semibold : .regular))
                Spacer()
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(selected ? Color.blue : Color.secondary)
                    .accessibilityHidden(true)
            }.frame(minHeight: 44).contentShape(Rectangle())
        }
        .buttonStyle(BlueRowPress())
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("sort-choice-\(id)")
    }

}

struct CollectionMenuActions: View {
    let collection: Collection
    let store: LibraryStore
    let l: Localizer
    @Binding var error: String?
    let delete: (PendingDeletion) -> Void
    var didSelect: () -> Void = {}
    var select: (() -> Void)?
    @Environment(NavigationState.self) private var navigation

    var body: some View {
        pinButton
        Button {
            didSelect()
            navigation.collectionArtworkID = collection.id
        } label: {
            Label(l("collection.changeIcon"), systemImage: "photo")
        }.accessibilityIdentifier("changeCollectionArtwork")
        if let select {
            Button(action: select) { Label(l("collection.selectItems"), systemImage: "checkmark.circle") }
                .accessibilityIdentifier("selectCollectionItems")
        }
        Button(role: .destructive, action: requestDelete) {
            BlueDeleteLabel()
        }
    }
    private var pinButton: some View {
        Button(action: togglePin) {
            Label(
                l(collection.pinned == true ? "collection.unpin" : "collection.pin"),
                systemImage: collection.pinned == true ? "pin.slash" : "pin")
        }
    }
    func togglePin() {
        didSelect()
        do {
            try store.update { state in
                guard let index = state.collections.firstIndex(where: { $0.id == collection.id }) else {
                    throw BlueError.missing
                }
                state.collections[index].pinned = state.collections[index].pinned != true
            }
            error = nil
        } catch {
            self.error = (error as? BlueError ?? .saveFailed).key
        }
    }

    func requestDelete() {
        didSelect()
        delete(
            PendingDeletion(
                kind: "collection", id: collection.id, collection: collection,
                recordRevisions: Dictionary(
                    uniqueKeysWithValues: store.records(in: collection.id).map { ($0.id, $0.revision) })))
    }

}
