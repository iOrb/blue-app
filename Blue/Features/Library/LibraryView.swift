import SwiftUI

struct LibraryView: View {
    let section: LibrarySection
    @Environment(LibraryStore.self) private var store
    @Environment(Localizer.self) private var l
    @Environment(NavigationState.self) private var navigation
    @State private var heldCollection: Collection?
    @State private var heldNote: Note?
    @State private var heldFrame = CGRect.zero
    @State private var newEvent = false
    @State private var pendingDeletion: PendingDeletion?
    @State private var confirmingDeletion = false
    @State private var collectionError: String?
    var body: some View {
        Group {
            if section == .calendar {
                CalendarView()
            } else {
                List {
                    if section == .collections {
                        let counts = Dictionary(grouping: store.state.records, by: \.collectionID).mapValues(
                            \.count)
                        ForEach(
                            store.state.collections.filter { $0.pinned == true }
                                + store.state.collections.filter { $0.pinned != true }
                        ) { collection in
                            collectionRow(collection, count: counts[collection.id] ?? 0)
                        }
                    } else {
                        ForEach(
                            store.state.notes.sorted {
                                if ($0.pinned == true) != ($1.pinned == true) { return $0.pinned == true }
                                return $0.updatedAt > $1.updatedAt
                            }
                        ) { note in
                            noteRow(note)
                        }
                    }
                    if let error = collectionError ?? navigation.noticeKey {
                        ErrorLine(key: error).listRowSeparator(.hidden)
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
        .background(Color(uiColor: .systemBackground)).scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .top, spacing: 0) { header }
        .overlay { heldOverlay }
        .toolbar(.hidden, for: .navigationBar)
        .blueConfirmation(
            isPresented: $confirmingDeletion,
            title: l(pendingDeletion?.kind == "note" ? "note.confirmDelete" : "collection.confirmDelete")
        ) {
            guard let deletion = pendingDeletion else { return }
            pendingDeletion = nil
            do { try store.confirmDeletion(deletion) } catch {
                collectionError = (error as? BlueError ?? .saveFailed).key
            }
        }
        .blueSheet(isPresented: $newEvent, title: "", ownHeader: true, allowsExpansion: false) {
            EventEditor(date: navigation.selectedDate)
        }
    }
    private func collectionRow(_ collection: Collection, count: Int) -> some View {
        let actions = CollectionMenuActions(
            collection: collection, store: store, l: l, error: $collectionError, delete: confirm)
        return Button {
            guard heldCollection == nil, heldNote == nil else { return }
            navigation.open(.collection(collection.id))
        } label: {
            CollectionLibraryLabel(collection: collection, count: count).padding(.horizontal, 24)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("collection-\(collection.title.key ?? collection.title.english)")
        .modifier(
            BlueRowTarget { frame in
                heldFrame = frame
                heldCollection = collection
            }
        )
        .accessibilityAction(named: Text(l(collection.pinned == true ? "collection.unpin" : "collection.pin"))) {
            actions.togglePin()
        }
        .accessibilityAction(named: Text(l("delete"))) { actions.requestDelete() }
        .swipeActions(edge: .leading, allowsFullSwipe: false) {
            Button(action: actions.togglePin) {
                Image(systemName: collection.pinned == true ? "pin.slash" : "pin")
                    .accessibilityLabel(l(collection.pinned == true ? "collection.unpin" : "collection.pin"))
            }.tint(.blue)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(action: actions.requestDelete) { Image(systemName: "trash").accessibilityLabel(l("delete")) }.tint(
                .red)
        }
        .blueListRow(fullWidth: true)
    }

    private func noteLabel(_ note: Note) -> some View {
        HStack {
            Text(l.text(note.title)).font(.title3.weight(.medium))
            Spacer()
            if note.pinned == true { Image(systemName: "pin.fill").foregroundStyle(.secondary) }
        }.padding(.horizontal, 24).frame(minHeight: 54).contentShape(Rectangle())
    }

    private func noteRow(_ note: Note) -> some View {
        Button {
            guard heldCollection == nil, heldNote == nil else { return }
            navigation.open(.note(note.id))
        } label: {
            noteLabel(note)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("note-\(l.text(note.title))")
        .modifier(
            BlueRowTarget { frame in
                heldFrame = frame
                heldNote = note
            }
        )
        .swipeActions(edge: .leading, allowsFullSwipe: false) {
            Button {
                pin(note)
            } label: {
                Image(systemName: note.pinned == true ? "pin.slash" : "pin")
                    .accessibilityLabel(l(note.pinned == true ? "collection.unpin" : "collection.pin"))
            }.tint(.blue)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button {
                delete(note)
            } label: {
                Image(systemName: "trash").accessibilityLabel(l("delete"))
            }.tint(.red)
        }
        .blueListRow(fullWidth: true)
    }

    private func dismissHold() {
        heldCollection = nil
        heldNote = nil
    }

    @ViewBuilder private var heldOverlay: some View {
        if heldCollection != nil || heldNote != nil {
            GeometryReader { geometry in
                let origin = geometry.frame(in: .global).origin
                ZStack {
                    BlueRowMenu(frame: heldFrame, dismiss: dismissHold) {
                        if let collection = heldCollection {
                            CollectionMenuActions(
                                collection: collection, store: store, l: l, error: $collectionError,
                                delete: confirm, didSelect: dismissHold)
                        } else if let note = heldNote {
                            Button {
                                dismissHold()
                                pin(note)
                            } label: {
                                Label(
                                    l(note.pinned == true ? "collection.unpin" : "collection.pin"),
                                    systemImage: note.pinned == true ? "pin.slash" : "pin")
                            }
                            Button(role: .destructive) {
                                dismissHold()
                                delete(note)
                            } label: {
                                BlueDeleteLabel()
                            }
                        }
                    }
                    Group {
                        if let collection = heldCollection {
                            CollectionLibraryLabel(
                                collection: collection,
                                count: store.records(in: collection.id).count
                            )
                            .padding(.horizontal, 24)
                        } else if let note = heldNote {
                            noteLabel(note)
                        }
                    }
                    .frame(width: heldFrame.width, height: heldFrame.height)
                    .background(Color(uiColor: .secondarySystemBackground))
                    .scaleEffect(1.025)
                    .position(x: heldFrame.midX - origin.x, y: heldFrame.midY - origin.y)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                }
            }
            .ignoresSafeArea()
        }
    }

    private func pin(_ note: Note) {
        var updated = note
        updated.pinned = note.pinned != true
        do { try store.saveNote(updated, expectedRevision: note.revision) } catch {
            collectionError = (error as? BlueError ?? .saveFailed).key
        }
    }

    private func delete(_ note: Note) {
        confirm(PendingDeletion(kind: "note", id: note.id, revision: note.revision))
    }

    private func confirm(_ deletion: PendingDeletion) {
        pendingDeletion = deletion
        confirmingDeletion = true
    }

    private var header: some View {
        HStack(spacing: 4) {
            Text(l(section.titleKey)).font(.largeTitle.bold()).tracking(-1.3)
                .lineLimit(1).minimumScaleFactor(0.55).layoutPriority(1)
                .accessibilityAddTraits(.isHeader).accessibilityIdentifier("sectionTitle")
            Spacer(minLength: 8)
            SettingsButton().buttonStyle(.plain)
            if section == .calendar {
                QuietButton(key: "event.new", symbol: "plus") { newEvent = true }
                    .accessibilityIdentifier("newEvent")
            } else {
                QuietButton(
                    key: section == .notes ? "note.new" : "collection.new", symbol: "plus"
                ) {
                    navigation.open(section == .notes ? .newNote : .newCollection)
                }.accessibilityIdentifier("createMenu")
            }
        }
        .padding(.horizontal, 24).padding(.top, 6).padding(.bottom, 12)
        .frame(maxWidth: 760).frame(maxWidth: .infinity)
        .background(Color(uiColor: .systemBackground))
    }
}

private struct CollectionLibraryLabel: View {
    let collection: Collection
    let count: Int
    @Environment(Localizer.self) private var l

    var body: some View {
        HStack(spacing: 14) {
            CollectionArtworkView(artwork: collection.artwork, symbol: collection.symbol)
            Text(l.text(collection.title)).font(.title3.weight(.medium))
            Spacer()
            if collection.pinned == true { Image(systemName: "pin.fill").font(.caption) }
            Text("\(count)").font(.subheadline).foregroundStyle(.tertiary)
        }.frame(minHeight: 54).contentShape(Rectangle())
    }
}
