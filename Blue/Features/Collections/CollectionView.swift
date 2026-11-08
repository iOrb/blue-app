import SwiftUI

struct RecordRow: View {
    let record: Record
    let collection: Collection
    var directActions = true
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
    @State private var confirmDelete = false
    @State private var title = ""
    @State private var error: String?
    @FocusState private var renaming: Bool
    private var query: CollectionQuery { navigation.queries[collectionID] ?? CollectionQuery() }
    var body: some View {
        if let collection = store.collection(collectionID) {
            ScrollViewReader { scroll in
                VStack(spacing: 0) {
                    HStack {
                        QuietButton(key: "back", symbol: "chevron.left") { navigation.path.removeLast() }
                            .accessibilityIdentifier("collectionBack")
                        Spacer()
                        Menu {
                            Button(l("rename")) {
                                scroll.scrollTo("title", anchor: .top)
                                renaming = true
                            }
                            Button(role: .destructive) {
                                confirmDelete = true
                            } label: {
                                Label(l("delete"), systemImage: "minus")
                            }
                        } label: {
                            Image(systemName: "ellipsis").frame(width: 44, height: 44).contentShape(Rectangle())
                        }.buttonStyle(.plain).accessibilityLabel(l("options")).accessibilityIdentifier(
                            "collectionOptions")
                    }.padding(.horizontal, 18)
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 16) {
                            VStack(spacing: 6) {
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
                                ).font(.largeTitle.weight(.bold)).multilineTextAlignment(.center).focused($renaming)
                                    .accessibilityIdentifier("collectionTitle")
                                Text(l.format("collection.itemCount", store.records(in: collectionID).count)).font(
                                    .subheadline.weight(.medium)
                                ).foregroundStyle(.secondary)
                            }.frame(maxWidth: .infinity).padding(.top, 8).padding(.bottom, 8).id("title")
                            HStack(spacing: 10) {
                                Text(l("sort.titleLabel")).foregroundStyle(.secondary)
                                Button {
                                    navigation.queries[collectionID, default: CollectionQuery()].ascending.toggle()
                                } label: {
                                    HStack(spacing: 6) {
                                        Text(
                                            collection.fields.first { $0.id == query.sortField }.map {
                                                l.text($0.label)
                                            }
                                                ?? l("title"))
                                        Image(systemName: query.ascending ? "arrow.up" : "arrow.down").font(
                                            .caption.weight(.semibold))
                                    }.frame(minHeight: 44)
                                }.accessibilityIdentifier("sortDirection").accessibilityValue(
                                    l(query.ascending ? "sort.ascending" : "sort.descending"))
                                Spacer()
                                QuietButton(key: "record.new", symbol: "plus") {
                                    navigation.open(.newRecord(collectionID))
                                }
                                .accessibilityIdentifier("newRecord")
                            }.font(.subheadline)
                            ForEach(
                                query.apply(
                                    to: store.records(in: collectionID), fields: collection.fields, locale: l.locale)
                            ) { record in
                                HStack(alignment: .center, spacing: 10) {
                                    Button {
                                        navigation.open(.record(record.id))
                                    } label: {
                                        Text(record.title).font(.title3.weight(.medium)).frame(
                                            maxWidth: .infinity, minHeight: 44, alignment: .leading
                                        ).contentShape(Rectangle())
                                    }.buttonStyle(.plain).accessibilityIdentifier("row-\(record.title)")
                                    RecordIndicators(record: record, collection: collection, interactive: true).frame(
                                        width: 144)
                                }.padding(.bottom, 2)
                            }
                            ErrorLine(key: error ?? navigation.noticeKey)
                        }.padding(.horizontal, 24).padding(.bottom, 90)
                    }.scrollDismissesKeyboard(.interactively)
                        .background(Color(uiColor: .systemBackground)).navigationBarTitleDisplayMode(.inline)
                        .navigationBarBackButtonHidden(true)
                        .toolbar(.hidden, for: .navigationBar)
                }
            }
            .blueConfirmation(isPresented: $confirmDelete, title: l("collection.confirmDelete")) {
                do {
                    try store.confirmDeletion(
                        PendingDeletion(
                            kind: "collection", id: collectionID, collection: collection,
                            recordRevisions: Dictionary(
                                uniqueKeysWithValues: store.records(in: collectionID).map { ($0.id, $0.revision) })))
                    navigation.path = []
                } catch { self.error = (error as? BlueError ?? .saveFailed).key }
            }
            .onAppear { title = l.text(collection.title) }
            .onChange(of: l.language) { _, _ in title = l.text(collection.title) }
            .onChange(of: collection.title) { _, value in title = l.text(value) }
        }
    }
}
