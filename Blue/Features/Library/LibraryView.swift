import SwiftUI

struct LibraryView: View {
    @Environment(LibraryStore.self) private var store
    @Environment(Localizer.self) private var l
    @Environment(NavigationState.self) private var navigation
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var search = ""
    @State private var collapsed: Set<UUID> = []
    @State private var sortNewest = true
    var body: some View {
        List {
            if search.isEmpty {
                ForEach(store.state.folders.filter { $0.parentID == nil }.sorted(by: folderOrder)) { folder in
                    folderSection(folder)
                    ForEach(store.state.folders.filter { $0.parentID == folder.id }.sorted(by: folderOrder)) { child in
                        folderSection(child)
                    }
                }
            } else {
                ForEach(store.state.records.filter { $0.title.localizedCaseInsensitiveContains(search) }.prefix(60)) {
                    record in
                    Button {
                        navigation.jump(to: record, store: store, locale: l.locale)
                    } label: {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(record.title).foregroundStyle(.primary)
                            if let collection = store.collection(record.collectionID) {
                                Text(l.text(collection.title)).font(.caption).foregroundStyle(.secondary)
                            }
                        }.padding(.vertical, 5)
                    }
                }
            }
            let notes = store.state.notes.filter {
                search.isEmpty
                    ? $0.folderID == nil
                    : l.text($0.title).localizedCaseInsensitiveContains(search)
                        || l.text($0.markdown).localizedCaseInsensitiveContains(search)
            }.sorted {
                sortNewest
                    ? $0.updatedAt > $1.updatedAt
                    : l.text($0.title).localizedStandardCompare(l.text($1.title)) == .orderedAscending
            }
            Section {
                ForEach(notes) { note in
                    NavigationLink(value: Route.note(note.id)) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(l.text(note.title)).font(.body.weight(.medium))
                            Text(
                                l.text(note.markdown).replacingOccurrences(of: "#", with: "").replacingOccurrences(
                                    of: "\n", with: " ")
                            )
                            .font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
                        }.padding(.vertical, 6)
                    }.accessibilityIdentifier("note-\(l.text(note.title))")
                }
            } header: {
                Text(l("library.notes"))
            }
            if store.state.collections.isEmpty && notes.isEmpty {
                ContentUnavailableView(l("library.empty"), systemImage: "text.alignleft")
            }
        }
        .listStyle(.plain)
        .searchable(text: $search, prompt: l("library.search"))
        .modifier(KeyboardDismissToolbar()).navigationTitle(l("tab.notes")).navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) { SettingsButton() }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    NavigationLink(l("note.new"), value: Route.newNote)
                    NavigationLink(l("collection.new"), value: Route.newCollection)
                    NavigationLink(l("folder.new"), value: Route.newFolder)
                    Button(l(sortNewest ? "sort.title" : "sort.updated")) { sortNewest.toggle() }
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel(l("create")).accessibilityIdentifier("createMenu")
            }
        }
    }
    private func folderOrder(_ lhs: Folder, _ rhs: Folder) -> Bool {
        let left = store.state.collections.firstIndex { $0.folderID == lhs.id } ?? Int.max
        let right = store.state.collections.firstIndex { $0.folderID == rhs.id } ?? Int.max
        return left == right
            ? l.text(lhs.title).localizedStandardCompare(l.text(rhs.title)) == .orderedAscending : left < right
    }
    @ViewBuilder private func folderSection(_ folder: Folder) -> some View {
        let collections = store.state.collections.filter { $0.folderID == folder.id }
        Section {
            if !collapsed.contains(folder.id) {
                ForEach(collections) { collection in
                    let records = store.records(in: collection.id).sorted {
                        $0.title.localizedStandardCompare($1.title) == .orderedAscending
                    }
                    if collections.count > 1 || collection.title != folder.title {
                        NavigationLink(l.text(collection.title), value: Route.collection(collection.id))
                    }
                    ForEach(records.prefix(2)) { record in
                        NavigationLink(value: Route.record(record.id)) {
                            RecordRow(record: record, collection: collection, directActions: false)
                        }
                    }
                    NavigationLink(value: Route.collection(collection.id)) {
                        Text(l.format("collection.viewCount", records.count)).font(.subheadline).foregroundStyle(
                            .secondary)
                    }.accessibilityIdentifier("open-\(collection.title.key ?? collection.title.english)")
                }
                ForEach(store.state.notes.filter { $0.folderID == folder.id }) { note in
                    NavigationLink(l.text(note.title), value: Route.note(note.id))
                }
                if collections.isEmpty { Text(l("folder.empty")).font(.subheadline).foregroundStyle(.secondary) }
            }
        } header: {
            HStack(spacing: 8) {
                Button {
                    if let collection = collections.first {
                        navigation.path.append(.collection(collection.id))
                    } else {
                        navigation.path.append(.folder(folder.id))
                    }
                } label: {
                    HStack(spacing: 9) {
                        Image(systemName: collections.first?.symbol ?? "folder").font(.system(size: 15))
                        Text(l.text(folder.title)).font(.headline)
                    }.foregroundStyle(.primary).frame(minHeight: 44).contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityIdentifier("folder-\(folder.title.key ?? folder.title.english)")
                    .contextMenu { NavigationLink(l("folder.edit"), value: Route.folder(folder.id)) }
                Spacer()
                Button {
                    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
                        if collapsed.contains(folder.id) {
                            collapsed.remove(folder.id)
                        } else {
                            collapsed.insert(folder.id)
                        }
                    }
                } label: {
                    Image(systemName: collapsed.contains(folder.id) ? "chevron.right" : "chevron.down").font(.caption)
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel(l(collapsed.contains(folder.id) ? "expand" : "collapse"))
            }.textCase(nil).padding(.leading, folder.parentID == nil ? 0 : 14)
        }
    }
}

struct FolderEditor: View {
    var folderID: UUID?
    @Environment(LibraryStore.self) private var store
    @Environment(Localizer.self) private var l
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var parentID: UUID?
    @State private var loaded = false
    @State private var originalName = ""
    @State private var confirmDelete = false
    @State private var error: String?
    var body: some View {
        Form {
            TextField(l("title"), text: $name).accessibilityIdentifier("folderTitle")
            Picker(l("folder.parent"), selection: $parentID) {
                Text(l("folder.topLevel")).tag(nil as UUID?)
                ForEach(store.state.folders.filter { $0.parentID == nil && $0.id != folderID }) { folder in
                    Text(l.text(folder.title)).tag(Optional(folder.id))
                }
            }
            if folderID != nil {
                Button(l("folder.delete"), role: .destructive) { confirmDelete = true }
            }
            ErrorLine(key: error)
        }
        .modifier(KeyboardDismissToolbar()).navigationTitle(l(folderID == nil ? "folder.new" : "folder.edit"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(l("save")) {
                    do {
                        try Validation.title(name)
                        try store.saveFolder(Folder(id: folderID ?? UUID(), title: .user(name), parentID: parentID))
                        dismiss()
                    } catch { self.error = (error as? BlueError ?? .saveFailed).key }
                }.disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .confirmationDialog(l("folder.confirmDelete"), isPresented: $confirmDelete, titleVisibility: .visible) {
            Button(l("delete"), role: .destructive) {
                do {
                    if let folderID { try store.deleteFolder(folderID) }
                    dismiss()
                } catch { self.error = (error as? BlueError ?? .saveFailed).key }
            }
        }
        .onChange(of: l.language) { _, _ in
            if name == originalName, let folder = store.state.folders.first(where: { $0.id == folderID }) {
                name = l.text(folder.title)
                originalName = name
            }
        }
        .onAppear {
            if !loaded, let folder = store.state.folders.first(where: { $0.id == folderID }) {
                name = l.text(folder.title)
                originalName = name
                parentID = folder.parentID
            }
            loaded = true
        }
    }
}
