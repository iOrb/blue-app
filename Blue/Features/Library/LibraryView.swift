import SwiftUI

struct LibraryView: View {
    @Environment(LibraryStore.self) private var store
    @Environment(Localizer.self) private var l
    @Environment(NavigationState.self) private var navigation
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var textSize
    @State private var search = ""
    @State private var collapsed: Set<UUID> = []
    @State private var scope = "all"
    @State private var error: String?
    private var collections: [Collection] {
        store.state.collections.filter { collection in
            (search.isEmpty || l.text(collection.title).localizedCaseInsensitiveContains(search)
                || store.records(in: collection.id).contains { $0.title.localizedCaseInsensitiveContains(search) })
        }
    }
    var body: some View {
        List {
            LazyVGrid(
                columns: Array(
                    repeating: GridItem(.flexible(), spacing: 6), count: textSize.isAccessibilitySize ? 2 : 4),
                spacing: 6
            ) {
                scopeButton("all", symbol: "square.grid.2x2")
                scopeButton("notes", symbol: "text.alignleft")
                scopeButton("collections", symbol: "square.stack")
                scopeButton("favorites", symbol: "star")
            }.listRowSeparator(.hidden).listRowInsets(EdgeInsets(top: 5, leading: 16, bottom: 8, trailing: 16))
            if scope != "notes" {
                ForEach(collections) { collection in collectionSection(collection) }
            }
            if scope != "collections" {
                let notes = store.state.notes.filter {
                    (scope != "favorites" || $0.favorite == true)
                        && (search.isEmpty || l.text($0.title).localizedCaseInsensitiveContains(search)
                            || l.text($0.markdown).localizedCaseInsensitiveContains(search))
                }.sorted { $0.updatedAt > $1.updatedAt }
                if !notes.isEmpty {
                    Section {
                        ForEach(notes) { note in
                            HStack {
                                Button {
                                    navigation.path.append(.note(note.id))
                                } label: {
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text(l.text(note.title)).font(.body.weight(.medium))
                                        Text(
                                            l.text(note.markdown).replacingOccurrences(of: "#", with: "")
                                                .replacingOccurrences(of: "\n", with: " ")
                                        )
                                        .font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
                                    }.padding(.vertical, 6)
                                }.buttonStyle(.plain).accessibilityIdentifier("note-\(l.text(note.title))")
                                IndicatorControl(field: .favoriteIndicator, selected: note.favorite == true) {
                                    var changed = note
                                    changed.favorite = !(note.favorite ?? false)
                                    do { try store.saveNote(changed, expectedRevision: note.revision) } catch {
                                        self.error = BlueError.saveFailed.key
                                    }
                                }
                            }
                        }
                    } header: {
                        Label(l("library.notes"), systemImage: "text.alignleft").textCase(nil)
                    }
                }
            }
            if store.state.collections.isEmpty && store.state.notes.isEmpty {
                VStack(alignment: .leading, spacing: 16) {
                    Text(l("library.startTitle")).font(.title2.weight(.medium))
                    Text(l("library.startHint")).font(.body).foregroundStyle(.secondary)
                    Button {
                        navigation.assistantExpanded = true
                        navigation.assistantFocused = true
                    } label: {
                        Label(l("library.askBlue"), systemImage: "sparkle")
                    }
                    .frame(minHeight: 44).accessibilityIdentifier("askBlue")
                }.padding(.vertical, 28).listRowSeparator(.hidden)
            }
            ErrorLine(key: error)
        }
        .listStyle(.plain).scrollDismissesKeyboard(.interactively)
        .searchable(text: $search, prompt: l("library.search"))
        .modifier(KeyboardDismissToolbar()).navigationTitle("Blue").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) { SettingsButton() }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {

                    NavigationLink(value: Route.newNote) { Label(l("note.new"), systemImage: "square.and.pencil") }
                    NavigationLink(value: Route.newCollection) {
                        Label(l("collection.new"), systemImage: "square.stack")
                    }
                } label: {
                    Image(systemName: "plus").frame(minWidth: 44, minHeight: 44)
                }
                .accessibilityLabel(l("create")).accessibilityIdentifier("createMenu")
            }
        }
    }
    @ViewBuilder private func scopeButton(_ key: String, symbol: String) -> some View {
        if key == "favorites" {
            IndicatorControl(field: .favoriteIndicator, selected: scope == "favorites") {
                scope = scope == "favorites" ? "all" : "favorites"
            }.frame(maxWidth: .infinity).frame(minHeight: 64).accessibilityIdentifier("scope-favorites")
        } else {
            Button {
                scope = key
            } label: {
                VStack(spacing: 5) {
                    Image(systemName: symbol).font(.body)
                    Text(l("library.scope.\(key)")).font(.caption.weight(.medium)).lineLimit(2)
                }.frame(maxWidth: .infinity).frame(minHeight: 56).padding(.vertical, 4)
                    .foregroundStyle(scope == key ? Color(uiColor: .systemBackground) : Color.primary)
                    .background(
                        scope == key ? Color.primary : Color.primary.opacity(0.055),
                        in: RoundedRectangle(cornerRadius: 18)
                    )
                    .contentShape(RoundedRectangle(cornerRadius: 18))
            }.buttonStyle(.plain).accessibilityIdentifier("scope-\(key)")
                .accessibilityAddTraits(scope == key ? .isSelected : [])
        }
    }

    @ViewBuilder private func collectionSection(_ collection: Collection) -> some View {
        let records = store.records(in: collection.id).filter {
            (scope != "favorites" || $0.isFavorite)
                && (search.isEmpty || l.text(collection.title).localizedCaseInsensitiveContains(search)
                    || $0.title.localizedCaseInsensitiveContains(search))
        }.sorted { $0.updatedAt > $1.updatedAt }
        if scope != "favorites" || !records.isEmpty {
            Section {
                if !collapsed.contains(collection.id) {
                    ForEach(records.prefix(search.isEmpty ? 2 : 30)) { record in
                        NavigationLink(value: Route.record(record.id)) {
                            RecordRow(record: record, collection: collection, directActions: false)
                        }
                    }
                    NavigationLink(value: Route.collection(collection.id)) {
                        Label(l.format("collection.viewCount", records.count), systemImage: "arrow.right")
                            .font(.subheadline).foregroundStyle(.secondary).frame(minHeight: 44)
                    }.accessibilityIdentifier("open-\(collection.title.key ?? collection.title.english)")
                }
            } header: {
                HStack(spacing: 8) {
                    Button {
                        navigation.path.append(.collection(collection.id))
                    } label: {
                        Label {
                            Text(l.text(collection.title))
                        } icon: {
                            ItemGlyph(symbol: collection.symbol)
                        }
                        .font(.headline).foregroundStyle(.primary).frame(minHeight: 44)
                    }.buttonStyle(.plain).accessibilityIdentifier(
                        "collection-\(collection.title.key ?? collection.title.english)")
                    Spacer()
                    Button {
                        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
                            if !collapsed.insert(collection.id).inserted { collapsed.remove(collection.id) }
                        }
                    } label: {
                        Image(systemName: collapsed.contains(collection.id) ? "chevron.right" : "chevron.down")
                            .font(.caption).frame(width: 44, height: 44)
                    }.accessibilityLabel(l(collapsed.contains(collection.id) ? "expand" : "collapse"))
                }.textCase(nil)
            }
        }
    }
}
